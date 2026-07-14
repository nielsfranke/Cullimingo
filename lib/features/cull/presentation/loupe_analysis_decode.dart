import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cullimingo/core/logging/app_logger.dart';

/// Decodes [bytes] with the engine codec — on Flutter's IO thread, not the UI
/// isolate — capped to [maxLongEdge] on the long edge (JPEG shrink-on-decode,
/// so a big source never gets fully decoded), and reads the pixels back as
/// RGBA (premultiplied; identical to straight for fully opaque photos). Null
/// when the bytes don't decode or the readback fails (logged; the caller
/// falls back to the pure-Dart decode so the overlays still work).
Future<({Uint8List rgba, int width, int height})?> decodeRgbaForAnalysis(
  Uint8List bytes, {
  required int maxLongEdge,
}) async {
  ui.Codec? codec;
  ui.Image? image;
  try {
    // instantiateImageCodecWithSize takes ownership of the buffer and
    // disposes it itself (success or failure) — disposing it here again
    // throws from the finally, which replaces the successful return and
    // silently killed every overlay. Do NOT touch the buffer after this.
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (w, h) {
        final long = math.max(w, h);
        if (long <= maxLongEdge) {
          return ui.TargetImageSize(width: w, height: h);
        }
        final scale = maxLongEdge / long;
        return ui.TargetImageSize(
          width: math.max(1, (w * scale).round()),
          height: math.max(1, (h * scale).round()),
        );
      },
    );
    final frame = await codec.getNextFrame();
    image = frame.image;
    // Default format (rawRgba, premultiplied) rather than rawStraightRgba:
    // photos are fully opaque, so the two are byte-identical, and the
    // straight-alpha readback is the less-travelled path across backends.
    final data = await image.toByteData();
    if (data == null) {
      appTalker.warning(
        'loupe analysis: toByteData returned null — falling back to the '
        'Dart decoder',
      );
      return null;
    }
    return (
      rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      width: image.width,
      height: image.height,
    );
  } on Object catch (e) {
    appTalker.warning(
      'loupe analysis: native decode/readback failed ($e) — falling back '
      'to the Dart decoder',
    );
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}
