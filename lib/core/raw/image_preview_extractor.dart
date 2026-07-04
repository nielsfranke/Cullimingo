import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cullimingo/core/raw/jpeg_resize.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';

/// Decodes non-RAW images (JPEG/PNG/…) with the pure-Dart `image` package.
///
/// The decode + resize + re-encode runs in a one-off background isolate via
/// [Isolate.run]; the persistent isolate pool arrives in Phase 2 (§2). Keeping
/// it behind [PreviewExtractor] lets us swap in libvips later without touching
/// callers.
class ImagePreviewExtractor implements PreviewExtractor {
  /// Creates an image-package backed extractor.
  const ImagePreviewExtractor();

  @override
  Future<Uint8List?> thumbnail(
    String path, {
    int longEdge = 512,
    CancelToken? cancel,
    JobPriority priority = JobPriority.visible,
  }) async {
    final file = File(path);
    if (!file.existsSync()) return null;
    final bytes = await file.readAsBytes();
    return Isolate.run(() => downscaleToJpeg(bytes, longEdge));
  }
}
