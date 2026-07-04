import 'dart:typed_data';

import 'package:cullimingo/core/vips/vips_encoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  final vips = VipsEncoder.instance();

  /// A 32×24 red/blue gradient as interleaved RGB bytes.
  Uint8List rgb(int w, int h) {
    final bytes = Uint8List(w * h * 3);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 3;
        bytes[i] = (255 * x / w).round();
        bytes[i + 2] = (255 * y / h).round();
      }
    }
    return bytes;
  }

  test('encodes WebP that the image package decodes back', () {
    if (vips == null) {
      markTestSkipped('libvips not installed on this machine');
      return;
    }
    final out = vips.encodeRgb(
      rgb: rgb(32, 24),
      width: 32,
      height: 24,
      quality: 80,
    );
    expect(out, isNotNull);
    final decoded = img.decodeWebP(out!);
    expect(decoded, isNotNull);
    expect(decoded!.width, 32);
    expect(decoded.height, 24);
  });

  test('encodes AVIF (ftyp brand avif)', () {
    if (vips == null) {
      markTestSkipped('libvips not installed on this machine');
      return;
    }
    final out = vips.encodeRgb(
      rgb: rgb(32, 24),
      width: 32,
      height: 24,
      quality: 60,
      avif: true,
    );
    expect(out, isNotNull);
    // ISO-BMFF: [size]['ftyp']['avif' major brand].
    expect(String.fromCharCodes(out!.sublist(4, 12)), 'ftypavif');
  });

  test('embeds the XMP packet into the WebP', () {
    if (vips == null) {
      markTestSkipped('libvips not installed on this machine');
      return;
    }
    const xmp =
        '<x:xmpmeta xmlns:x="adobe:ns:meta/">cullimingo-marker </x:xmpmeta>';
    final out = vips.encodeRgb(
      rgb: rgb(32, 24),
      width: 32,
      height: 24,
      quality: 80,
      xmp: xmp,
    );
    expect(out, isNotNull);
    expect(String.fromCharCodes(out!), contains('cullimingo-marker'));
  });

  test('mismatched buffer size returns null instead of crashing', () {
    if (vips == null) {
      markTestSkipped('libvips not installed on this machine');
      return;
    }
    expect(
      vips.encodeRgb(rgb: Uint8List(10), width: 32, height: 24, quality: 80),
      isNull,
    );
  });
}
