import 'dart:typed_data';

import 'package:cullimingo/features/cull/domain/loupe_analysis.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Encodes a synthetic [width]x[height] image (PNG — lossless, so pixel
/// values survive the encode/decode round trip exactly) where [paint] fills
/// in each pixel's colour.
Uint8List _pngOf(
  int width,
  int height,
  img.Color Function(int x, int y) paint,
) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixel(x, y, paint(x, y));
    }
  }
  return img.encodePng(image);
}

void main() {
  test('returns null for undecodable bytes', () {
    final result = computeLoupeAnalysis(
      Uint8List.fromList([1, 2, 3]),
      wantHistogram: true,
      wantClipping: false,
      wantPeaking: false,
    );
    expect(result, isNull);
  });

  test('histogram counts each channel value into its bin', () {
    // Four distinct, known colours — one pixel each.
    final colors = [
      img.ColorRgb8(10, 20, 30),
      img.ColorRgb8(200, 100, 50),
      img.ColorRgb8(10, 250, 0),
      img.ColorRgb8(0, 0, 0),
    ];
    final bytes = _pngOf(2, 2, (x, y) => colors[y * 2 + x]);

    final result = computeLoupeAnalysis(
      bytes,
      wantHistogram: true,
      wantClipping: false,
      wantPeaking: false,
    )!;

    expect(result.clippingOverlayRgba, isNull);
    expect(result.peakingOverlayRgba, isNull);
    final h = result.histogram!;
    expect(h.red[10], 2); // two pixels with r=10
    expect(h.red[200], 1);
    expect(h.green[0], 1);
    expect(h.green[250], 1);
    expect(h.blue[30], 1);
    expect(h.maxCount, 2);
  });

  test('clipping overlay tints blown highlights red, crushed shadows blue', () {
    // Row: white (blown), black (crushed), mid-grey (neither).
    final bytes = _pngOf(3, 1, (x, y) {
      return switch (x) {
        0 => img.ColorRgb8(255, 255, 255),
        1 => img.ColorRgb8(0, 0, 0),
        _ => img.ColorRgb8(128, 128, 128),
      };
    });

    final result = computeLoupeAnalysis(
      bytes,
      wantHistogram: false,
      wantClipping: true,
      wantPeaking: false,
    )!;

    expect(result.histogram, isNull);
    final overlay = result.clippingOverlayRgba!;
    // Pixel 0 (white): opaque red.
    expect(overlay.sublist(0, 4), [255, 0, 0, 220]);
    // Pixel 1 (black): opaque blue.
    expect(overlay.sublist(4, 8), [0, 0, 255, 220]);
    // Pixel 2 (mid-grey): left untouched (transparent).
    expect(overlay.sublist(8, 12), [0, 0, 0, 0]);
  });

  test('focus peaking marks a hard edge and leaves flat fields untouched', () {
    // 4x4: left two columns black, right two columns white — a vertical
    // edge at x=1/x=2. Only rows 0..2 have a valid gradient (the last row
    // has no "down" neighbour to compare against).
    final bytes = _pngOf(4, 4, (x, y) {
      final v = x < 2 ? 0 : 255;
      return img.ColorRgb8(v, v, v);
    });

    final result = computeLoupeAnalysis(
      bytes,
      wantHistogram: false,
      wantClipping: false,
      wantPeaking: true,
    )!;

    final overlay = result.peakingOverlayRgba!;
    bool flagged(int x, int y) {
      final i = (y * 4 + x) * 4;
      return overlay[i + 3] > 0;
    }

    // The black pixel right next to the jump to white is flagged...
    expect(flagged(1, 0), isTrue);
    // ...but a pixel deep inside either flat field is not.
    expect(flagged(0, 0), isFalse);
    expect(flagged(3, 0), isFalse);
  });
}
