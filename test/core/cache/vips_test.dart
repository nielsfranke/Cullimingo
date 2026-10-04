import 'dart:convert';
import 'dart:typed_data';

import 'package:cullimingo/core/cache/vips.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  final vips = Vips.tryLoad();
  final hasVips = vips != null;

  Uint8List jpeg(img.Image image) => Uint8List.fromList(img.encodeJpg(image));

  // Same 2×2 AVIF embedded in vips.dart for HEIF loader warm-up; decoding it
  // here guards both the sample's validity and the HEIF-decode capability.
  final warmupAvif = base64Decode(
    'AAAAHGZ0eXBhdmlmAAAAAG1pZjFhdmlmbWlhZgAAANRtZXRhAAAAAAAAACFoZGxyAAAAAAAA'
    'AABwaWN0AAAAAAAAAAAAAAAAAAAAACJpbG9jAAAAAERAAAEAAQAAAAAA+AABAAAAAAAAABYA'
    'AAAjaWluZgAAAAAAAQAAABVpbmZlAgAAAAABAABhdjAxAAAAAA5waXRtAAAAAAABAAAAVGlw'
    'cnAAAAA2aXBjbwAAAAxhdjFDgUB8AAAAABRpc3BlAAAAAAAAAAIAAAACAAAADnBpeGkAAAAA'
    'AQwAAAAWaXBtYQAAAAAAAAABAAEDgQIDAAAAHm1kYXQSAAoFWAA2uoAyCxlGIYmmaACQP5vg',
  );

  test('downscales a large landscape JPEG within the long edge', () {
    if (!hasVips) {
      markTestSkipped('libvips not installed');
      return;
    }
    final src = jpeg(img.Image(width: 4000, height: 2000));
    final out = vips.thumbnail(src, 800);

    expect(out, isNotNull);
    final decoded = img.decodeJpg(out!)!;
    expect(decoded.width, lessThanOrEqualTo(800));
    expect(decoded.height, lessThanOrEqualTo(800));
    expect(out.length, lessThan(src.length));
  });

  test('a portrait source also fits within the box', () {
    if (!hasVips) {
      markTestSkipped('libvips not installed');
      return;
    }
    final decoded = img.decodeJpg(
      vips.thumbnail(jpeg(img.Image(width: 2000, height: 4000)), 800)!,
    )!;
    expect(decoded.width, lessThanOrEqualTo(800));
    expect(decoded.height, lessThanOrEqualTo(800));
  });

  test('auto-rotates from EXIF orientation', () {
    if (!hasVips) {
      markTestSkipped('libvips not installed');
      return;
    }
    // Landscape pixels tagged "rotate 90 CW" — vips should output portrait.
    final image = img.Image(width: 4000, height: 2000);
    image.exif.imageIfd['Orientation'] = 6;
    final decoded = img.decodeJpg(vips.thumbnail(jpeg(image), 800)!)!;

    expect(decoded.height, greaterThan(decoded.width));
  });

  test('decodes an AVIF/HEIF buffer to a JPEG thumbnail', () {
    if (!hasVips) {
      markTestSkipped('libvips not installed');
      return;
    }
    final out = vips.thumbnail(warmupAvif, 64);
    expect(out, isNotNull, reason: 'HEIF/AVIF should decode via vips-heif');
    expect(out!.sublist(0, 2), [0xFF, 0xD8]); // JPEG magic
  });

  test('recognises ISO base-media (HEIF/AVIF) buffers only', () {
    expect(Vips.isIsoBmff(warmupAvif), isTrue);
    expect(Vips.isIsoBmff(jpeg(img.Image(width: 2, height: 2))), isFalse);
    expect(
      Vips.isIsoBmff(Uint8List.fromList(utf8.encode('xxxxftyp'))),
      isFalse,
    );
  });

  test('encodes and downsizes interleaved RGB pixels', () {
    if (!hasVips) {
      markTestSkipped('libvips not installed');
      return;
    }
    final rgb = Uint8List(400 * 200 * 3);
    for (var i = 0; i < rgb.length; i += 3) {
      rgb[i] = 230;
      rgb[i + 1] = 80;
      rgb[i + 2] = 30;
    }

    final out = vips.thumbnailRgb(
      rgb,
      width: 400,
      height: 200,
      channels: 3,
      longEdge: 100,
    );

    expect(out, isNotNull);
    final decoded = img.decodeJpg(out!)!;
    expect(decoded.width, 100);
    expect(decoded.height, 50);
  });

  test('encodes RGB pixels at the requested JPEG quality', () {
    if (!hasVips) {
      markTestSkipped('libvips not installed');
      return;
    }
    // Noise-like content, so quality visibly changes the size.
    final rgb = Uint8List.fromList(
      List<int>.generate(256 * 256 * 3, (i) => (i * 7919) % 251),
    );
    Uint8List encode(int q) => vips.thumbnailRgb(
      rgb,
      width: 256,
      height: 256,
      channels: 3,
      longEdge: 256,
      quality: q,
    )!;

    expect(encode(95).length, greaterThan(encode(30).length));
  });

  test('warmUpProcess completes without throwing', () {
    // Registers the JPEG + HEIF loader types on the main isolate; must be a
    // no-throw best effort whether or not libvips/libheif are present.
    expect(Vips.warmUpProcess, returnsNormally);
  });
}
