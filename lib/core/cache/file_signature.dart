import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Derives a fast cache key for [file] from its path + size + mtime, salted by
/// tier (`BUILD_PLAN.md` §3).
///
/// Uses `stat` metadata only — **no file content is read** — so it stays cheap
/// even for a 24 MB RAW on a slow external drive and never stalls the grid
/// (§0.6). RAW/JPEG originals are immutable in practice, so size + mtime
/// reliably invalidates the cache when a file changes.
///
/// The stat runs async (dart:io thread pool), so calling this from the UI
/// isolate never blocks a frame even when the file sits on slow removable
/// media. Pass [stat] when the caller already has one to skip the syscall.
Future<String> fileSignature(
  File file, {
  String salt = '',
  FileStat? stat,
}) async {
  // Deliberately async — see the doc comment above.
  // ignore: avoid_slow_async_io
  stat ??= await file.stat();
  final meta = utf8.encode(
    '${file.path}:${stat.size}:${stat.modified.microsecondsSinceEpoch}:$salt',
  );
  return sha1.convert(meta).toString();
}
