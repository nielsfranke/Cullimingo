import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:cullimingo/core/files/sidecar_path.dart';
import 'package:cullimingo/core/files/verified_copy.dart';
import 'package:path/path.dart' as p;

/// Whether a transfer copies files to the destination or *moves* them — a move
/// deletes each source (and its sidecar) only after the copy has verified, so
/// an interrupted or failed move never loses the original.
enum TransferMode {
  /// Duplicate the files at the destination, leaving the originals.
  copy,

  /// Copy-then-delete: remove each source once its copy is verified.
  move,
}

/// A planned transfer: absolute [source] → [relPath] under the destination
/// root, with an optional [sidecar] (`.xmp`) carried along and renamed to keep
/// the pairing.
class TransferItem {
  /// Creates a transfer item.
  const TransferItem({
    required this.source,
    required this.relPath,
    this.sidecar,
  });

  /// Absolute source path.
  final String source;

  /// Destination path relative to the chosen root (the basename, de-duplicated
  /// within the batch).
  final String relPath;

  /// The matching sidecar to carry along, or null when the photo has none.
  final ({String source, String relPath})? sidecar;
}

/// Builds a transfer plan for [sources] (absolute photo paths) into a flat
/// destination: each keeps its basename, within-batch collisions get `_2`,
/// `_3`, … so no file clobbers another (same rule as ingest). When
/// [includeSidecars] is set, an existing `.xmp` sidecar is paired with each
/// photo and renamed to share the (de-duplicated) basename.
Future<List<TransferItem>> buildTransferPlan(
  List<String> sources, {
  bool includeSidecars = true,
}) async {
  final used = <String>{};
  final items = <TransferItem>[];
  for (final source in sources) {
    final rel = _unique(p.basename(source), used);
    ({String source, String relPath})? sidecar;
    if (includeSidecars) {
      final sidecarSrc = sidecarPath(source);
      // Async exists() (not existsSync) so a plan over an iCloud-synced folder
      // never stalls the UI isolate (matches the metadata sidecar readers).
      // ignore: avoid_slow_async_io
      if (await File(sidecarSrc).exists()) {
        sidecar = (source: sidecarSrc, relPath: p.setExtension(rel, '.xmp'));
      }
    }
    items.add(TransferItem(source: source, relPath: rel, sidecar: sidecar));
  }
  return items;
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

/// Progress tick during a run: [done] of [total] photos handled, with the
/// [last] copy result (the sidecar copy is not ticked separately).
class TransferProgress {
  /// Creates a progress tick.
  const TransferProgress({
    required this.done,
    required this.total,
    required this.last,
  });

  /// Photos processed so far.
  final int done;

  /// Total photos in the plan.
  final int total;

  /// The most recent photo copy result.
  final CopyResult last;
}

/// Aggregate outcome of a transfer run.
class TransferSummary {
  /// Creates a summary over [results].
  const TransferSummary(this.results);

  /// Per-photo results, in completion order.
  final List<CopyResult> results;

  int _count(CopyOutcome o) => results.where((r) => r.outcome == o).length;

  /// Photos that landed safely at the destination (freshly copied or already
  /// present and identical).
  int get transferred => results.where((r) => r.ok).length;

  /// Destinations that already existed and differed — left untouched, source
  /// kept even on a move.
  int get conflicts => _count(CopyOutcome.conflict);

  /// Photos that failed verification, were missing, or errored.
  int get failed =>
      _count(CopyOutcome.verifyFailed) +
      _count(CopyOutcome.sourceMissing) +
      _count(CopyOutcome.error);

  /// Whether every photo landed safely.
  bool get allOk => results.isNotEmpty && results.every((r) => r.ok);
}

/// Signature of the verified-copy step, injectable so tests skip the isolate.
typedef Copier =
    Future<CopyResult> Function({
      required String source,
      required List<String> destinations,
      bool verify,
    });

/// Copies (or moves) [plan] into [destinationRoot] off the UI isolate, emitting
/// a [TransferProgress] as each photo finishes. Up to [concurrency] transfers
/// run at once so disk I/O + verification overlap across files. Cancelling the
/// subscription stops launching new transfers.
///
/// On [TransferMode.move] the source (and its sidecar) is deleted only after
/// the copy verifies — a [CopyOutcome.conflict] or failure keeps the original.
/// A destination that resolves to the source path itself is a no-op skip (never
/// deleting the only copy).
Stream<TransferProgress> runTransfer({
  required List<TransferItem> plan,
  required String destinationRoot,
  required TransferMode mode,
  bool verify = true,
  int concurrency = 4,
  Copier copier = _isolateCopy,
}) {
  final total = plan.length;
  final controller = StreamController<TransferProgress>();
  var next = 0;
  var done = 0;
  var stopped = false;

  Future<void> worker() async {
    while (!stopped) {
      final i = next++;
      if (i >= total) return;
      final item = plan[i];
      final dest = p.join(destinationRoot, item.relPath);

      // Guard: transferring a file onto itself would, on a move, delete the one
      // and only copy. Treat it as a clean skip.
      final CopyResult result;
      if (p.equals(dest, item.source)) {
        result = CopyResult(source: item.source, outcome: CopyOutcome.skipped);
      } else {
        result = await copier(
          source: item.source,
          destinations: [dest],
          verify: verify,
        );
        if (result.ok && item.sidecar != null && !stopped) {
          final sidecarResult = await copier(
            source: item.sidecar!.source,
            destinations: [p.join(destinationRoot, item.sidecar!.relPath)],
            verify: verify,
          );
          // Only a verified sidecar copy may delete the source — a failed
          // copy would otherwise erase the marks' one remaining home.
          if (mode == TransferMode.move && sidecarResult.ok) {
            _deleteQuietly(item.sidecar!.source);
          }
        }
        // Delete the source only once its copy is safely at the destination.
        // The !stopped guard matches the sidecar block above: a cancel between
        // the two must not move the photo while stranding its sidecar.
        if (result.ok && mode == TransferMode.move && !stopped) {
          _deleteQuietly(item.source);
        }
      }

      if (stopped) return;
      done++;
      if (!controller.isClosed) {
        controller.add(
          TransferProgress(done: done, total: total, last: result),
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
// hash + I/O never touch the UI isolate (`BUILD_PLAN.md` §0.6 / rule #2).
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

void _deleteQuietly(String path) {
  try {
    File(path).deleteSync();
  } on Object {
    // Best effort — a left-behind source after a verified copy is harmless.
  }
}
