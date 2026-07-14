import 'dart:typed_data';

import 'package:cullimingo/features/cull/domain/loupe_analysis.dart';
import 'package:cullimingo/features/cull/presentation/loupe_analysis_decode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Covers the production analysis pipeline end-to-end (native engine decode →
/// RGBA readback → pixel loop) — the loupe widget tests run without real
/// bytes, so a decode/readback regression would otherwise only surface in the
/// running app (as it did when the readback format broke on Impeller).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A JPEG with a blown white left half and a crushed black right half.
  Uint8List clippedJpeg({int width = 64, int height = 32}) {
    final canvas = img.Image(width: width, height: height);
    img.fillRect(
      canvas,
      x1: 0,
      y1: 0,
      x2: width ~/ 2 - 1,
      y2: height - 1,
      color: img.ColorRgb8(255, 255, 255),
    );
    return Uint8List.fromList(img.encodeJpg(canvas, quality: 95));
  }

  test('decodeRgbaForAnalysis decodes a JPEG to full-size RGBA', () async {
    final decoded = await decodeRgbaForAnalysis(
      clippedJpeg(),
      maxLongEdge: 2048,
    );

    expect(decoded, isNotNull);
    expect(decoded!.width, 64);
    expect(decoded.height, 32);
    expect(decoded.rgba.length, 64 * 32 * 4);
  });

  test('decodeRgbaForAnalysis caps the long edge, keeping aspect', () async {
    final decoded = await decodeRgbaForAnalysis(
      clippedJpeg(width: 400, height: 200),
      maxLongEdge: 100,
    );

    expect(decoded, isNotNull);
    expect(decoded!.width, 100);
    expect(decoded.height, 50);
    expect(decoded.rgba.length, 100 * 50 * 4);
  });

  test('decoded pixels feed the analysis: histogram + clipping map', () async {
    final decoded = await decodeRgbaForAnalysis(
      clippedJpeg(),
      maxLongEdge: 2048,
    );

    final analysis = computeLoupeAnalysisFromRgba(
      decoded!.rgba,
      width: decoded.width,
      height: decoded.height,
      wantHistogram: true,
      wantClipping: true,
      wantPeaking: false,
    );

    // Every pixel lands in exactly one histogram bin per channel.
    final histogram = analysis.histogram!;
    expect(histogram.red.reduce((a, b) => a + b), 64 * 32);

    // The white half tints red (blown), the black half blue (crushed).
    final clip = analysis.clippingOverlayRgba!;
    int at(int x, int y, int c) => clip[(y * decoded.width + x) * 4 + c];
    expect(at(4, 16, 0), 255, reason: 'white half flagged as blown (red)');
    expect(at(60, 16, 2), 255, reason: 'black half flagged as crushed (blue)');
  });

  test('undecodable bytes return null instead of throwing', () async {
    final decoded = await decodeRgbaForAnalysis(
      Uint8List.fromList([1, 2, 3, 4]),
      maxLongEdge: 2048,
    );
    expect(decoded, isNull);
  });
}
