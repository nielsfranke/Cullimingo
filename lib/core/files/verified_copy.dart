import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cullimingo/core/files/posix_fs.dart';
import 'package:path/path.dart' as p;

/// What happened to one source file during a verified copy.
enum CopyOutcome {
  /// Copied to every destination and the hash verified.
  copied,

  /// Every destination already held an identical copy (resume / re-run).
  skipped,

  /// A destination already exists but differs — left untouched, never
  /// overwritten silently (`BUILD_PLAN.md` §5 Phase 3).
  conflict,

  /// The freshly written copy's hash didn't match the source (corrupt/
  /// incomplete write); the bad copy was deleted.
  verifyFailed,

  /// The source file was missing or unreadable.
  sourceMissing,

  /// The source changed (size or modification time) while it was being read
  /// — still being written by a camera, tether or sync tool. Fresh copies are
  /// deleted: they hold a version that no longer exists.
  sourceChanged,

  /// The source was modified moments before the copy started — most likely
  /// still being written (a tether, a sync tool, a camera over USB). Held
  /// back untouched; importing again once it has settled copies it.
  sourceBusy,

  /// Any other I/O error.
  error,
}

/// Result of copying one source to one or more destinations.
class CopyResult {
  /// Creates a copy result.
  const CopyResult({
    required this.source,
    required this.outcome,
    this.message,
  });

  /// The source path this result is for.
  final String source;

  /// What happened.
  final CopyOutcome outcome;

  /// Human-readable detail for non-success outcomes (which dest, what error).
  final String? message;

  /// Whether the source landed safely at every destination (copied or already
  /// present and identical).
  bool get ok =>
      outcome == CopyOutcome.copied || outcome == CopyOutcome.skipped;
}

/// Copies [source] to each of [destinations], verifying integrity by SHA-256
/// (Photo-Mechanic-style ingest, `BUILD_PLAN.md` §5 Phase 3). Heavy I/O — the
/// caller runs this off the UI isolate.
///
/// Per destination: an identical existing file is a clean skip (resume); an
/// existing file that differs — or anything at that name that isn't a plain
/// file, like a symlink — is a [CopyOutcome.conflict] and is **never**
/// touched; otherwise the file is copied and its hash re-checked. The worst
/// outcome across all destinations is returned.
///
/// A copy never appears under its final name half-written. It is written to
/// a hidden part file beside the destination (`.<name>.<random>.part`,
/// created exclusively, so a symlink planted at that name can't redirect the
/// write), verified there, and only then published under the real name with
/// [publishNoReplace] — which refuses rather than replaces. Writing straight
/// to the final name used to leave half a photo under it when the app was
/// killed or the drive dropped; the next import called that a conflict, kept
/// it, and never imported the photo. Two runs copying into the same folder
/// can't truncate or delete each other's files either: each only ever
/// touches its own part files.
///
/// A source modified less than [quietPeriod] ago (either way: a clock skewed
/// into the future by more than that is a camera clock, not a write) is held
/// back as [CopyOutcome.sourceBusy] before anything is written. The mid-copy
/// check catches a file that changes *during* the copy; a half-written file
/// that happens to sit idle for a moment only shows up here. The app's
/// copiers pass [kSourceQuietPeriod]; the default of none is for callers
/// whose sources are known to be complete.
///
/// [alwaysVerify] names destinations read back even when [verify] is off —
/// the import's backup copy, which nobody looks at until the day it's needed.
///
/// [volumeGuards] maps destination roots to the mount point their volume was
/// on when the run was checked (`checkDestinations`). Before writing under
/// such a root, the copy makes sure it's still there and on that volume —
/// never creating it — so a drive unplugged mid-run fails its files instead
/// of filling the system disk through an empty mount point.
///
/// [onProgress] is called as the copy moves (every chunk read, written or
/// hashed) — the heartbeat `watchedCopy` uses to tell a slow copy from a
/// hung one.
Future<CopyResult> verifiedCopy({
  required String source,
  required List<String> destinations,
  bool verify = true,
  Set<String> alwaysVerify = const {},
  Duration quietPeriod = Duration.zero,
  Map<String, String> volumeGuards = const {},
  void Function()? onProgress,
}) async {
  final src = File(source);
  if (!src.existsSync()) {
    return CopyResult(
      source: source,
      outcome: CopyOutcome.sourceMissing,
      message: 'Source not found',
    );
  }
  // The copy and its hash come from one read of the source, so verification
  // only proves the copy matches *that read*. If the file changes meanwhile,
  // the copy is stale while every check passes — and a handoff *move* then
  // deletes the newer original. Compare the source before and after instead.
  final before = src.statSync();
  if (quietPeriod > Duration.zero &&
      DateTime.now().difference(before.modified).abs() < quietPeriod) {
    return CopyResult(
      source: source,
      outcome: CopyOutcome.sourceBusy,
      message:
          'Changed seconds ago (still being written?) — not copied, '
          'import again in a moment',
    );
  }

  // Split into destinations that need writing vs. ones already present. A
  // symlink (even a dangling one) or a folder at the name is never written
  // through or compared — following it would put the copy somewhere else.
  final fresh = <String>[];
  final existing = <String>[];
  for (final dest in destinations) {
    final type = FileSystemEntity.typeSync(dest, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      fresh.add(dest);
    } else if (type == FileSystemEntityType.file) {
      existing.add(dest);
    } else {
      return CopyResult(
        source: source,
        outcome: CopyOutcome.conflict,
        message: "Destination exists and isn't a plain file: $dest",
      );
    }
  }
  for (final dest in fresh) {
    final problem = _volumeProblem(dest, volumeGuards);
    if (problem != null) {
      return CopyResult(
        source: source,
        outcome: CopyOutcome.error,
        message: problem,
      );
    }
  }
  final parts = {for (final dest in fresh) dest: partPathFor(dest)};

  try {
    // The source hash is only needed to compare existing dests or to verify a
    // fresh copy — skip it entirely otherwise (pure copy is ~2× faster).
    bool verifies(String dest) => verify || alwaysVerify.contains(dest);
    final needHash = existing.isNotEmpty || fresh.any(verifies);
    Digest? sourceHash;
    if (fresh.isNotEmpty) {
      // One source read copies to every fresh destination (and hashes it if
      // we'll need the hash).
      sourceHash = await _streamCopy(
        src,
        parts.values,
        hash: needHash,
        onProgress: onProgress,
      );
    } else if (needHash) {
      sourceHash = await _hashFile(src, onProgress);
    }

    // Existing dests: identical → skip; different → conflict (left untouched).
    for (final dest in existing) {
      if (await _hashFile(File(dest), onProgress) != sourceHash) {
        parts.values.forEach(_deleteQuietly);
        return CopyResult(
          source: source,
          outcome: CopyOutcome.conflict,
          message: 'Destination exists and differs: $dest',
        );
      }
    }

    // Verify each freshly written copy by re-reading it.
    for (final MapEntry(key: dest, value: part) in parts.entries) {
      if (!verifies(dest)) continue;
      if (await _hashFile(File(part), onProgress) != sourceHash) {
        parts.values.forEach(_deleteQuietly);
        return CopyResult(
          source: source,
          outcome: CopyOutcome.verifyFailed,
          message: 'Hash mismatch after copy: $dest',
        );
      }
    }

    final after = src.statSync();
    if (after.size != before.size || after.modified != before.modified) {
      parts.values.forEach(_deleteQuietly);
      return CopyResult(
        source: source,
        outcome: CopyOutcome.sourceChanged,
        message: 'Source changed while copying (still being written?)',
      );
    }

    // Keep the capture-time mtime on the copy, like the original card file:
    // re-importing or re-scanning copies (no EXIF read) dates them by mtime,
    // and a fresh "now" put a whole backup into today's date folder. Set on
    // the part file, so the published name never shows any other date.
    for (final part in parts.values) {
      try {
        File(part).setLastModifiedSync(before.modified);
      } on Object {
        // Best effort: some filesystems (SMB, FAT edge cases) refuse it.
      }
    }

    // Publish. A name taken since the scan above (another run copying the
    // same photo into the same folder) is compared, never replaced.
    var published = 0;
    for (final MapEntry(key: dest, value: part) in parts.entries) {
      if (publishNoReplace(part, dest) == PublishOutcome.published) {
        published++;
        continue;
      }
      final same =
          FileSystemEntity.typeSync(dest, followLinks: false) ==
              FileSystemEntityType.file &&
          await _hashFile(File(dest), onProgress) ==
              await _hashFile(File(part), onProgress);
      _deleteQuietly(part);
      if (!same) {
        parts.values.forEach(_deleteQuietly);
        return CopyResult(
          source: source,
          outcome: CopyOutcome.conflict,
          message: 'Destination appeared during the copy and differs: $dest',
        );
      }
    }

    return CopyResult(
      source: source,
      outcome: published == 0 ? CopyOutcome.skipped : CopyOutcome.copied,
    );
  } on Object catch (e) {
    // Don't leave half-written part files behind. Published copies stay: each
    // was verified (or would be, by a re-run) before it got its name.
    parts.values.forEach(_deleteQuietly);
    return CopyResult(
      source: source,
      outcome: CopyOutcome.error,
      message: '$e',
    );
  }
}

/// Why [dest] must not be written right now, or null: its guarded root is
/// gone or no longer on the volume it was checked on.
String? _volumeProblem(String dest, Map<String, String> guards) {
  for (final MapEntry(key: root, value: mount) in guards.entries) {
    if (!p.isWithin(root, dest)) continue;
    if (!Directory(root).existsSync() ||
        volumeInfo(root)?.mountPoint != mount) {
      return "Destination drive isn't connected any more ($root)";
    }
  }
  return null;
}

/// How long a source must have been left alone before the app copies it —
/// see `verifiedCopy`'s `quietPeriod`.
const Duration kSourceQuietPeriod = Duration(seconds: 3);

/// Suffix of the hidden part files a copy is written to before it's
/// published. Not a supported photo type, so a part file left behind by a
/// crash is never listed, imported or culled as a photo.
const String kPartFileSuffix = '.part';

final Random _partRandom = Random.secure();

/// A fresh hidden part-file path beside [dest]:
/// `.<name>.<12 hex random>.<epoch seconds>.part`. The random tag keeps
/// concurrent copies of the same name (two handoffs into one folder) in
/// separate files; the creation time in the name is what the leftover sweep
/// (`part_cleanup.dart`) judges age by — file times can't be trusted for
/// that: a copy sets its part file's mtime to the capture date, and exFAT and
/// FAT keep no separate ctime.
String partPathFor(String dest, {DateTime? now}) {
  final tag = List.generate(
    6,
    (_) => _partRandom.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final created = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  return p.join(
    p.dirname(dest),
    '.${p.basename(dest)}.$tag.$created$kPartFileSuffix',
  );
}

/// Streams [src] once, writing every chunk to each of [parts] — each created
/// exclusively (so nothing already at that name, symlinks included, is ever
/// written through) and flushed to disk before it's closed. When [hash] is
/// set it also feeds the stream through SHA-256 (so the source is read a
/// single time for copy + hash) and returns the digest; otherwise `null`.
///
/// Writes go through [RandomAccessFile] rather than an `IOSink`: a sink only
/// reports a write error (ENOSPC on a full card/SSD, EIO on a dropped mount)
/// on its `done` future, which escaped as an *uncaught* error, killed the copy
/// isolate and left the import's progress stream open forever. Awaited
/// `writeFrom` calls throw where they fail, so the caller's catch cleans up.
Future<Digest?> _streamCopy(
  File src,
  Iterable<String> parts, {
  required bool hash,
  void Function()? onProgress,
}) async {
  Digest? digest;
  Sink<List<int>>? hashInput;
  if (hash) {
    final hashSink = ChunkedConversionSink<Digest>.withCallback(
      (digests) => digest = digests.single,
    );
    hashInput = sha256.startChunkedConversion(hashSink);
  }

  final outs = <RandomAccessFile>[];
  (Object, StackTrace)? closeError;
  try {
    for (final part in parts) {
      File(part).parent.createSync(recursive: true);
      // O_EXCL: fails on anything already there, a dangling symlink included.
      File(part).createSync(exclusive: true);
      outs.add(await File(part).open(mode: FileMode.writeOnly));
    }
    await for (final chunk in src.openRead()) {
      hashInput?.add(chunk);
      for (final out in outs) {
        await out.writeFrom(chunk);
      }
      onProgress?.call();
    }
    // On disk before verify reads it back and before it gets its real name.
    for (final out in outs) {
      await out.flush();
    }
  } finally {
    hashInput?.close();
    // Close every file even if one fails, then surface the first failure.
    for (final out in outs) {
      try {
        await out.close();
      } on Object catch (e, st) {
        closeError ??= (e, st);
      }
    }
  }
  if (closeError case (final e, final st)) Error.throwWithStackTrace(e, st);
  return digest;
}

/// Streams [file] through SHA-256 so even a 50 MB RAW never loads fully in RAM.
Future<Digest> _hashFile(File file, [void Function()? onProgress]) async {
  Digest? digest;
  final sink = ChunkedConversionSink<Digest>.withCallback(
    (digests) => digest = digests.single,
  );
  final input = sha256.startChunkedConversion(sink);
  await file.openRead().forEach((chunk) {
    input.add(chunk);
    onProgress?.call();
  });
  input.close();
  return digest!;
}

void _deleteQuietly(String path) {
  try {
    File(path).deleteSync();
  } on Object {
    // Best effort.
  }
}
