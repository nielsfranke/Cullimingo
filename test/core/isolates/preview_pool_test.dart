import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cullimingo/core/isolates/preview_pool.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// A scripted stand-in for the real worker, speaking the pool's protocol. The
/// path decides what it does:
/// - `hang`: never answers (a native decode that hung on the fast path);
/// - `slow-hang`: announces a demosaic, then never answers;
/// - `slow:<ms>`: like a RAW without an embedded JPEG — if this worker still
///   holds that file's decode it answers at once, else it announces a
///   demosaic, works for `<ms>` and keeps the decode;
/// - anything else: answers at once.
/// Answers carry `[workerId, hit ? 1 : 0]` so tests can see who served a job
/// and whether it reused a decode.
void _fakeWorker(List<Object?> init) {
  final toMain = init[0]! as SendPort;
  final workerId = init[3]! as int;
  final inbox = ReceivePort();
  String? cached;
  inbox.listen((message) async {
    final job = message! as List<Object?>;
    final id = job[0]! as int;
    final path = job[1]! as String;
    var hit = false;
    if (path == 'hang') return;
    if (path == 'slow-hang') {
      toMain.send([previewPoolDemosaicTag, id]);
      return;
    }
    if (path.startsWith('slow:')) {
      if (cached == path) {
        hit = true;
      } else {
        toMain.send([previewPoolDemosaicTag, id]);
        final ms = int.parse(path.substring(5).split('#').first);
        await Future<void>.delayed(Duration(milliseconds: ms));
        cached = path;
      }
    }
    toMain.send([
      id,
      TransferableTypedData.fromList([
        Uint8List.fromList([workerId, if (hit) 1 else 0]),
      ]),
      inbox.sendPort,
      cached,
    ]);
  });
  toMain.send([workerId, inbox.sendPort]);
}

bool _isInstalled(String executable) {
  try {
    return Process.runSync(executable, ['-version']).exitCode == 0;
  } on Object {
    return false;
  }
}

void main() {
  late Directory tmp;
  late PreviewPool pool;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('preview_pool');
    // libvips off: it spawns threads that keep the test process from exiting.
    // vips is covered by vips_test; here we test the pool's queue/dispatch.
    pool = PreviewPool(workers: 2, enableVips: false);
  });

  tearDown(() async {
    await pool.dispose();
    await tmp.delete(recursive: true);
  });

  File writeJpeg(String name, int w, int h) {
    final image = img.Image(width: w, height: h);
    img.fill(image, color: img.ColorRgb8(10, 120, 200));
    return File(p.join(tmp.path, name))..writeAsBytesSync(img.encodeJpg(image));
  }

  test('extracts and downscales a JPEG via a worker', () async {
    final file = writeJpeg('a.jpg', 1600, 900);
    final bytes = await pool.thumbnail(file.path, longEdge: 200);

    expect(bytes, isNotNull);
    final out = img.decodeJpg(bytes!)!;
    expect(out.width, 200);
  });

  test('handles many concurrent requests across workers', () async {
    final files = [for (var i = 0; i < 20; i++) writeJpeg('p$i.jpg', 400, 300)];
    final results = await Future.wait(
      files.map((f) => pool.thumbnail(f.path, longEdge: 128)),
    );

    expect(results.where((b) => b != null), hasLength(20));
  });

  test('returns null for a missing file', () async {
    expect(await pool.thumbnail('/no/such.jpg'), isNull);
  });

  test('a full-resolution request (longEdge 0) returns the source '
      'undownscaled', () async {
    final file = writeJpeg('full.jpg', 1600, 900);
    // longEdge 0 = the full tier: hand back the original bitmap, no resize.
    final bytes = await pool.thumbnail(file.path, longEdge: 0);

    expect(bytes, isNotNull);
    final out = img.decodeJpg(bytes!)!;
    expect(out.width, 1600, reason: 'full-res source must not be downscaled');
    expect(out.height, 900);
  });

  test('skips an already-cancelled request', () async {
    final file = writeJpeg('c.jpg', 800, 600);
    final cancel = CancelToken()..cancel();
    expect(await pool.thumbnail(file.path, cancel: cancel), isNull);
  });

  test(
    'extracts a video poster frame via ffmpegthumbnailer/ffmpeg on Linux',
    () async {
      if (!Platform.isLinux) {
        markTestSkipped('poster extraction only runs this path on Linux');
        return;
      }
      final hasThumbnailer = _isInstalled('ffmpegthumbnailer');
      final hasFfmpeg = _isInstalled('ffmpeg');
      if (!hasThumbnailer && !hasFfmpeg) {
        markTestSkipped('neither ffmpegthumbnailer nor ffmpeg is installed');
        return;
      }

      // A tiny synthetic clip generated on the fly — no binary asset to keep
      // in the repo, and it exercises the exact tool(s) present on this box.
      final video = p.join(tmp.path, 'clip.mp4');
      final generated = Process.runSync('ffmpeg', [
        '-y',
        '-loglevel',
        'error',
        '-f',
        'lavfi',
        '-i',
        'testsrc=duration=1:size=320x240:rate=5',
        '-pix_fmt',
        'yuv420p',
        video,
      ]);
      expect(
        generated.exitCode,
        0,
        reason: 'test setup: ffmpeg must generate the sample clip',
      );

      final bytes = await pool.thumbnail(video, longEdge: 160);

      expect(bytes, isNotNull);
      final out = img.decodeImage(bytes!);
      expect(out, isNotNull, reason: 'poster bytes must decode as an image');
      expect(out!.width <= 160 && out.height <= 160, isTrue);
    },
  );

  test('visible jobs jump ahead of already-queued prefetch jobs', () async {
    // One worker → strictly sequential, so completion order reflects dispatch
    // order. Pre-warm so worker-spawn latency isn't part of the timing.
    final single = PreviewPool(workers: 1, enableVips: false);
    addTearDown(single.dispose);
    await single.thumbnail(writeJpeg('warm.jpg', 64, 64).path, longEdge: 32);

    final order = <String>[];
    void record(String tag) => order.add(tag);

    // Submitted in one synchronous burst: p0 dispatches immediately (worker
    // idle); p1, p2 and the later visible job all queue behind it. When p0
    // finishes, the visible job must be served before the queued prefetch jobs.
    final futures = <Future<void>>[
      for (final tag in ['p0', 'p1', 'p2'])
        single
            .thumbnail(
              writeJpeg('$tag.jpg', 200, 150).path,
              priority: JobPriority.prefetch,
            )
            .then((_) => record(tag)),
      single
          .thumbnail(writeJpeg('v.jpg', 200, 150).path)
          .then((_) => record('v')),
    ];
    await Future.wait(futures);

    // p0 was in flight before v was queued, so it stays first; v then jumps the
    // two remaining prefetch jobs.
    expect(order, ['p0', 'v', 'p1', 'p2']);
  });

  group('watchdog budgets (GitHub #5)', () {
    PreviewPool fakePool({
      int workers = 1,
      Duration fast = const Duration(milliseconds: 200),
      Duration slow = const Duration(seconds: 5),
    }) {
      final pool = PreviewPool(
        workers: workers,
        enableVips: false,
        fastJobTimeout: fast,
        slowJobTimeout: slow,
        workerEntry: _fakeWorker,
      );
      addTearDown(pool.dispose);
      return pool;
    }

    test('a hung fast-path job is reclaimed after the short budget', () async {
      final pool = fakePool();
      final watch = Stopwatch()..start();
      expect(await pool.thumbnail('hang'), isNull);
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
      // The hung worker was replaced, so the pool still serves jobs.
      expect(await pool.thumbnail('ok'), isNotNull);
    });

    test('a job that announces a demosaic gets the long budget', () async {
      final pool = fakePool();
      // Takes four times the short budget, well inside the long one.
      expect(await pool.thumbnail('slow:800'), isNotNull);
    });

    test('a hung demosaic is still reclaimed after the long budget', () async {
      final pool = fakePool(
        fast: const Duration(milliseconds: 100),
        slow: const Duration(milliseconds: 600),
      );
      final watch = Stopwatch()..start();
      expect(await pool.thumbnail('slow-hang'), isNull);
      expect(
        watch.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 600)),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 4)));
      expect(await pool.thumbnail('ok'), isNotNull);
    });
  });

  group('demosaic reuse across tiers (GitHub #7)', () {
    PreviewPool fakePool() {
      final pool = PreviewPool(
        workers: 2,
        enableVips: false,
        fastJobTimeout: const Duration(seconds: 5),
        workerEntry: _fakeWorker,
      );
      addTearDown(pool.dispose);
      return pool;
    }

    test(
      'another tier of a file being demosaiced waits for that decode',
      () async {
        final pool = fakePool();
        final first = pool.thumbnail('slow:500');
        // Let the worker's demosaic announcement arrive, then ask again —
        // with a second worker idle, which must not start a parallel decode.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final second = pool.thumbnail('slow:500', longEdge: 2048);

        final a = (await first)!;
        final b = (await second)!;
        expect(a[1], 0, reason: 'the first ask decodes');
        expect(b[0], a[0], reason: 'the second ask waits for the same worker');
        expect(b[1], 1, reason: 'and reuses its decode');
      },
    );

    test('a later tier goes to the worker holding the decode', () async {
      final pool = fakePool();
      // Two files at once land on the two workers; each keeps its decode.
      final results = await Future.wait([
        pool.thumbnail('slow:100#a'),
        pool.thumbnail('slow:100#b'),
      ]);
      final a = results[0]!;
      expect(results[1]![0], isNot(a[0]));
      await pool.thumbnail('quick');
      for (final file in ['slow:100#a', 'slow:100#b']) {
        final again = (await pool.thumbnail(file, longEdge: 2048))!;
        final first = file.endsWith('a') ? a : results[1]!;
        expect(again[0], first[0], reason: '$file goes back to its worker');
        expect(again[1], 1);
      }
    });
  });
}
