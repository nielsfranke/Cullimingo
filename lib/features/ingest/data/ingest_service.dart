import 'dart:async';
import 'dart:isolate';

import 'package:cullimingo/features/ingest/data/verified_copy.dart';
import 'package:cullimingo/features/ingest/domain/rename_template.dart';
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
        // swapping in its own extension so the pairing survives the rename.
        companions: [
          for (final c in s.companions)
            (source: c, relPath: p.setExtension(uniqueRel, p.extension(c))),
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

/// Scans [sourceRoot] into [IngestSource]s (the slow, source-dependent step).
/// Capture time comes from the file mtime (cameras set it to the shot time on
/// the card); EXIF is only read when [withCamera] is set (`{camera}` token),
/// since reading EXIF for a whole card is slow. Cache the result and re-run
/// [buildPlan] on template/shoot changes — those don't need a re-scan.
Future<List<IngestSource>> scanSources(
  String sourceRoot, {
  bool includeVideos = true,
  bool withCamera = false,
}) async {
  final files = await scanFolderFast(sourceRoot, includeVideos: includeVideos);
  final byPath = withCamera
      ? {
          for (final e in await scanExif(files.map((f) => f.path).toList()))
            e.path: e,
        }
      : const <String, ScannedExif>{};

  return [
    for (final f in files)
      IngestSource(
        path: f.path,
        capturedAt: byPath[f.path]?.capturedAt ?? f.mtime,
        camera: byPath[f.path]?.camera,
        sizeBytes: f.sizeBytes,
        companions: f.companions,
      ),
  ];
}

/// Convenience: scan [sourceRoot] then build the plan for [template]/[shoot].
Future<IngestPlan> planIngest({
  required String sourceRoot,
  required RenameTemplate template,
  String shoot = '',
  bool includeVideos = true,
}) async {
  final sources = await scanSources(
    sourceRoot,
    includeVideos: includeVideos,
    withCamera: template.pattern.contains('{camera}'),
  );
  return buildPlan(sources: sources, template: template, shoot: shoot);
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
  /// Creates a summary over [results].
  const IngestSummary(this.results);

  /// Per-file results, in run order.
  final List<CopyResult> results;

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
      _count(CopyOutcome.error);

  /// Whether every file landed safely.
  bool get allOk => results.every((r) => r.ok);
}

/// Signature of the verified-copy step, injectable so tests skip the isolate.
typedef Copier =
    Future<CopyResult> Function({
      required String source,
      required List<String> destinations,
      bool verify,
    });

/// Runs [plan] into one or two [destinationRoots] off the UI isolate, emitting
/// an [IngestProgress] as each file finishes. Up to [concurrency] copies run at
/// once so disk reads/writes/verification overlap across files (a big win on
/// SSDs; harmless on slower media where the device serialises anyway).
/// Cancelling the subscription stops launching new copies.
Stream<IngestProgress> runIngest({
  required IngestPlan plan,
  required List<String> destinationRoots,
  bool verify = true,
  int concurrency = 4,
  Copier copier = _isolateCopy,
}) {
  final total = plan.items.length;
  final controller = StreamController<IngestProgress>();
  var next = 0;
  var done = 0;
  var bytesDone = 0;
  var stopped = false;

  // Each worker pulls the next index until the plan is exhausted. The shared
  // counters are safe: only the copy itself runs in an isolate, the
  // coordination here stays on this single isolate's event loop.
  Future<void> worker() async {
    while (!stopped) {
      final i = next++;
      if (i >= total) return;
      final item = plan.items[i];
      final dests = [
        for (final root in destinationRoots) p.join(root, item.relPath),
      ];
      final result = await copier(
        source: item.source,
        destinations: dests,
        verify: verify,
      );
      // Carry the companions (sidecars) along once the media itself is safe.
      if (result.ok) {
        for (final c in item.companions) {
          if (stopped) break;
          await copier(
            source: c.source,
            destinations: [
              for (final root in destinationRoots) p.join(root, c.relPath),
            ],
            verify: verify,
          );
        }
      }
      if (stopped) return;
      done++;
      bytesDone += item.sizeBytes;
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
      await Future.wait([for (var w = 0; w < workerCount; w++) worker()]);
      if (!controller.isClosed) await controller.close();
    }
    ..onCancel = () => stopped = true;

  return controller.stream;
}

// Default copier: run the verified copy on a one-off background isolate so the
// hash + I/O never touch the UI isolate (`BUILD_PLAN.md` §0.6).
Future<CopyResult> _isolateCopy({
  required String source,
  required List<String> destinations,
  bool verify = true,
}) => Isolate.run(
  () => verifiedCopy(
    source: source,
    destinations: destinations,
    verify: verify,
  ),
);
