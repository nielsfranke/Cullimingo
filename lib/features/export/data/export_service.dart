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

/// Renders [plan] off the UI isolate, emitting an [ExportProgress] as each file
/// finishes (`BUILD_PLAN.md` §6). Files land under [destinationRoot], unless
/// [nextToOriginals] is set — then each output goes beside its own source file
/// (optionally inside [subfolder], e.g. `Exports/`), so a shoot exports in
/// place. Up to [concurrency] files render at once so decode/encode overlap
/// across cores; the UI isolate only receives ticks. Cancelling the
/// subscription stops launching new renders.
///
/// By default each of the [concurrency] slots runs a long-lived worker isolate
/// that loads libraw **once** and renders its share of files — the earlier
/// per-file `Isolate.run` + dylib reload was exactly the pattern `PreviewPool`
/// exists to avoid (500 RAWs meant 500 isolate spawns + libraw inits). Tests
/// inject [renderer] to skip isolates entirely.
Stream<ExportProgress> runExport({
  required List<ExportItem> plan,
  required ExportPreset preset,
  String? destinationRoot,
  bool nextToOriginals = false,
  String subfolder = '',
  String? libraryPath,
  int concurrency = 4,
  Renderer? renderer,
}) {
  assert(
    nextToOriginals || destinationRoot != null,
    'runExport needs a destinationRoot unless nextToOriginals is set',
  );
  final total = plan.length;
  final controller = StreamController<ExportProgress>();
  var next = 0;
  var done = 0;
  var stopped = false;

  // Where one item's output file lands. Next-to-originals resolves per source
  // dir (plus the optional subfolder); otherwise everything shares the root.
  String destPathFor(ExportItem item) {
    if (nextToOriginals) {
      final base = subfolder.isEmpty
          ? p.dirname(item.source)
          : p.join(p.dirname(item.source), subfolder);
      return p.join(base, item.relPath);
    }
    return p.join(destinationRoot!, item.relPath);
  }

  Future<void> worker() async {
    // One long-lived render isolate per slot (unless a test injected a
    // renderer); it loads libraw once and serves this worker's whole share.
    // A failed spawn falls back to the per-file Isolate.run path.
    _RenderWorker? iso;
    if (renderer == null) {
      try {
        iso = await _RenderWorker.spawn(libraryPath);
      } on Object {
        iso = null;
      }
    }
    try {
      while (!stopped) {
        final i = next++;
        if (i >= total) return;
        final item = plan[i];
        final destPath = destPathFor(item);
        ExportOutcome outcome;
        try {
          outcome = iso != null
              ? await iso.render(item, destPath, preset)
              : await (renderer ?? _isolateRender)(
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
    } finally {
      iso?.dispose();
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

// Fallback renderer (worker spawn failed): read + decode + encode + write on
// a one-off background isolate so it never touches the UI isolate.
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

/// A long-lived export render isolate: libraw is loaded once at spawn, then
/// jobs are rendered strictly sequentially — the owner awaits each [render]
/// before sending the next, so replies pair up without job ids.
class _RenderWorker {
  _RenderWorker._(this._isolate, this._commands, this._replies, this._reply);

  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _replies;
  final StreamIterator<Object?> _reply;

  /// Spawns the worker and waits for it to hand back its command port.
  static Future<_RenderWorker> spawn(String? libraryPath) async {
    final replies = ReceivePort();
    final Isolate isolate;
    try {
      isolate = await Isolate.spawn(
        _exportWorkerMain,
        [replies.sendPort, libraryPath],
        debugName: 'export-worker',
      );
    } on Object {
      replies.close();
      rethrow;
    }
    final reply = StreamIterator<Object?>(replies);
    await reply.moveNext();
    final commands = reply.current! as SendPort;
    return _RenderWorker._(isolate, commands, replies, reply);
  }

  /// Renders one file on the worker and returns its outcome.
  Future<ExportOutcome> render(
    ExportItem item,
    String destPath,
    ExportPreset preset,
  ) async {
    _commands.send([item, destPath, preset]);
    if (!await _reply.moveNext()) return ExportOutcome.error; // worker died
    return ExportOutcome.values[_reply.current! as int];
  }

  /// Kills the worker isolate.
  void dispose() {
    _isolate.kill(priority: Isolate.immediate);
    _replies.close();
  }
}

void _exportWorkerMain(List<Object?> init) {
  final toMain = init[0]! as SendPort;
  final libraryPath = init[1] as String?;

  // Load libraw once for this worker's lifetime — the whole point of the
  // long-lived isolate (a per-file dylib open costs an init per RAW).
  FlutterLibRawBindings? libraw;
  final lib = libraryPath ?? LibRawPreviewExtractor.resolveLibraryPath();
  if (lib != null) {
    try {
      libraw = FlutterLibRawBindings(DynamicLibrary.open(lib));
    } on Object {
      libraw = null;
    }
  }

  final inbox = ReceivePort()
    ..listen((message) {
      final job = message! as List<Object?>;
      final outcome = renderExportToFile(
        item: job[0]! as ExportItem,
        destPath: job[1]! as String,
        preset: job[2]! as ExportPreset,
        libraryPath: libraryPath,
        libraw: libraw,
      );
      toMain.send(outcome.index);
    });

  toMain.send(inbox.sendPort);
}

/// Reads [item]'s source (embedded JPEG preview for RAW, file bytes otherwise),
/// renders it per [preset] and writes the JPEG to [destPath] (creating parent
/// folders, overwriting any prior export). Synchronous file I/O — only call it
/// inside a background isolate. Returns the [ExportOutcome].
ExportOutcome renderExportToFile({
  required ExportItem item,
  required String destPath,
  required ExportPreset preset,
  String? libraryPath,
  FlutterLibRawBindings? libraw,
}) {
  try {
    final source = item.isRaw
        ? _embeddedRawJpeg(item.source, libraryPath, libraw)
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

/// Returns the embedded full-res JPEG preview of [rawPath], or null if
/// unavailable. With [preloaded] bindings (a pooled export worker) no dylib is
/// opened; otherwise libraw is loaded from [libraryPath] / auto-discovery.
Uint8List? _embeddedRawJpeg(
  String rawPath,
  String? libraryPath,
  FlutterLibRawBindings? preloaded,
) {
  if (!File(rawPath).existsSync()) return null;
  if (preloaded != null) {
    try {
      return extractRawThumbnail(preloaded, rawPath);
    } on Object {
      return null;
    }
  }
  final lib = libraryPath ?? LibRawPreviewExtractor.resolveLibraryPath();
  if (lib == null) return null;
  try {
    final dylib = DynamicLibrary.open(lib);
    return extractRawThumbnail(FlutterLibRawBindings(dylib), rawPath);
  } on Object {
    return null;
  }
}
