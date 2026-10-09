import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:cullimingo/core/cache/vips.dart';
import 'package:cullimingo/core/files/host_command.dart';
import 'package:cullimingo/core/files/supported_files.dart';
import 'package:cullimingo/core/logging/app_logger.dart';
import 'package:cullimingo/core/raw/jpeg_resize.dart';
import 'package:cullimingo/core/raw/libraw_preview_extractor.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/core/raw/raw_display_jpeg.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_libraw/flutter_libraw.dart';

class _Job {
  _Job(this.id, this.path, this.longEdge, this.cancel);
  final int id;
  final String path;
  final int longEdge;
  final CancelToken? cancel;
}

/// Tag of the worker → pool message `[tag, jobId]` sent when a job enters a
/// slow decode — the LibRaw demosaic fallback or a HEIF (see
/// [PreviewPool.slowJobTimeout]).
@visibleForTesting
const String previewPoolDemosaicTag = 'demosaic';

/// A persistent pool of worker isolates that extract thumbnails. Each worker
/// loads libraw **once**. Jobs are served visible-first (on-screen cells jump
/// ahead of off-screen prefetch batches; FIFO within each tier), and off-screen
/// jobs are additionally cancelled by the auto-disposed thumbnail providers
/// before a worker ever picks them up — so the queue drains to the cells the
/// user is actually looking at fast (`BUILD_PLAN.md` §2).
///
/// Implements [PreviewExtractor], so it drops into `PreviewCache` in place of
/// the per-call `PreviewService` (which spawned an isolate and reloaded libraw
/// for every single thumbnail).
///
/// Worker protocol (all lists): a worker registers with `[workerId, port]`,
/// may announce a slow demosaic with `[previewPoolDemosaicTag, jobId]`, and
/// answers with `[jobId, TransferableTypedData?, port, cachedPath?]`, where
/// `cachedPath` is the RAW whose demosaic it is holding (see [DemosaicCache]).
class PreviewPool implements PreviewExtractor {
  /// Creates a pool. [workers] defaults to cores-1 (clamped 1–8); [librawPath]
  /// overrides dylib discovery. [workerEntry] replaces the worker isolate's
  /// entry point (tests only).
  PreviewPool({
    int? workers,
    String? librawPath,
    this.enableVips = true,
    this.fastJobTimeout = const Duration(seconds: 12),
    this.slowJobTimeout = const Duration(seconds: 60),
    @visibleForTesting void Function(List<Object?>)? workerEntry,
  }) : _workerCount = (workers ?? (Platform.numberOfProcessors - 1)).clamp(
         1,
         8,
       ),
       _librawPath = librawPath ?? LibRawPreviewExtractor.resolveLibraryPath(),
       _workerEntry = workerEntry ?? _previewWorkerMain;

  final int _workerCount;
  final String? _librawPath;
  final void Function(List<Object?>) _workerEntry;

  /// Whether workers load libvips. It spawns process-global threads that keep a
  /// spawned isolate from terminating, which hangs the test process (the app
  /// exits via the OS, so it's fine there). Pool-logic tests pass `false`.
  final bool enableVips;

  /// How long a dispatched job may run before its worker is presumed dead or
  /// hung (a native RAW/vips decode can segfault or OOM-kill the isolate, which
  /// is uncatchable). Nearly every job — embedded JPEG, bitmap downscale,
  /// video poster — takes milliseconds, so a hung one is reclaimed quickly.
  final Duration fastJobTimeout;

  /// The budget a job gets once its worker announces a slow decode — the
  /// LibRaw demosaic fallback, or a HEIF that may need a full HEVC decode —
  /// which can legitimately take much longer on a slow external drive or CPU.
  /// Counted from the announcement (GitHub #5).
  final Duration slowJobTimeout;

  // Live workers by id, with the reverse port→id map filled at registration —
  // so a job timeout can identify and kill exactly the worker that hung, and a
  // late answer from an already-killed worker is recognisably stale.
  final Map<int, Isolate> _workers = {};
  final Map<SendPort, int> _portOwner = {};
  // Each in-flight job and the worker it was dispatched to.
  final Map<int, _Job> _inFlight = {};
  final Map<int, SendPort> _dispatched = {};
  final List<SendPort> _free = [];
  // Which RAW each worker holds a demosaic of, and which RAWs are being
  // demosaiced right now (→ by whom). Another tier of such a file waits for
  // that worker instead of decoding the same file again in parallel (#7).
  final Map<SendPort, String> _warm = {};
  final Map<String, SendPort> _demosaicing = {};
  // Two FIFOs so on-screen cells jump ahead of off-screen prefetch batches
  // (`BUILD_PLAN.md` §2): _dispatch always drains _visible before _prefetch,
  // and within each queue serves oldest-first (top cells, built first, render
  // first). A fast scroll queues a big prefetch batch behind whatever's on
  // screen, so the viewport still fills first.
  final Queue<_Job> _visible = Queue<_Job>();
  final Queue<_Job> _prefetch = Queue<_Job>();
  final Map<int, Completer<Uint8List?>> _waiting = {};
  // Watchdog per *dispatched* job (none while a job waits in _pending), so a
  // worker that never answers is detected and replaced instead of permanently
  // shrinking the pool (which dead-stopped thumbnails after a few RAW folders).
  final Map<int, Timer> _timers = {};
  ReceivePort? _results;
  bool _started = false;
  bool _disposed = false;
  int _nextId = 0;
  int _spawnCount = 0;

  Future<void> _ensureStarted() async {
    if (_started) return;
    _started = true;
    _results = ReceivePort()..listen(_onMessage);
    for (var i = 0; i < _workerCount; i++) {
      await _spawnWorker();
    }
  }

  Future<void> _spawnWorker() async {
    if (_disposed) return;
    final workerId = _spawnCount++;
    final iso = await Isolate.spawn(_workerEntry, [
      _results!.sendPort,
      _librawPath,
      enableVips,
      workerId,
    ], debugName: 'preview-worker-$workerId');
    if (_disposed) {
      // dispose() ran while the spawn was in flight — don't leak the isolate.
      iso.kill(priority: Isolate.immediate);
      return;
    }
    _workers[workerId] = iso;
  }

  void _onMessage(Object? message) {
    // Never let a malformed message throw out of here: an uncaught error in the
    // results listener would silently freeze the entire pool.
    try {
      final list = message! as List<Object?>;
      if (list[0] == previewPoolDemosaicTag) {
        _onDemosaicStarted(list[1]! as int);
        return;
      }
      if (list.length == 2) {
        // A worker registering as free: [workerId, port].
        final workerId = list[0]! as int;
        final port = list[1]! as SendPort;
        if (!_workers.containsKey(workerId)) return; // killed before it spoke
        _portOwner[port] = workerId;
        _free.add(port);
        _dispatch();
        return;
      }
      // A job result: [jobId, transferable bytes, port, cachedPath?].
      final id = list[0]! as int;
      final transfer = list[1] as TransferableTypedData?;
      final bytes = transfer?.materialize().asUint8List();
      final worker = list[2]! as SendPort;
      final cachedPath = list.length > 3 ? list[3] as String? : null;
      _dispatched.remove(id);
      final job = _inFlight.remove(id);
      // A worker the watchdog already killed can still have an answer sitting
      // in the mailbox — drop it, its replacement is running. Re-adding it
      // used to grow the pool by one on every slow-but-alive timeout.
      if (!_portOwner.containsKey(worker)) return;
      if (job != null && _demosaicing[job.path] == worker) {
        _demosaicing.remove(job.path);
      }
      if (cachedPath == null) {
        _warm.remove(worker);
      } else {
        _warm[worker] = cachedPath;
      }
      _timers.remove(id)?.cancel();
      _waiting.remove(id)?.complete(bytes);
      _free.add(worker);
      _dispatch();
    } on Object catch (e) {
      // Drop the bad message; keep the pool alive. (An unguarded throw here
      // once froze the whole pool — workers' results were silently dropped.)
      appTalker.warning('PreviewPool dropped a bad worker message: $e');
    }
  }

  // The worker entered the demosaic fallback: legitimately slow, so swap the
  // job's short watchdog for the long one, and hold back other tiers of the
  // same file until this decode (and its cached bitmap) is done.
  void _onDemosaicStarted(int id) {
    final port = _dispatched[id];
    final job = _inFlight[id];
    if (port == null || job == null || !_portOwner.containsKey(port)) return;
    _timers.remove(id)?.cancel();
    _timers[id] = Timer(slowJobTimeout, () => _onJobTimeout(id));
    _demosaicing[job.path] = port;
  }

  void _dispatch() {
    while (_free.isNotEmpty) {
      final job = _nextJob();
      if (job == null) break;
      // Skip jobs the caller no longer needs (scrolled off-screen) without
      // burning a worker, so the queue drains to the visible cells fast (§2).
      if (job.cancel?.isCancelled ?? false) {
        _waiting.remove(job.id)?.complete(null);
        continue;
      }
      final port = _takeWorkerFor(job.path)
        ..send([job.id, job.path, job.longEdge]);
      _dispatched[job.id] = port;
      _inFlight[job.id] = job;
      _timers[job.id] = Timer(fastJobTimeout, () => _onJobTimeout(job.id));
    }
  }

  // Visible cells first, then prefetch; oldest-first within each (FIFO). A job
  // whose file is being demosaiced right now waits (keeping its place) so it
  // can reuse that worker's decode instead of repeating it.
  _Job? _nextJob() {
    for (final queue in [_visible, _prefetch]) {
      if (_demosaicing.isEmpty) {
        if (queue.isNotEmpty) return queue.removeFirst();
        continue;
      }
      for (final job in queue) {
        if (!_demosaicing.containsKey(job.path)) {
          queue.remove(job);
          return job;
        }
      }
    }
    return null;
  }

  // The free worker already holding [path]'s demosaic, else any free worker.
  SendPort _takeWorkerFor(String path) {
    for (var i = 0; i < _free.length; i++) {
      if (_warm[_free[i]] == path) return _free.removeAt(i);
    }
    return _free.removeLast();
  }

  // A dispatched job didn't answer in time → its worker likely crashed or hung
  // on a native decode. Unstick the waiting cell (placeholder), kill the hung
  // worker (it holds an isolate plus native libraw/vips state — merely
  // abandoning it leaked one worker per timeout, and a late answer grew the
  // pool by one), and top the pool back up with a fresh one.
  void _onJobTimeout(int id) {
    _timers.remove(id);
    final job = _inFlight.remove(id);
    final completer = _waiting.remove(id);
    if (completer == null || completer.isCompleted) return;
    appTalker.warning(
      'PreviewPool worker timed out on job $id '
      '(likely crashed/OOM/hung); killing it and respawning',
    );
    final port = _dispatched.remove(id);
    if (port != null) {
      final workerId = _portOwner.remove(port);
      final iso = workerId == null ? null : _workers.remove(workerId);
      iso?.kill(priority: Isolate.immediate);
      _warm.remove(port);
      _demosaicing.removeWhere((_, owner) => owner == port);
    }
    if (job != null) _demosaicing.remove(job.path);
    completer.complete(null);
    unawaited(_spawnWorker());
    // Jobs held back behind that demosaic may run on the other workers now.
    _dispatch();
  }

  @override
  Future<Uint8List?> thumbnail(
    String path, {
    int longEdge = 512,
    CancelToken? cancel,
    JobPriority priority = JobPriority.visible,
  }) async {
    if (_disposed || (cancel?.isCancelled ?? false)) return null;
    await _ensureStarted();
    // Re-check after the await: a dispose() racing the first worker spawn has
    // already emptied the queues — enqueueing now would hang this future
    // forever (no worker, no timer, nobody to complete it).
    if (_disposed) return null;

    final id = _nextId++;
    final completer = Completer<Uint8List?>();
    _waiting[id] = completer;
    (priority == JobPriority.visible ? _visible : _prefetch).add(
      _Job(id, path, longEdge, cancel),
    );
    _dispatch();
    return completer.future;
  }

  /// Kills the workers and fails any outstanding requests.
  Future<void> dispose() async {
    _disposed = true;
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    for (final iso in _workers.values) {
      iso.kill(priority: Isolate.immediate);
    }
    _workers.clear();
    _portOwner.clear();
    _dispatched.clear();
    _inFlight.clear();
    _warm.clear();
    _demosaicing.clear();
    _free.clear();
    _visible.clear();
    _prefetch.clear();
    _results?.close();
    for (final c in _waiting.values) {
      if (!c.isCompleted) c.complete(null);
    }
    _waiting.clear();
  }
}

void _previewWorkerMain(List<Object?> init) {
  final toMain = init[0]! as SendPort;
  final librawPath = init[1] as String?;
  final inbox = ReceivePort();

  FlutterLibRawBindings? libraw;
  if (librawPath != null) {
    try {
      libraw = FlutterLibRawBindings(DynamicLibrary.open(librawPath));
    } on Object {
      libraw = null;
    }
  }
  // Load libvips once per worker for fast native downscale + EXIF auto-rotate.
  final enableVips = init[2]! as bool;
  final vips = enableVips ? Vips.tryLoad() : null;
  final workerId = init[3]! as int;
  // This worker's last demosaic, so the grid, loupe and full tiers of a RAW
  // without a usable embedded JPEG don't each repeat it (GitHub #7).
  final demosaics = DemosaicCache();

  inbox.listen((message) async {
    final job = message! as List<Object?>;
    final id = job[0]! as int;
    final path = job[1]! as String;
    final longEdge = job[2]! as int;
    Uint8List? bytes;
    try {
      bytes = await _extractInWorker(
        path,
        longEdge,
        libraw,
        vips,
        demosaics,
        onSlowDecode: () => toMain.send([previewPoolDemosaicTag, id]),
      );
    } on Object {
      bytes = null;
    }
    // TransferableTypedData moves the buffer instead of copying it — a plain
    // send deep-copies, which is fine for a 200 KB grid thumb but a real stall
    // for the full tier (a 45-MP RAW's embedded JPEG is 10–40 MB, copied right
    // when the user expects the 100% zoom to be instant).
    toMain.send([
      id,
      if (bytes == null) null else TransferableTypedData.fromList([bytes]),
      inbox.sendPort,
      demosaics.path,
    ]);
  });

  toMain.send([workerId, inbox.sendPort]); // register as free
}

// Async only so a RAW demosaic can collect LibRaw's data-error reports (see
// rawDisplayJpeg); the pool never sends a worker its next job before it has
// answered, so jobs still run strictly one at a time per worker.
Future<Uint8List?> _extractInWorker(
  String path,
  int longEdge,
  FlutterLibRawBindings? libraw,
  Vips? vips,
  DemosaicCache demosaics, {
  required void Function() onSlowDecode,
}) async {
  // Videos: grab a poster frame via the OS (QuickLook), never load the whole
  // file. Returns null (→ placeholder) when no frame can be produced.
  if (isVideoPath(path)) {
    return _videoPoster(path, longEdge <= 0 ? 1024 : longEdge, vips);
  }

  Uint8List? source;
  if (isRawPath(path)) {
    if (libraw == null) return null;
    // The embedded JPEG, or a demosaic when that's missing or tiny. Full tier
    // (longEdge <= 0): the full embedded JPEG or a full-resolution demosaic,
    // undownscaled, for true 100% pixel-peeping in the loupe.
    final raw = await rawDisplayJpeg(
      libraw,
      path,
      longEdge: longEdge,
      vips: () => vips,
      cache: demosaics,
      onDemosaic: onSlowDecode,
    );
    if (raw == null) return null;
    if (raw.demosaiced || longEdge <= 0) return raw.bytes;
    source = raw.bytes;
  } else {
    // A HEIF may need a full HEVC decode (see `Vips.thumbnail`), which can
    // outlast the short watchdog on a big file and a slow CPU (#10).
    if (isHeifPath(path)) onSlowDecode();
    // Full-resolution request: the original bitmap, undownscaled.
    if (longEdge <= 0) return _extractFull(path, vips);
    final file = File(path);
    if (!file.existsSync()) return null;
    source = file.readAsBytesSync(); // original (JPEG/PNG/HEIF/…)
  }

  // Downscale to a small, correctly-oriented JPEG with libvips (fast, also
  // decodes HEIF); fall back to the pure-Dart path. Only hand back the original
  // un-transcoded if it's a bitmap Flutter can render (not HEIF/RAW).
  final thumb =
      vips?.thumbnail(source, longEdge) ?? downscaleToJpeg(source, longEdge);
  if (thumb != null) return thumb;
  return isBitmapPath(path) ? source : null;
}

// The full-resolution source for the loupe's 100% zoom of a non-RAW: no
// downscale, no re-encode where avoidable. A Flutter-renderable bitmap
// (JPEG/PNG) → the untouched original file; anything else (HEIF …) → a
// full-size vips transcode so Flutter can display it.
Uint8List? _extractFull(String path, Vips? vips) {
  final file = File(path);
  if (!file.existsSync()) return null;
  final bytes = file.readAsBytesSync();
  if (isBitmapPath(path)) return bytes;
  // Large edge = "don't upscale"; vips caps at the source's native size.
  return vips?.thumbnail(bytes, 20000) ?? bytes;
}

/// Extracts a video poster frame: QuickLook (`qlmanage -t`) on macOS,
/// `ffmpegthumbnailer` (falling back to `ffmpeg`) on Linux. No-op (→
/// placeholder) on other platforms, or if nothing usable is installed.
Uint8List? _videoPoster(String path, int longEdge, Vips? vips) {
  if (Platform.isMacOS) return _videoPosterMacOS(path, longEdge, vips);
  if (Platform.isLinux) return _videoPosterLinux(path, longEdge, vips);
  return null;
}

Uint8List? _videoPosterMacOS(String path, int longEdge, Vips? vips) {
  Directory? tmp;
  try {
    tmp = Directory.systemTemp.createTempSync('cm_ql');
    Process.runSync('qlmanage', [
      '-t',
      '-s',
      '$longEdge',
      '-o',
      tmp.path,
      path,
    ]);
    final pngs = tmp
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.png'))
        .toList();
    if (pngs.isEmpty) return null;
    return _reencodePoster(pngs.first.readAsBytesSync(), longEdge, vips);
  } on Object {
    return null;
  } finally {
    try {
      tmp?.deleteSync(recursive: true);
    } on Object {
      // best effort
    }
  }
}

/// `ffmpegthumbnailer` picks a representative frame (not just frame 0, often
/// black) and is purpose-built for this, so it's tried first; `ffmpeg` itself
/// (near-universally installed already, for other tooling) is the fallback.
/// Neither is a new Dart dependency — both are external binaries, same shape
/// as macOS's `qlmanage`.
Uint8List? _videoPosterLinux(String path, int longEdge, Vips? vips) {
  Directory? tmp;
  try {
    // Host-visible: under Flatpak the tools run on the host (see
    // [_runToBytes]) and can't see the sandbox's private /tmp.
    tmp = hostVisibleTempDir().createTempSync('cm_thumb');
    final pngOut = '${tmp.path}/poster.png';
    var bytes = _runToBytes('ffmpegthumbnailer', [
      '-i',
      path,
      '-o',
      pngOut,
      '-s',
      '$longEdge',
      '-q',
      '8',
    ], pngOut);

    bytes ??= () {
      final jpgOut = '${tmp!.path}/poster.jpg';
      return _runToBytes('ffmpeg', [
        '-y',
        '-loglevel',
        'error',
        '-i',
        path,
        '-frames:v',
        '1',
        '-vf',
        'scale=$longEdge:$longEdge:force_original_aspect_ratio=decrease',
        '-q:v',
        '4',
        jpgOut,
      ], jpgOut);
    }();

    if (bytes == null) return null;
    return _reencodePoster(bytes, longEdge, vips);
  } on Object {
    return null;
  } finally {
    try {
      tmp?.deleteSync(recursive: true);
    } on Object {
      // best effort
    }
  }
}

/// Runs [executable] (swallowing a missing-binary [ProcessException]) and
/// returns [outputPath]'s bytes if it exited clean and actually wrote
/// something; null otherwise so the caller can fall back.
Uint8List? _runToBytes(
  String executable,
  List<String> args,
  String outputPath,
) {
  try {
    final (exe, hostArgs) = hostCommand(executable, args);
    final result = Process.runSync(exe, hostArgs);
    if (result.exitCode != 0) return null;
  } on Object {
    return null; // binary not installed
  }
  final file = File(outputPath);
  if (!file.existsSync()) return null;
  final bytes = file.readAsBytesSync();
  return bytes.isEmpty ? null : bytes;
}

// Downscales/re-encodes a decoded poster frame to a small JPEG, correctly
// oriented — shared by every platform's poster extractor.
Uint8List _reencodePoster(Uint8List bytes, int longEdge, Vips? vips) =>
    vips?.thumbnail(bytes, longEdge) ??
    downscaleToJpeg(bytes, longEdge) ??
    bytes;
