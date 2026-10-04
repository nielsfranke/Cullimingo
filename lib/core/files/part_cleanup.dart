import 'dart:io';
import 'dart:isolate';

import 'package:cullimingo/core/files/verified_copy.dart';
import 'package:path/path.dart' as p;

/// Exactly the names [partPathFor] produces: `.<name>.<12 hex>.part`. Nothing
/// else — not a user's `photo.part`, not `.x.part` — is ever touched.
final RegExp kPartFileName = RegExp(r'^\..+\.[0-9a-f]{12}\.part$');

/// How long a part file must have gone untouched (its status-change time)
/// before it counts as left behind. A copy in flight keeps touching its part
/// file, so an hour-idle one belongs to a run that crashed or was killed —
/// never to a concurrent run.
const Duration kStalePartAge = Duration(hours: 1);

/// Deletes stale part files ([kPartFileName], older than [olderThan]) directly
/// inside each of [dirs] — one listing per folder, never a walk of the whole
/// destination. Missing folders are skipped. Returns how many were removed.
///
/// Blocking I/O: use [removeStalePartFiles] from the UI isolate.
int removeStalePartFilesSync(
  Iterable<String> dirs, {
  Duration olderThan = kStalePartAge,
  DateTime? now,
}) {
  final cutoff = (now ?? DateTime.now()).subtract(olderThan);
  var removed = 0;
  for (final dir in dirs.toSet()) {
    final List<FileSystemEntity> entries;
    try {
      entries = Directory(dir).listSync(followLinks: false);
    } on FileSystemException {
      continue; // not there (yet) or unreadable: nothing of ours to clean
    }
    for (final entry in entries) {
      if (entry is! File) continue;
      final name = p.basename(entry.path);
      if (!kPartFileName.hasMatch(name)) continue;
      try {
        // ctime, not mtime: a copy sets its part file's mtime back to the
        // photo's capture date just before publishing it, which would make
        // a live part file look ancient. Every write and that very mtime
        // change bump ctime to now.
        if (entry.statSync().changed.isBefore(cutoff)) {
          entry.deleteSync();
          removed++;
        }
      } on FileSystemException {
        // Best effort: gone already, or not ours to delete.
      }
    }
  }
  return removed;
}

/// [removeStalePartFilesSync] off the UI isolate. Best effort: a hung mount or
/// any error yields 0 after [timeout] — it never holds up or fails a run.
Future<int> removeStalePartFiles(
  Iterable<String> dirs, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final list = dirs.toSet().toList();
  if (list.isEmpty) return 0;
  try {
    return await Isolate.run(
      () => removeStalePartFilesSync(list),
    ).timeout(timeout, onTimeout: () => 0);
  } on Object {
    return 0;
  }
}
