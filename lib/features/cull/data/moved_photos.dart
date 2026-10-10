import 'dart:io';

import 'package:cullimingo/core/db/database.dart';

/// After a Move to folder…, drops the rows of [sources] that are no longer on
/// disk from [importId]'s read model and returns their paths. Without this the
/// grid kept a moved photo at its old path, and a later Delete "trashed" the
/// missing file, reporting success while nothing happened (GitHub #14).
///
/// Decided by the disk, not the transfer's report: a failed, conflicting or
/// cancelled move keeps its original — and so its row and marks.
Future<List<String>> forgetMovedPhotos({
  required AppDatabase db,
  required int importId,
  required Iterable<String> sources,
}) async {
  final gone = <String>[];
  for (final path in sources) {
    // Async exists() so a check over a network share never stalls the UI
    // isolate (matches move_to_trash.dart).
    // ignore: avoid_slow_async_io
    if (!await File(path).exists()) gone.add(path);
  }
  await db.deletePhotosByPaths(importId, gone);
  return gone;
}
