import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Per-channel pixel-value counts (256 bins) for the loupe's RGB histogram.
class RgbHistogram {
  /// Creates a histogram from its three channel bin arrays (256 entries each).
  const RgbHistogram({
    required this.red,
    required this.green,
    required this.blue,
  });

  /// Red channel bin counts, index 0 (black) to 255 (full).
  final List<int> red;

  /// Green channel bin counts.
  final List<int> green;

  /// Blue channel bin counts.
  final List<int> blue;

  /// The tallest bin across all three channels — normalises the chart height.
  int get maxCount {
    var max = 0;
    for (final bins in [red, green, blue]) {
      for (final c in bins) {
        if (c > max) max = c;
      }
    }
    return max;
  }
}

/// Result of [computeLoupeAnalysis]: whichever of the histogram / clipping /
/// peaking products were requested (the rest are null, so a caller that only
/// wants one doesn't pay for the others).
class LoupeAnalysis {
  /// Creates an analysis result. [width]/[height] describe the overlay images.
  const LoupeAnalysis({
    required this.width,
    required this.height,
    this.histogram,
    this.clippingOverlayRgba,
    this.peakingOverlayRgba,
  });

  /// Pixel width of the analysed image (and of the overlay buffers).
  final int width;

  /// Pixel height of the analysed image (and of the overlay buffers).
  final int height;

  /// The RGB histogram, when requested.
  final RgbHistogram? histogram;

  /// RGBA overlay (straight, non-premultiplied) tinting blown highlights red
  /// and crushed shadows blue; transparent everywhere else. `width * height *
  /// 4` bytes, when requested.
  final Uint8List? clippingOverlayRgba;

  /// RGBA overlay tinting high-contrast edges (in-focus detail) a bright
  /// accent colour; transparent everywhere else. `width * height * 4` bytes,
  /// when requested.
  final Uint8List? peakingOverlayRgba;
}

/// A channel value at or above this counts as "blown" (clipped highlight).
const int _highlightThreshold = 250;

/// A channel value at or below this counts as "crushed" (clipped shadow).
const int _shadowThreshold = 5;

/// Minimum luminance gradient (against the right/below neighbour) to count as
/// an in-focus edge. Tuned empirically against real photos — high enough that
/// smooth skies/skin don't peak, low enough that real detail does.
const double _edgeThreshold = 40;

/// Runs [computeLoupeAnalysis] on a background isolate (`BUILD_PLAN.md` §0.6 —
/// a multi-megapixel convolution has no business on the UI isolate). A
/// top-level wrapper, not a method: `Isolate.run` sends the closure it's
/// given, and a closure created inside a `State` method can drag the whole
/// widget tree along for the ride (Dart shares one context across a method's
/// closures, so if any statement in the same method touches `this` — even
/// `mounted` — the isolate call's closure captures it too, and a `_Timer`
/// living somewhere in that tree fails to serialize). Calling from a
/// top-level function sidesteps that: there's no `this` to capture.
Future<LoupeAnalysis?> computeLoupeAnalysisOffThread(
  Uint8List sourceBytes, {
  required bool wantHistogram,
  required bool wantClipping,
  required bool wantPeaking,
}) {
  return Isolate.run(
    () => computeLoupeAnalysis(
      sourceBytes,
      wantHistogram: wantHistogram,
      wantClipping: wantClipping,
      wantPeaking: wantPeaking,
    ),
  );
}

/// Decodes [sourceBytes] (the loupe preview JPEG/WebP) and computes whichever
/// of the histogram / clipping-warning / focus-peaking products are asked
/// for, in a single pass over the pixels. Pure — call via
/// [computeLoupeAnalysisOffThread] rather than directly from UI code. Returns
/// null when the bytes don't decode.
LoupeAnalysis? computeLoupeAnalysis(
  Uint8List sourceBytes, {
  required bool wantHistogram,
  required bool wantClipping,
  required bool wantPeaking,
}) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(sourceBytes);
  } on Object {
    decoded = null;
  }
  if (decoded == null) return null;
  final width = decoded.width;
  final height = decoded.height;
  final rgba = decoded.getBytes(order: img.ChannelOrder.rgba);

  List<int>? red;
  List<int>? green;
  List<int>? blue;
  if (wantHistogram) {
    red = List.filled(256, 0);
    green = List.filled(256, 0);
    blue = List.filled(256, 0);
  }
  final clip = wantClipping ? Uint8List(width * height * 4) : null;
  final peak = wantPeaking ? Uint8List(width * height * 4) : null;

  for (var y = 0; y < height; y++) {
    final rowStart = y * width * 4;
    for (var x = 0; x < width; x++) {
      final i = rowStart + x * 4;
      final r = rgba[i];
      final g = rgba[i + 1];
      final b = rgba[i + 2];

      if (red != null) {
        red[r]++;
        green![g]++;
        blue![b]++;
      }

      if (clip != null) {
        if (r >= _highlightThreshold &&
            g >= _highlightThreshold &&
            b >= _highlightThreshold) {
          clip[i] = 255; // opaque red: blown highlight
          clip[i + 3] = 220;
        } else if (r <= _shadowThreshold &&
            g <= _shadowThreshold &&
            b <= _shadowThreshold) {
          clip[i + 2] = 255; // opaque blue: crushed shadow
          clip[i + 3] = 220;
        }
      }

      if (peak != null && x + 1 < width && y + 1 < height) {
        final lum = 0.299 * r + 0.587 * g + 0.114 * b;
        final right = i + 4;
        final down = i + width * 4;
        final lumRight =
            0.299 * rgba[right] +
            0.587 * rgba[right + 1] +
            0.114 * rgba[right + 2];
        final lumDown =
            0.299 * rgba[down] +
            0.587 * rgba[down + 1] +
            0.114 * rgba[down + 2];
        final gradient = (lum - lumRight).abs() + (lum - lumDown).abs();
        if (gradient >= _edgeThreshold) {
          // Bright accent (magenta), reads clearly over any photo content.
          peak[i] = 255;
          peak[i + 1] = 32;
          peak[i + 2] = 220;
          peak[i + 3] = 235;
        }
      }
    }
  }

  return LoupeAnalysis(
    width: width,
    height: height,
    histogram: red == null
        ? null
        : RgbHistogram(red: red, green: green!, blue: blue!),
    clippingOverlayRgba: clip,
    peakingOverlayRgba: peak,
  );
}
