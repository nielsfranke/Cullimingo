import 'dart:async';

import 'package:cullimingo/core/files/part_cleanup.dart';
import 'package:cullimingo/core/files/sidecar_path.dart';
import 'package:cullimingo/core/files/verified_copy.dart';
import 'package:cullimingo/core/files/watched_copy.dart';
import 'package:cullimingo/core/naming/rename_template.dart';
import 'package:cullimingo/features/library/data/folder_scanner.dart';
import 'package:path/path.dart' as p;

/// One source file resolved enough to plan its destination: absolute [path],
/// resolved [capturedAt] (EXIF or mtime), and [camera].
class IngestSource {
  /// Creates an ingest source.
  const IngestSource({
    required this.path,
    required this.capturedAt,
    this.camera,
    this.sizeBytes = 0,
    this.companions = const [],
  });

  /// Absolute source path.
  final String path;

  /// Capture time (EXIF `DateTimeOriginal`, else file mtime).
  final DateTime capturedAt;

  /// Camera make/model, when known.
  final String? camera;

  /// File size in bytes.
  final int sizeBytes;

  /// Sibling sidecar/companion file paths to carry along (`.xmp`, `.thm`, …).
  final List<String> companions;
}

/// A planned copy: one [source] to a destination-relative path [relPath].
class IngestItem {
  /// Creates a plan item.
  const IngestItem({
    required this.source,
    required this.relPath,
    this.sizeBytes = 0,
    this.companions = const [],
  });

  /// Absolute source path.
  final String source;

  /// Destination path relative to the chosen root, from the rename template.
  final String relPath;

  /// Source file size in bytes.
  final int sizeBytes;

  /// Companion files copied alongside, each renamed to share this item's
  /// destination basename (e.g. the matching `.xmp`).
  final List<({String source, String relPath})> companions;
}

/// The full set of planned copies — drives the live preview and the run.
class IngestPlan {
  /// Creates a plan.
  const IngestPlan(this.items);

  /// The planned items, in copy order.
  final List<IngestItem> items;

  /// Total bytes to copy (per destination).
  int get totalBytes => items.fold(0, (sum, i) => sum + i.sizeBytes);

  /// The destination-relative sub-folder every item shares (e.g.
  /// `2026/2026-07-06_Shoot`), or `null` when items land directly at the
  /// destination root (a flat template) or span more than one sub-folder (a
  /// card spanning several shoot dates with a dated template). Lets the
  /// caller open the folder a run actually landed in, instead of always the
  /// whole destination root.
  String? get commonSubfolder {
    if (items.isEmpty) return null;
    final dirs = items.map((i) => _relDir(i.relPath)).toSet();
    if (dirs.length != 1) return null;
    final dir = dirs.first;
    return dir.isEmpty ? null : dir;
  }
}

// [IngestItem.relPath] always uses `/` (see [RenameTemplate.pathFor]),
// regardless of platform, so this splits on it directly rather than using
// `package:path`'s dirname (which assumes the host platform's separator).
String _relDir(String relPath) {
  final i = relPath.lastIndexOf('/');
  return i < 0 ? '' : relPath.substring(0, i);
}

/// The day (time truncated) [dt] falls on, so photos from the same day group
/// together regardless of time-of-day.
DateTime dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// Distinct capture dates in [sources] with a photo count each, oldest first.
/// Powers the ingest dialog's per-day filter chips — a card carrying more
/// than one shoot's leftovers shows one chip per day found.
List<MapEntry<DateTime, int>> captureDateCounts(List<IngestSource> sources) {
  final counts = <DateTime, int>{};
  for (final s in sources) {
    final day = dateOnly(s.capturedAt);
    counts[day] = (counts[day] ?? 0) + 1;
  }
  return counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
}

/// Returns [sources] with any whose capture date (day-only) is in
/// [excludedDates] removed. An empty [excludedDates] returns [sources]
/// unchanged. Used by the ingest dialog's "only import these days" filter —
/// applied client-side over an already-scanned source list, so toggling a
/// day never re-scans.
List<IngestSource> excludeCaptureDates(
  List<IngestSource> sources,
  Set<DateTime> excludedDates,
) {
  if (excludedDates.isEmpty) return sources;
  return sources
      .where((s) => !excludedDates.contains(dateOnly(s.capturedAt)))
      .toList();
}

/// Builds an [IngestPlan] from resolved [sources] (pure, unit-testable). Orders
/// by capture time then path so `{seq}` is stable, then resolves within-batch
/// destination collisions by appending `_2`, `_3`, … so no copy clobbers
/// another (`BUILD_PLAN.md` §5 Phase 3).
IngestPlan buildPlan({
  required List<IngestSource> sources,
  required RenameTemplate template,
  String shoot = '',
}) {
  final ordered = [...sources]
    ..sort((a, b) {
      final byTime = a.capturedAt.compareTo(b.capturedAt);
      return byTime != 0 ? byTime : a.path.compareTo(b.path);
    });

  final used = <String>{};
  final items = <IngestItem>[];
  for (var i = 0; i < ordered.length; i++) {
    final s = ordered[i];
    final rel = template.pathFor(
      RenameInput(
        capturedAt: s.capturedAt,
        originalName: p.basename(s.path),
        sequence: i + 1,
        camera: s.camera,
        shoot: shoot,
      ),
    );
    final uniqueRel = _unique(rel, used);
    items.add(
      IngestItem(
        source: s.path,
        relPath: uniqueRel,
        sizeBytes: s.sizeBytes,
        // Each companion follows the photo's (possibly de-duplicated) path,
        // swapping in its own extension so the pairing survives the rename
        // (a per-file `IMG.JPG.xmp` keeps the full new filename instead).
        companions: [
          for (final c in s.companions)
            (source: c, relPath: followSidecarPath(c, s.path, uniqueRel)),
        ],
      ),
    );
  }
  return IngestPlan(items);
}

String _unique(String rel, Set<String> used) {
  if (used.add(rel.toLowerCase())) return rel;
  final ext = p.extension(rel);
  final base = rel.substring(0, rel.length - ext.length);
  var n = 2;
  while (!used.add('${base}_$n$ext'.toLowerCase())) {
    n++;
  }
  return '${base}_$n$ext';
}

/// A scanned source: the files to plan from, plus whatever the scan couldn't
/// read. A non-empty [unreadable] means the card holds files the import will
/// never see — the dialog and the summary must say so, or the card gets
/// formatted with photos still on it.
class SourceScan {
  /// Creates a source scan.
  const SourceScan(this.sources, {this.unreadable = const []});

  /// The files found, with capture time and camera resolved.
  final List<IngestSource> sources;

  /// Folders/files on the source the scan couldn't read.
  final List<ScanProblem> unreadable;
}

/// Scans [sourceRoot] into [IngestSource]s (the slow, source-dependent step).
/// Capture time is the EXIF `DateTimeOriginal`, read for every file (header
/// only, on a background isolate) so date folders match when the photo was
/// taken; the file mtime is the fallback when a file has no usable date (an
/// impossible one is rejected by the reader). Cache the result and re-run
/// [buildPlan] on template/shoot changes — those don't need a re-scan.
/// [scanner] lists the source (injectable for tests).
Future<SourceScan> scanSources(
  String sourceRoot, {
  bool includeVideos = true,
  FolderScanner scanner = scanFolder,
}) async {
  final scan = await scanner(sourceRoot, includeVideos: includeVideos);
  final files = scan.files;
  final byPath = {
    for (final e in await scanExif(files.map((f) => f.path).toList()))
      e.path: e,
  };

  return SourceScan(
    [
      for (final f in files)
        IngestSource(
          path: f.path,
          capturedAt: byPath[f.path]?.capturedAt ?? f.mtime,
          camera: byPath[f.path]?.camera,
          sizeBytes: f.sizeBytes,
          companions: f.companions,
        ),
    ],
    unreadable: scan.unreadable,
  );
}

/// Progress tick during a run: [done] of [total] processed, with the [last]
/// result.
class IngestProgress {
  /// Creates a progress tick.
  const IngestProgress({
    required this.done,
    required this.total,
    required this.bytesDone,
    required this.last,
  });

  /// Files processed so far.
  final int done;

  /// Total files in the plan.
  final int total;

  /// Bytes of source media copied so far (for a throughput readout).
  final int bytesDone;

  /// The most recent copy result.
  final CopyResult last;
}

/// Aggregate outcome of a run.
class IngestSummary {
  /// Creates a summary over [results]. [planned] is the plan's size (defaults
  /// to the results); [cancelled] marks a run the user stopped early;
  /// [unreadable] lists what the source scan couldn't read.
  const IngestSummary(
    this.results, {
    int? planned,
    this.cancelled = false,
    this.unreadable = const [],
  }) : planned = planned ?? -1;

  /// Per-file results, in run order.
  final List<CopyResult> results;

  /// Files in the plan (`-1` = not given, i.e. every planned file has a
  /// result).
  final int planned;

  /// Whether the user cancelled the run.
  final bool cancelled;

  /// Folders/files on the source the scan couldn't read, so never imported.
  final List<ScanProblem> unreadable;

  /// Planned files never copied because the run was cancelled.
  int get notStarted =>
      planned < 0 ? 0 : (planned - results.length).clamp(0, planned);

  int _count(CopyOutcome o) => results.where((r) => r.outcome == o).length;

  /// Files freshly copied + verified.
  int get copied => _count(CopyOutcome.copied);

  /// Files already present and identical (skipped).
  int get skipped => _count(CopyOutcome.skipped);

  /// Destinations that existed and differed (not overwritten).
  int get conflicts => _count(CopyOutcome.conflict);

  /// Files that failed verification, were missing, or errored.
  int get failed =>
      _count(CopyOutcome.verifyFailed) +
      _count(CopyOutcome.sourceMissing) +
      _count(CopyOutcome.sourceChanged) +
      _count(CopyOutcome.error);

  /// Files held back because they were still being written (not in
  /// [failed]): running again once they have settled copies them.
  int get stillBeingWritten => _count(CopyOutcome.sourceBusy);

  /// Whether every planned file landed safely — never true for a cancelled
  /// run, which used to read "Import complete" over a partial import, nor
  /// when part of the source couldn't be read (its files were never planned).
  bool get allOk =>
      !cancelled &&
      notStarted == 0 &&
      unreadable.isEmpty &&
      results.every((r) => r.ok);
}

/// Signature of the verified-copy step, injectable so tests skip the isolate.
/// [alwaysVerify] names the destinations read back whatever `verify` says.
typedef Copier =
    Future<CopyResult> Function({
      required String source,
      required List<String> destinations,
      bool verify,
      Set<String> alwaysVerify,
    });

/// Runs [plan] into one or two [destinationRoots] off the UI isolate, emitting
/// an [IngestProgress] as each file finishes. Up to [concurrency] copies run at
/// once so disk reads/writes/verification overlap across files (a big win on
/// SSDs; harmless on slower media where the device serialises anyway).
/// When [shouldStop] returns true no new file is started, but copies already
/// running finish and are still reported, and then the stream closes — so a
/// cancelled run's summary covers every file that actually landed. Cancelling
/// the subscription also stops launching new copies, but drops the results of
/// the ones in flight; prefer [shouldStop].
///
/// A copy that hangs (a dropped network share) is given up on by the default
/// copier's stall watchdog (`watchedCopy`). After a cancel, copies still in
/// flight get [cancelGrace] to finish; then the run stops waiting for them
/// and reports them as failed ("cancelled mid-copy"), so Cancel always ends
/// the run.
///
/// [volumeGuards] (from `checkDestinations`) make the default copier refuse
/// to write under a root whose drive has gone since the run was checked.
///
/// [verify] governs the primary destination (the first root). Every further
/// root is a backup and is always verified: an unverified backup is only
/// found to be bad on the day it's needed.
Stream<IngestProgress> runIngest({
  required IngestPlan plan,
  required List<String> destinationRoots,
  bool verify = true,
  int concurrency = 4,
  Copier? copier,
  bool Function()? shouldStop,
  Duration cancelGrace = const Duration(seconds: 5),
  Map<String, String> volumeGuards = const {},
}) {
  final total = plan.items.length;
  final controller = StreamController<IngestProgress>();
  var next = 0;
  var done = 0;
  var bytesDone = 0;
  var stopped = false;

  // Completes once the run stops waiting for copies in flight (cancel grace
  // over, or the listener gone). The default copier kills its isolate then.
  final abandon = Completer<void>();
  void abandonInFlight() {
    if (!abandon.isCompleted) abandon.complete();
  }

  final copyOne =
      copier ??
      ({
        required String source,
        required List<String> destinations,
        bool verify = true,
        Set<String> alwaysVerify = const {},
      }) => watchedCopy(
        source: source,
        destinations: destinations,
        verify: verify,
        alwaysVerify: alwaysVerify,
        volumeGuards: volumeGuards,
        abandon: abandon.future,
      );

  // Each worker pulls the next index until the plan is exhausted. The shared
  // counters are safe: only the copy itself runs in an isolate, the
  // coordination here stays on this single isolate's event loop.
  // A copier that throws (rather than returning an error result) must not
  // kill its worker: the stream would never close and the dialog would sit on
  // "Importing…" forever.
  Future<CopyResult> copy(String source, List<String> destinations) async {
    try {
      return await Future.any([
        copyOne(
          source: source,
          destinations: destinations,
          verify: verify,
          alwaysVerify: destinations.skip(1).toSet(),
        ),
        abandon.future.then(
          (_) => CopyResult(
            source: source,
            outcome: CopyOutcome.error,
            message: kCopyAbandonedMessage,
          ),
        ),
      ]);
    } on Object catch (e) {
      return CopyResult(
        source: source,
        outcome: CopyOutcome.error,
        message: '$e',
      );
    }
  }

  Future<void> worker() async {
    while (!stopped && !(shouldStop?.call() ?? false)) {
      final i = next++;
      if (i >= total) return;
      final item = plan.items[i];
      final dests = [
        for (final root in destinationRoots) p.join(root, item.relPath),
      ];
      var result = await copy(item.source, dests);
      // Carry the companions (sidecars) along once the media itself is safe.
      // The item reports its *worst* outcome: a photo that landed but lost
      // its `.xmp`/`.thm` used to count as fully ok — the summary said
      // "all imported" while the marks quietly stayed behind on the card.
      if (result.ok) {
        for (final c in item.companions) {
          if (stopped) break;
          final companion = await copy(c.source, [
            for (final root in destinationRoots) p.join(root, c.relPath),
          ]);
          if (result.ok && !companion.ok) {
            result = CopyResult(
              source: c.source,
              outcome: companion.outcome,
              message: companion.message,
            );
          }
        }
      }
      if (stopped) return;
      done++;
      // Only bytes actually written count toward the throughput readout — a
      // skipped or failed file used to spike it.
      if (result.outcome == CopyOutcome.copied) bytesDone += item.sizeBytes;
      if (!controller.isClosed) {
        controller.add(
          IngestProgress(
            done: done,
            total: total,
            bytesDone: bytesDone,
            last: result,
          ),
        );
      }
    }
  }

  controller
    ..onListen = () async {
      final workerCount = total == 0
          ? 0
          : (concurrency < 1 ? 1 : (concurrency > total ? total : concurrency));
      // Part files a crashed or killed earlier run left in these folders.
      // Alongside the copies, not before them: this run's own part files are
      // fresh, so the cleanup never touches them.
      unawaited(
        removeStalePartFiles({
          for (final root in destinationRoots)
            for (final item in plan.items) ...[
              p.dirname(p.join(root, item.relPath)),
              for (final c in item.companions)
                p.dirname(p.join(root, c.relPath)),
            ],
        }),
      );
      // Watch for a cancel while copies are in flight: give them the grace
      // period, then stop waiting.
      Timer? grace;
      final watch = Timer.periodic(const Duration(milliseconds: 200), (t) {
        if (!(shouldStop?.call() ?? false)) return;
        t.cancel();
        grace = Timer(cancelGrace, abandonInFlight);
      });
      await Future.wait([for (var w = 0; w < workerCount; w++) worker()]);
      watch.cancel();
      grace?.cancel();
      if (!controller.isClosed) await controller.close();
    }
    ..onCancel = () {
      stopped = true;
      abandonInFlight();
    };

  return controller.stream;
}
