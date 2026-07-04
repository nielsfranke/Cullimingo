import 'dart:typed_data';

import 'package:cullimingo/core/raw/image_preview_extractor.dart';
import 'package:cullimingo/core/raw/libraw_preview_extractor.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';

/// Routes a thumbnail request to the right extractor by file type: RAW files go
/// to LibRaw (embedded preview), everything else to the `image` package. This
/// is the single seam the rest of the app depends on.
class PreviewService implements PreviewExtractor {
  /// Creates a service with optional custom extractors (handy for tests).
  const PreviewService({
    this.raw = const LibRawPreviewExtractor(),
    this.image = const ImagePreviewExtractor(),
  });

  /// Extractor used for RAW files.
  final PreviewExtractor raw;

  /// Extractor used for non-RAW images.
  final PreviewExtractor image;

  @override
  Future<Uint8List?> thumbnail(
    String path, {
    int longEdge = 512,
    CancelToken? cancel,
    JobPriority priority = JobPriority.visible,
  }) {
    final extractor = isRawPath(path) ? raw : image;
    return extractor.thumbnail(
      path,
      longEdge: longEdge,
      cancel: cancel,
      priority: priority,
    );
  }
}
