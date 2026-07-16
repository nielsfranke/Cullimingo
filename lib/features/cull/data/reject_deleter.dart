import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/files/move_to_trash.dart';
import 'package:cullimingo/core/files/sidecar_path.dart';

/// The trash step, injectable so tests run without touching the OS trash.
typedef Trasher =
    Future<TrashResult> Function(
      List<String> paths, {
      void Function(int processed, int total)? onProgress,
    });

/// Outcome of a delete-rejects run.
class RejectDeleteResult {
  /// Creates a result.
  const RejectDeleteResult({
    required this.deleted,
    required this.failedPaths,
    this.error,
  });

  /// Photos whose file went to the trash — their rows are gone from the read
  /// model.
  final int deleted;

  /// Photo files the OS refused to trash; their rows (and marks) are kept.
  final List<String> failedPaths;

  /// A run-level trash problem (tool missing, unsupported platform), or null.
  final String? error;
}

/// Moves every photo in [rejects] to the OS trash together with its `.xmp`
/// sidecar, then removes the successfully-trashed photos' rows from
/// [importId]'s read model. A photo whose file could not be trashed keeps its
/// row and marks, so nothing silently disappears from the grid while still on
/// disk. Never a hard delete — everything lands in the trash, restorable.
Future<RejectDeleteResult> deleteRejectedPhotos({
  required AppDatabase db,
  required int importId,
  required List<Photo> rejects,
  Trasher trash = moveToTrash,
  void Function(int processed, int total)? onProgress,
}) async {
  if (rejects.isEmpty) {
    return const RejectDeleteResult(deleted: 0, failedPaths: []);
  }
  // Photo + sidecar per reject; a missing sidecar is skipped by the trasher.
  final paths = <String>[
    for (final photo in rejects) ...[photo.path, sidecarPath(photo.path)],
  ];
  final result = await trash(paths, onProgress: onProgress);

  final failed = result.failed.toSet();
  final deletable = <String>[];
  final kept = <String>[];
  for (final photo in rejects) {
    (failed.contains(photo.path) ? kept : deletable).add(photo.path);
  }
  await db.deletePhotosByPaths(importId, deletable);

  return RejectDeleteResult(
    deleted: deletable.length,
    failedPaths: kept,
    error: result.error,
  );
}
