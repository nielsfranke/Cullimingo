import 'dart:typed_data';

import 'package:cullimingo/core/raw/jpeg_resize.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _jpeg(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(90, 140, 200));
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  test('downscales a landscape source so the long edge matches', () {
    final out = downscaleToJpeg(_jpeg(800, 400), 200);
    final decoded = img.decodeJpg(out!)!;
    expect(decoded.width, 200);
    expect(decoded.height, 100);
  });

  test('downscales a portrait source by its (taller) long edge', () {
    final out = downscaleToJpeg(_jpeg(400, 800), 200);
    final decoded = img.decodeJpg(out!)!;
    expect(decoded.height, 200);
    expect(decoded.width, 100);
  });

  test('never upscales a source already below the long edge', () {
    final out = downscaleToJpeg(_jpeg(300, 200), 4096);
    final decoded = img.decodeJpg(out!)!;
    expect(decoded.width, 300);
    expect(decoded.height, 200);
  });

  test('bakes EXIF orientation into the pixels', () {
    final src = img.Image(width: 400, height: 200);
    img.fill(src, color: img.ColorRgb8(10, 20, 30));
    src.exif.imageIfd.orientation = 6; // display-rotate 90° CW
    final bytes = Uint8List.fromList(img.encodeJpg(src));

    // Long edge stays 400, so no downscale — only the orientation bake applies.
    final decoded = img.decodeJpg(downscaleToJpeg(bytes, 4096)!)!;
    expect(decoded.width, 200);
    expect(decoded.height, 400);
  });

  test('returns null for undecodable bytes', () {
    expect(downscaleToJpeg(Uint8List.fromList([1, 2, 3, 4]), 200), isNull);
  });
}
