import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Decodes [bytes], bakes EXIF orientation, downscales so the long edge is
/// about [longEdge] px (never upscaling), and re-encodes as JPEG. Returns
/// `null` if undecodable. Shared by the bitmap and LibRaw preview paths.
Uint8List? downscaleToJpeg(Uint8List bytes, int longEdge) {
  // `decodeImage` can throw (not just return null) on malformed input — e.g. a
  // truncated buffer trips a bounds check inside a format probe. Treat any such
  // failure as "undecodable" so callers get the documented `null`.
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object catch (_) {
    return null;
  }
  if (decoded == null) return null;
  final oriented = img.bakeOrientation(decoded);

  final maxEdge = oriented.width >= oriented.height
      ? oriented.width
      : oriented.height;
  final resized = maxEdge <= longEdge
      ? oriented
      : (oriented.width >= oriented.height
            ? img.copyResize(oriented, width: longEdge)
            : img.copyResize(oriented, height: longEdge));

  return img.encodeJpg(resized, quality: 85);
}
