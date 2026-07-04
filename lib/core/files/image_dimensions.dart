import 'dart:io';
import 'dart:typed_data';

/// Full-image pixel dimensions read straight from an image file's own header —
/// the JPEG frame (`SOFn`), PNG `IHDR`, or the HEIF/AVIF `ispe` box — without
/// decoding any pixel data.
///
/// This is the fallback for `readPhotoExif` when a file carries no EXIF
/// `ExifImageWidth`/`Length` tags: JPEGs often drop them (processed/exported
/// files), and HEIF/AVIF don't use EXIF for size at all. The header always knows
/// the true size, so the inspector can show real dimensions instead of `—`.
/// Reads only header bytes, so it stays cheap; still, call off the UI isolate
/// for big batches (the scan already does).
Future<({int width, int height})?> readImageDimensions(File file) async {
  RandomAccessFile? raf;
  try {
    raf = await file.open();
    final head = await raf.read(32);
    final png = _pngSize(head);
    if (png != null) return png;
    if (head.length >= 2 && head[0] == 0xFF && head[1] == 0xD8) {
      return await _jpegSize(raf);
    }
    if (_isIsobmff(head)) {
      // HEIF/AVIF: the `ispe` box lives in the `meta` box near the file start,
      // so a bounded prefix is enough. iPhone HEIC and AVIF put `meta` first.
      final length = await raf.length();
      await raf.setPosition(0);
      final prefix = await raf.read(
        length < _heifScanBytes ? length : _heifScanBytes,
      );
      return _heifIspeSize(prefix);
    }
    return null;
  } on Object {
    return null;
  } finally {
    await raf?.close();
  }
}

/// How far into a HEIF/AVIF file we scan for the `meta`/`ispe` boxes.
const int _heifScanBytes = 256 * 1024;

/// ISO Base Media File Format (HEIF/AVIF/MP4…): a `ftyp` box at offset 4.
bool _isIsobmff(Uint8List head) =>
    head.length >= 8 &&
    head[4] == 0x66 && // 'f'
    head[5] == 0x74 && // 't'
    head[6] == 0x79 && // 'y'
    head[7] == 0x70; // 'p'

/// Walks the ISOBMFF box tree in [bytes] (a HEIF/AVIF header prefix) and returns
/// the largest `ispe` (ImageSpatialExtents) size — the primary image, so a
/// smaller thumbnail's `ispe` never wins. `null` when no `ispe` is present
/// (e.g. a plain MP4/MOV video, which has none). Recurses only into the
/// container boxes that lead to `ispe` (`meta` → `iprp` → `ipco`).
({int width, int height})? _heifIspeSize(Uint8List bytes) {
  ({int width, int height})? best;
  void walk(int start, int end) {
    var pos = start;
    while (pos + 8 <= end) {
      var size = _u32(bytes, pos);
      final type = String.fromCharCodes(bytes, pos + 4, pos + 8);
      var contentStart = pos + 8;
      if (size == 1) {
        // 64-bit largesize. A box big enough to need it won't be an `ispe`
        // container within our bounded prefix, so bail if the high word is set.
        if (pos + 16 > end || _u32(bytes, pos + 8) != 0) return;
        size = _u32(bytes, pos + 12);
        contentStart = pos + 16;
      }
      final boxEnd = size == 0
          ? end // "to end of file" — clamped to the prefix
          : (pos + size <= end ? pos + size : end);
      if (boxEnd < contentStart) return; // malformed
      switch (type) {
        case 'ispe':
          // FullBox: version(1) + flags(3), then width(4) + height(4).
          if (contentStart + 12 <= boxEnd) {
            final w = _u32(bytes, contentStart + 4);
            final h = _u32(bytes, contentStart + 8);
            if (w > 0 &&
                h > 0 &&
                (best == null || w * h > best!.width * best!.height)) {
              best = (width: w, height: h);
            }
          }
        case 'meta': // FullBox container: skip version+flags before children.
          walk(contentStart + 4, boxEnd);
        case 'iprp':
        case 'ipco':
          walk(contentStart, boxEnd);
      }
      if (size == 0) break;
      pos = boxEnd;
    }
  }

  walk(0, bytes.length);
  return best;
}

const List<int> _pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// PNG: `IHDR` is the first chunk; width/height are the two big-endian uint32s
/// at offset 16.
({int width, int height})? _pngSize(Uint8List head) {
  if (head.length < 24) return null;
  for (var i = 0; i < _pngMagic.length; i++) {
    if (head[i] != _pngMagic[i]) return null;
  }
  final width = _u32(head, 16);
  final height = _u32(head, 20);
  if (width <= 0 || height <= 0) return null;
  return (width: width, height: height);
}

/// JPEG: walk the marker segments (each carries its own length) until the frame
/// header (`SOF0`–`SOF15`, excluding the non-frame `DHT`/`JPG`/`DAC` markers),
/// whose payload is precision(1) + height(2) + width(2). Skipping by segment
/// length means a big EXIF/ICC/thumbnail block before the frame doesn't matter.
Future<({int width, int height})?> _jpegSize(RandomAccessFile raf) async {
  var pos = 2; // past SOI (FF D8)
  final length = await raf.length();
  while (pos + 4 <= length) {
    await raf.setPosition(pos);
    final marker = await raf.read(4);
    if (marker.length < 4 || marker[0] != 0xFF) return null;
    final code = marker[1];
    // Standalone markers (no length): RSTn, SOI, EOI, TEM.
    if (code == 0x01 || (code >= 0xD0 && code <= 0xD9)) {
      pos += 2;
      continue;
    }
    final segLen = (marker[2] << 8) | marker[3];
    final isFrame =
        code >= 0xC0 &&
        code <= 0xCF &&
        code != 0xC4 && // DHT
        code != 0xC8 && // JPG
        code != 0xCC; // DAC
    if (isFrame) {
      // marker(2) + length(2) already read; next is precision(1) then h/w.
      final frame = await raf.read(5);
      if (frame.length < 5) return null;
      final height = (frame[1] << 8) | frame[2];
      final width = (frame[3] << 8) | frame[4];
      if (width <= 0 || height <= 0) return null;
      return (width: width, height: height);
    }
    if (segLen < 2) return null;
    pos += 2 + segLen;
  }
  return null;
}

int _u32(Uint8List b, int i) =>
    (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
