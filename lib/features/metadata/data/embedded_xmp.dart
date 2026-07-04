import 'dart:convert';
import 'dart:io';

import 'package:cullimingo/features/metadata/data/xmp_codec.dart';
import 'package:cullimingo/features/metadata/domain/xmp_data.dart';

/// How many bytes from the start of an image we scan for the XMP packet. The
/// standard XMP APP1 segment sits near the file header and a single JPEG marker
/// caps at 64 KB; 256 KB is a generous bound that keeps the read cheap even on
/// large files.
const int _scanBytes = 256 * 1024;

/// Extracts the XMP packet (`<x:xmpmeta>…</x:xmpmeta>`) embedded in image
/// [content], or `null` if there is none. Pure: slices between the packet's
/// literal start/end tags, so it tolerates the surrounding binary of a JPEG.
String? extractXmpPacket(String content) {
  const start = '<x:xmpmeta';
  const end = '</x:xmpmeta>';
  final from = content.indexOf(start);
  if (from < 0) return null;
  final to = content.indexOf(end, from);
  if (to < 0) return null;
  return content.substring(from, to + end.length);
}

/// Reads rating/label/keywords from the XMP embedded *inside* the image at
/// [path] — what Capture One / Lightroom write into an exported JPEG/HEIC/TIFF
/// (which carries no `.xmp` sidecar). Returns `null` when the file has no
/// readable packet. Only a bounded prefix is read, so it stays cheap; still,
/// call it off the UI isolate for large batches.
Future<XmpData?> readEmbeddedXmp(String path) async {
  RandomAccessFile? raf;
  try {
    raf = await File(path).open();
    final length = await raf.length();
    final count = length < _scanBytes ? length : _scanBytes;
    final bytes = await raf.read(count);
    final packet = extractXmpPacket(utf8.decode(bytes, allowMalformed: true));
    if (packet == null) return null;
    return decodeXmp(packet);
  } on Object {
    return null;
  } finally {
    await raf?.close();
  }
}
