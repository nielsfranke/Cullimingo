import 'dart:ffi';
import 'dart:io';

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
