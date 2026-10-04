import 'dart:io';
import 'dart:isolate';

import 'package:cullimingo/core/files/verified_copy.dart';
import 'package:path/path.dart' as p;

/// Exactly the names [partPathFor] produces:
/// `.<name>.<12 hex>.<epoch seconds>.part` (group 1: the creation time).
/// Nothing else — not a user's `photo.part`, not `.x.part` — is ever touched.
final RegExp kPartFileName = RegExp(
  r'^\..+\.[0-9a-f]{12}\.([0-9]{9,12})\.part$',
);

/// How long ago a part file must have been created (the time in its name)
/// before it counts as left behind. A copy publishes its part file within
/// seconds to minutes, so an hour-old one belongs to a run that crashed or
/// was killed — never to a concurrent run. File times aren't used: a copy
/// sets its part file's mtime to the capture date, and exFAT/FAT keep no
/// separate ctime, so a live part file there looks years old.
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
      final match = kPartFileName.firstMatch(p.basename(entry.path));
      if (match == null) continue;
      final created = DateTime.fromMillisecondsSinceEpoch(
        int.parse(match[1]!) * 1000,
      );
      if (!created.isBefore(cutoff)) continue;
      try {
        entry.deleteSync();
        removed++;
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
