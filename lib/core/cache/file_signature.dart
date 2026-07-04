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
Future<String> fileSignature(File file, {String salt = ''}) async {
  final stat = file.statSync();
  final meta = utf8.encode(
    '${file.path}:${stat.size}:${stat.modified.microsecondsSinceEpoch}:$salt',
  );
  return sha1.convert(meta).toString();
}
