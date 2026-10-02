import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

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
/// existing file that differs is a [CopyOutcome.conflict] and is **never**
/// overwritten; otherwise the file is copied and its hash re-checked, deleting
/// the copy on a [CopyOutcome.verifyFailed]. The worst outcome across all
/// destinations is returned.
Future<CopyResult> verifiedCopy({
  required String source,
  required List<String> destinations,
  bool verify = true,
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

  // Split into destinations that need writing vs. ones already present.
  final fresh = <String>[];
  final existing = <String>[];
  for (final dest in destinations) {
    (File(dest).existsSync() ? existing : fresh).add(dest);
  }

  try {
    // The source hash is only needed to compare existing dests or to verify a
    // fresh copy — skip it entirely otherwise (pure copy is ~2× faster).
    final needHash = verify || existing.isNotEmpty;
    Digest? sourceHash;
    if (fresh.isNotEmpty) {
      // One source read copies to every fresh destination (and hashes it if
      // we'll need the hash).
      sourceHash = await _streamCopy(src, fresh, hash: needHash);
    } else if (needHash) {
      sourceHash = await _hashFile(src);
    }

    // Existing dests: identical → skip; different → conflict (left untouched).
    for (final dest in existing) {
      if (await _hashFile(File(dest)) != sourceHash) {
        return CopyResult(
          source: source,
          outcome: CopyOutcome.conflict,
          message: 'Destination exists and differs: $dest',
        );
      }
    }

    // Verify each freshly written copy by re-reading it.
    if (verify) {
      for (final dest in fresh) {
        if (await _hashFile(File(dest)) != sourceHash) {
          _deleteQuietly(dest);
          return CopyResult(
            source: source,
            outcome: CopyOutcome.verifyFailed,
            message: 'Hash mismatch after copy: $dest',
          );
        }
      }
    }

    final after = src.statSync();
    if (after.size != before.size || after.modified != before.modified) {
      fresh.forEach(_deleteQuietly);
      return CopyResult(
        source: source,
        outcome: CopyOutcome.sourceChanged,
        message: 'Source changed while copying (still being written?)',
      );
    }

    // Keep the capture-time mtime on the copy, like the original card file:
    // re-importing or re-scanning copies (no EXIF read) dates them by mtime,
    // and a fresh "now" put a whole backup into today's date folder.
    if (fresh.isNotEmpty) {
      final mtime = src.lastModifiedSync();
      for (final dest in fresh) {
        try {
          File(dest).setLastModifiedSync(mtime);
        } on Object {
          // Best effort: some filesystems (SMB, FAT edge cases) refuse it.
        }
      }
    }

    return CopyResult(
      source: source,
      outcome: fresh.isEmpty ? CopyOutcome.skipped : CopyOutcome.copied,
    );
  } on Object catch (e) {
    fresh.forEach(_deleteQuietly); // don't leave half-written files behind
    return CopyResult(
      source: source,
      outcome: CopyOutcome.error,
      message: '$e',
    );
  }
}

/// Streams [src] once, writing every chunk to each of [dests]. When [hash] is
/// set it also feeds the stream through SHA-256 (so the source is read a single
/// time for copy + hash) and returns the digest; otherwise returns `null`.
///
/// Writes go through [RandomAccessFile] rather than an `IOSink`: a sink only
/// reports a write error (ENOSPC on a full card/SSD, EIO on a dropped mount)
/// on its `done` future, which escaped as an *uncaught* error, killed the copy
/// isolate and left the import's progress stream open forever. Awaited
/// `writeFrom` calls throw where they fail, so the caller's catch cleans up.
Future<Digest?> _streamCopy(
  File src,
  List<String> dests, {
  required bool hash,
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
    for (final dest in dests) {
      File(dest).parent.createSync(recursive: true);
      outs.add(await File(dest).open(mode: FileMode.writeOnly));
    }
    await for (final chunk in src.openRead()) {
      hashInput?.add(chunk);
      for (final out in outs) {
        await out.writeFrom(chunk);
      }
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
Future<Digest> _hashFile(File file) async {
  Digest? digest;
  final sink = ChunkedConversionSink<Digest>.withCallback(
    (digests) => digest = digests.single,
  );
  final input = sha256.startChunkedConversion(sink);
  await file.openRead().forEach(input.add);
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
