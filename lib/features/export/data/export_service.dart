import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cullimingo/core/raw/libraw_preview_extractor.dart';
import 'package:cullimingo/features/export/data/export_encoder.dart';
import 'package:cullimingo/features/export/domain/export_plan.dart';
import 'package:cullimingo/features/export/domain/export_preset.dart';
import 'package:flutter_libraw/flutter_libraw.dart';
import 'package:path/path.dart' as p;

/// What happened to one exported file.
enum ExportOutcome {
  /// Rendered and written.
  written,

  /// Source couldn't be read/decoded (missing file, no embedded preview).
  sourceUnreadable,

  /// An unexpected error while rendering or writing.
  error,
}

/// The result of exporting one file.
class ExportResult {
  /// Creates a result.
  const ExportResult({required this.relPath, required this.outcome});

  /// Destination-relative output path.
  final String relPath;

  /// Outcome of the render+write.
  final ExportOutcome outcome;

  /// Whether the file was written successfully.
  bool get ok => outcome == ExportOutcome.written;
}

/// A progress tick: one [last] result, [done] of [total] finished.
class ExportProgress {
  /// Creates a progress tick.
  const ExportProgress({
    required this.done,
    required this.total,
    required this.last,
  });

  /// Files processed so far.
  final int done;

  /// Total files in the plan.
  final int total;

  /// The most recent result.
  final ExportResult last;
}

/// Aggregate outcome of an export run.
class ExportSummary {
  /// Creates a summary over [results].
  const ExportSummary(this.results);

  /// Per-file results, in completion order.
  final List<ExportResult> results;

  int _count(ExportOutcome o) => results.where((r) => r.outcome == o).length;

  /// Files written successfully.
  int get written => _count(ExportOutcome.written);

  /// Files that failed (unreadable source or error).
  int get failed =>
      _count(ExportOutcome.sourceUnreadable) + _count(ExportOutcome.error);

  /// Whether every file was written.
  bool get allOk => results.isNotEmpty && results.every((r) => r.ok);
}

/// Signature of the per-file render step, injectable so tests skip the isolate.
typedef Renderer =
    Future<ExportOutcome> Function({
      required ExportItem item,
      required String destPath,
      required ExportPreset preset,
      required String? libraryPath,
    });

/// Renders [plan] into [destinationRoot] off the UI isolate, emitting an
/// [ExportProgress] as each file finishes (`BUILD_PLAN.md` §6). Up to
/// [concurrency] files render at once so decode/encode overlap across cores;
/// the UI isolate only receives ticks. Cancelling the subscription stops
/// launching new renders.
Stream<ExportProgress> runExport({
  required List<ExportItem> plan,
  required String destinationRoot,
  required ExportPreset preset,
  String? libraryPath,
  int concurrency = 4,
  Renderer renderer = _isolateRender,
}) {
  final total = plan.length;
  final controller = StreamController<ExportProgress>();
  var next = 0;
  var done = 0;
  var stopped = false;

  Future<void> worker() async {
    while (!stopped) {
      final i = next++;
      if (i >= total) return;
      final item = plan[i];
      final destPath = p.join(destinationRoot, item.relPath);
      ExportOutcome outcome;
      try {
        outcome = await renderer(
          item: item,
          destPath: destPath,
          preset: preset,
          libraryPath: libraryPath,
        );
      } on Object {
        outcome = ExportOutcome.error;
      }
      if (stopped) return;
      done++;
      if (!controller.isClosed) {
        controller.add(
          ExportProgress(
            done: done,
            total: total,
            last: ExportResult(relPath: item.relPath, outcome: outcome),
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

// Default renderer: do the read + decode + encode + write on a one-off
// background isolate so it never touches the UI isolate.
Future<ExportOutcome> _isolateRender({
  required ExportItem item,
  required String destPath,
  required ExportPreset preset,
  required String? libraryPath,
}) => Isolate.run(
  () => renderExportToFile(
    item: item,
    destPath: destPath,
    preset: preset,
    libraryPath: libraryPath,
  ),
);

/// Reads [item]'s source (embedded JPEG preview for RAW, file bytes otherwise),
/// renders it per [preset] and writes the JPEG to [destPath] (creating parent
/// folders, overwriting any prior export). Synchronous file I/O — only call it
/// inside a background isolate. Returns the [ExportOutcome].
ExportOutcome renderExportToFile({
  required ExportItem item,
  required String destPath,
  required ExportPreset preset,
  String? libraryPath,
}) {
  try {
    final source = item.isRaw
        ? _embeddedRawJpeg(item.source, libraryPath)
        : (File(item.source).existsSync()
              ? File(item.source).readAsBytesSync()
              : null);
    if (source == null) return ExportOutcome.sourceUnreadable;

    final out = renderExportBytes(
      source,
      longEdge: preset.longEdge,
      quality: preset.quality,
      format: preset.format,
      sharpen: preset.sharpen,
      maxBytes: preset.maxBytes,
      meta: item.meta,
      userRotation: item.userRotation,
    );
    if (out == null) return ExportOutcome.sourceUnreadable;

    File(destPath)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(out);
    return ExportOutcome.written;
  } on Object {
    return ExportOutcome.error;
  }
}

/// Loads libraw (from [libraryPath] or auto-discovery) and returns the embedded
/// full-res JPEG preview of [rawPath], or null if unavailable.
Uint8List? _embeddedRawJpeg(String rawPath, String? libraryPath) {
  final lib = libraryPath ?? LibRawPreviewExtractor.resolveLibraryPath();
  if (lib == null || !File(rawPath).existsSync()) return null;
  try {
    final dylib = DynamicLibrary.open(lib);
    return extractRawThumbnail(FlutterLibRawBindings(dylib), rawPath);
  } on Object {
    return null;
  }
}
