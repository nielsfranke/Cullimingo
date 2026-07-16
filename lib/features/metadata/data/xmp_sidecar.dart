import 'dart:io';

import 'package:cullimingo/features/metadata/data/xmp_codec.dart';
import 'package:cullimingo/features/metadata/data/xmp_merge.dart';
import 'package:cullimingo/features/metadata/domain/xmp_data.dart';
import 'package:path/path.dart' as p;

/// Sidecar path for [photoPath]: same folder, basename + `.xmp` — the
/// Lightroom/Bridge convention for proprietary RAW (`DSC0001.ARW` →
/// `DSC0001.xmp`).
String sidecarPath(String photoPath) => p.setExtension(photoPath, '.xmp');

/// Reads and parses the sidecar for [photoPath], or `null` if none exists or it
/// can't be parsed.
Future<XmpData?> readSidecar(String photoPath) async {
  final file = File(sidecarPath(photoPath));
  // Async exists() (not existsSync) so a big import never blocks the UI isolate
  // — synchronous stat on iCloud-synced folders can stall for seconds each.
  // ignore: avoid_slow_async_io
  if (!await file.exists()) return null;
  try {
    return decodeXmp(await file.readAsString());
  } on Object {
    return null;
  }
}

/// Writes [data] to [photoPath]'s sidecar. An existing sidecar is *merged*
/// ([mergeXmp]): only Cullimingo-owned properties are replaced, so Lightroom
/// develop settings, GPS and other foreign tags survive a rating keystroke.
/// A missing or unparseable sidecar gets a fresh packet.
Future<void> writeSidecar(String photoPath, XmpData data) async {
  final file = File(sidecarPath(photoPath));
  String packet;
  try {
    packet = mergeXmp(await file.readAsString(), data);
  } on Object {
    // No sidecar yet, or one we can't parse (readers already treat that as
    // "no marks") — start a fresh packet rather than failing the write.
    packet = encodeXmp(data);
  }
  // Write-to-tmp + atomic rename: the sidecar is the durable source of truth,
  // so a crash mid-write must never leave a truncated packet behind.
  final tmp = File('${file.path}.culltmp');
  try {
    await tmp.writeAsString(packet, flush: true);
    await tmp.rename(file.path);
  } on Object {
    try {
      await tmp.delete();
    } on Object {
      // Best effort — a stray tmp next to the sidecar is harmless.
    }
    rethrow; // callers count sidecar-write failures
  }
}

/// The sidecar's last-modified time for [photoPath], truncated to whole seconds
/// (drift persists `DateTime` as unix seconds, so an un-truncated mtime would
/// never compare equal to a stored `xmpMtime` and every sync would treat our
/// own write as an external edit). `null` when no sidecar exists.
Future<DateTime?> readSidecarMtime(String photoPath) async {
  // Async stat (not statSync) so a large import never blocks the UI isolate —
  // a synchronous stat on iCloud-synced folders can stall for seconds each.
  // ignore: avoid_slow_async_io
  final stat = await File(sidecarPath(photoPath)).stat();
  if (stat.type == FileSystemEntityType.notFound) return null;
  final secs = stat.modified.millisecondsSinceEpoch ~/ 1000;
  return DateTime.fromMillisecondsSinceEpoch(secs * 1000);
}
