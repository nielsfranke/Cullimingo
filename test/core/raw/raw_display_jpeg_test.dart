import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:cullimingo/core/cache/vips.dart';
import 'package:cullimingo/core/raw/libraw_preview_extractor.dart';
import 'package:cullimingo/core/raw/raw_display_jpeg.dart';
import 'package:flutter_libraw/flutter_libraw.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'synthetic_dng.dart';

void main() {
  // CULLIMINGO_LIBRAW points the tests at another build (e.g. LibRaw 0.22).
  final libPath =
      Platform.environment['CULLIMINGO_LIBRAW'] ??
      LibRawPreviewExtractor.resolveLibraryPath();
  final lr = libPath == null
      ? null
      : FlutterLibRawBindings(DynamicLibrary.open(libPath));
  final vips = Vips.tryLoad();

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('cm_rawjpeg_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String writeDng({int truncate = 0}) {
    final path = p.join(tmp.path, 'synthetic.dng');
    File(path).writeAsBytesSync(syntheticDng(truncate: truncate));
    return path;
  }

  bool skipWithout({bool needVips = true}) {
    if (lr == null) {
      markTestSkipped('libraw not installed on this machine');
      return true;
    }
    if (needVips && vips == null) {
      markTestSkipped('libvips not installed on this machine');
      return true;
    }
    return false;
  }

  test('setLibRawHalfSize finds params.half_size on the loaded runtime', () {
    if (skipWithout(needVips: false)) return;
    final handle = lr!.libraw_init(0);
    addTearDown(() => lr.libraw_close(handle));

    expect(setLibRawHalfSize(lr, handle, enabled: true), isTrue);
    // The generated struct matches the 0.21 ABI, so there the probed offset
    // must land exactly on the real field.
    final version = lr.libraw_versionNumber();
    if ((version >> 8) & 0xffff == 21) {
      expect(handle.ref.params.half_size, 1);
      expect(setLibRawHalfSize(lr, handle, enabled: false), isTrue);
      expect(handle.ref.params.half_size, 0);
      // The probe restores the defaults it disturbed.
      expect(handle.ref.params.bright, 1);
      expect(handle.ref.params.output_color, 1);
    }
  });

  test('half-size demosaic is used when it still covers the request', () {
    if (skipWithout(needVips: false)) return;
    final path = writeDng();
    int? decodedWidth(int minLongEdge) => processRawBitmap<int>(
      lr!,
      path,
      minLongEdge: minLongEdge,
      consume: (_, _, width, _, _) => width,
    );

    expect(decodedWidth(16), 32); // 64 px wide, half = 32 ≥ 16
    expect(decodedWidth(40), 64); // half would be too small → full size
    expect(decodedWidth(0), 64); // full tier
  });

  test('a RAW without an embedded preview is demosaiced to the tier', () async {
    if (skipWithout()) return;
    final path = writeDng();

    final thumb = await rawDisplayJpeg(
      lr!,
      path,
      longEdge: 20,
      vips: () => vips,
    );
    expect(thumb, isNotNull);
    expect(thumb!.demosaiced, isTrue);
    final small = img.decodeJpg(thumb.bytes)!;
    expect(small.width, 20);
    expect(small.height, 15);

    // Never upscaled past the decode, and the full tier is native size.
    final big = await rawDisplayJpeg(
      lr,
      path,
      longEdge: 4000,
      vips: () => vips,
    );
    expect(img.decodeJpg(big!.bytes)!.width, 64);
    final full = await rawDisplayJpeg(lr, path, longEdge: 0, vips: () => vips);
    expect(img.decodeJpg(full!.bytes)!.width, 64);
  });

  test('without libvips there is nothing to show for a preview-less RAW', () {
    if (skipWithout(needVips: false)) return;
    expect(
      rawDisplayJpeg(lr!, writeDng(), longEdge: 20, vips: () => null),
      completion(isNull),
    );
  });

  group('demosaic cache (GitHub #7)', () {
    test('another tier of the same RAW reuses the decode', () async {
      if (skipWithout()) return;
      final path = writeDng();
      final cache = DemosaicCache();
      var demosaics = 0;
      Future<RawDisplayJpeg?> ask(int longEdge) => rawDisplayJpeg(
        lr!,
        path,
        longEdge: longEdge,
        vips: () => vips,
        cache: cache,
        onDemosaic: () => demosaics++,
      );

      final thumb = await ask(10);
      expect(demosaics, 1);
      expect(cache.path, path);
      // Half-size decode (32 px) covers a 20 px tier: no second demosaic, and
      // the output matches what a fresh decode renders.
      final loupe = await ask(20);
      expect(demosaics, 1);
      expect(img.decodeJpg(thumb!.bytes)!.width, 10);
      expect(img.decodeJpg(loupe!.bytes)!.width, 20);

      // The half-size bitmap can't serve the full tier → decode again.
      final full = await ask(0);
      expect(demosaics, 2);
      expect(img.decodeJpg(full!.bytes)!.width, 64);
    });

    test('a changed file is decoded again', () async {
      if (skipWithout()) return;
      final path = writeDng();
      final cache = DemosaicCache();
      var demosaics = 0;
      Future<void> ask() => rawDisplayJpeg(
        lr!,
        path,
        longEdge: 20,
        vips: () => vips,
        cache: cache,
        onDemosaic: () => demosaics++,
      );

      await ask();
      File(path).setLastModifiedSync(DateTime(2020));
      await ask();
      expect(demosaics, 2);
    });

    test('a corrupt decode is never cached', () async {
      if (skipWithout()) return;
      final cache = DemosaicCache();
      await rawDisplayJpeg(
        lr!,
        writeDng(truncate: 1000),
        longEdge: 20,
        vips: () => vips,
        cache: cache,
      );
      expect(cache.path, isNull);
    });
  });

  group('DemosaicCache', () {
    const key = DemosaicKey('/a.nef', 10, 1000);
    CachedDemosaic bitmap({
      DemosaicKey k = key,
      int w = 40,
      int h = 30,
      bool full = false,
    }) => CachedDemosaic(
      k,
      Uint8List(w * h * 3),
      width: w,
      height: h,
      fullResolution: full,
    );

    test('serves only the same file version, and only tiers it covers', () {
      final cache = DemosaicCache()..store(bitmap());
      expect(cache.lookup(key, longEdge: 40), isNotNull);
      expect(cache.lookup(key, longEdge: 41), isNull, reason: 'no upscale');
      expect(cache.lookup(key, longEdge: 0), isNull, reason: 'half-size');
      expect(
        cache.lookup(const DemosaicKey('/a.nef', 10, 2000), longEdge: 20),
        isNull,
        reason: 'mtime changed',
      );
      expect(
        cache.lookup(const DemosaicKey('/a.nef', 11, 1000), longEdge: 20),
        isNull,
        reason: 'size changed',
      );
      cache.store(bitmap(full: true));
      expect(cache.lookup(key, longEdge: 0), isNotNull);
    });

    test('keeps one entry and never one over the size cap', () {
      final cache = DemosaicCache(maxBytes: 40 * 30 * 3)..store(bitmap());
      const other = DemosaicKey('/b.nef', 10, 1000);
      cache.store(bitmap(k: other));
      expect(cache.lookup(key, longEdge: 10), isNull);
      expect(cache.path, '/b.nef');
      cache.store(bitmap(w: 41));
      expect(cache.path, '/b.nef', reason: 'over the cap: not stored');
    });

    test('drops its entry after the TTL', () async {
      final cache = DemosaicCache(ttl: const Duration(milliseconds: 50))
        ..store(bitmap());
      expect(cache.path, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(cache.path, isNull);
    });
  });

  test('a corrupt RAW is reported as a failed decode, not noise', () async {
    if (skipWithout()) return;
    // LibRaw raises its data-error callback while unpacking the short strip.
    final path = writeDng(truncate: 1000);
    final out = await rawDisplayJpeg(
      lr!,
      path,
      longEdge: 20,
      vips: () => vips,
    );
    expect(out, isNull);
  });
}
