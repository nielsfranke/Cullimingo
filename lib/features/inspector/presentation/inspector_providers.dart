import 'package:cullimingo/features/inspector/data/exif_detail.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'inspector_providers.g.dart';

/// Whether the read-only metadata inspector side panel is open (Phase 8).
/// Session state — not persisted; a panel toggle need not survive relaunch.
@riverpod
class InspectorOpen extends _$InspectorOpen {
  @override
  bool build() => false;

  /// Flips the panel open/closed.
  void toggle() => state = !state;
}

/// EXIF detail for the file at [path], read in a background isolate. Keyed by
/// path so changing focus re-reads; auto-dispose frees it when focus moves on
/// or the panel closes.
@riverpod
Future<ExifDetail> focusedExif(Ref ref, String path) => readExifDetail(path);
