import 'dart:isolate';
import 'dart:typed_data';

import 'package:cullimingo/features/cull/data/phash_compute.dart';
import 'package:cullimingo/features/cull/domain/perceptual_hash.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _jpeg(img.Image image) => Uint8List.fromList(img.encodeJpg(image));

void main() {
  test('computeDHash decodes a JPEG and returns a hash', () {
    final image = img.Image(width: 64, height: 64);
    // A left→right brightness gradient (clearly directional).
    for (var y = 0; y < 64; y++) {
      for (var x = 0; x < 64; x++) {
        image.setPixelRgb(x, y, x * 4, x * 4, x * 4);
      }
    }
    expect(computeDHash(_jpeg(image)), isNotNull);
  });

  test('similar images hash close; different images hash far', () {
    final gradient = img.Image(width: 64, height: 64);
    final gradientNoisy = img.Image(width: 64, height: 64);
    final inverted = img.Image(width: 64, height: 64);
    for (var y = 0; y < 64; y++) {
      for (var x = 0; x < 64; x++) {
        final v = x * 4;
        gradient.setPixelRgb(x, y, v, v, v);
        gradientNoisy.setPixelRgb(x, y, (v + 6).clamp(0, 255), v, v);
        inverted.setPixelRgb(x, y, 255 - v, 255 - v, 255 - v);
      }
    }
    final h1 = computeDHash(_jpeg(gradient))!;
    final h2 = computeDHash(_jpeg(gradientNoisy))!;
    final h3 = computeDHash(_jpeg(inverted))!;

    expect(hammingDistance(h1, h2), lessThan(10)); // near-duplicate
    expect(hammingDistance(h1, h3), greaterThan(10)); // very different
  });

  test('garbage bytes yield null, never throw', () {
    expect(computeDHash(Uint8List.fromList([1, 2, 3, 4, 5])), isNull);
  });

  test(
    'computeDHash works inside Isolate.run (how the page calls it)',
    () async {
      final image = img.Image(width: 64, height: 64);
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          image.setPixelRgb(x, y, x * 4, x * 4, x * 4);
        }
      }
      final bytes = _jpeg(image);
      final hash = await Isolate.run(() => computeDHash(bytes));
      expect(hash, isNotNull);
      expect(hash, computeDHash(bytes)); // same result on/off the isolate
    },
  );
}
