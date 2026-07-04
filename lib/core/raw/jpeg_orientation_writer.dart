import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cullimingo/core/files/supported_files.dart';

/// Writes [orientation] (1–8) into the embedded EXIF of the JPEG at [path],
/// **losslessly** (only the Orientation tag's bytes change — the compressed
/// pixels are never touched, so there's no recompression loss). Returns whether
/// the file was actually changed — `false` for non-JPEG paths, an out-of-range
/// [orientation], a missing file, or a JPEG we can't safely patch. Runs the
/// read/patch/write on a background isolate (Rule 2: no file I/O on the UI
/// isolate).
Future<bool> writeEmbeddedOrientation(String path, int orientation) async {
  if (!isJpegPath(path) || orientation < 1 || orientation > 8) return false;
  // Cheap stat on the caller's isolate: skip spawning a worker for a RAW or a
  // path with no file (e.g. seeded test rows) — nothing to patch there.
  if (!File(path).existsSync()) return false;
  return Isolate.run(() {
    final patched = setJpegOrientation(
      File(path).readAsBytesSync(),
      orientation,
    );
    if (patched == null) return false;
    File(path).writeAsBytesSync(patched, flush: true);
    return true;
  });
}

/// Returns a copy of the JPEG [bytes] with its EXIF Orientation set to
/// [orientation], or `null` when nothing was changed (not a JPEG, no writable
/// spot, already correct, or a malformed header). Pure — unit-testable without
/// touching the disk.
///
/// Two cases are handled: an existing EXIF APP1 whose IFD0 already carries an
/// Orientation tag is patched in place; a JPEG with no EXIF APP1 at all gets a
/// minimal one inserted right after SOI. A rarer EXIF-without-Orientation file
/// is left untouched (the sidecar still records the rotation).
Uint8List? setJpegOrientation(Uint8List bytes, int orientation) {
  if (orientation < 1 || orientation > 8) return null;
  // Must start with the SOI marker to be a JPEG.
  if (bytes.length < 2 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;

  var offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] != 0xFF) return null; // not at a marker → give up
    final marker = bytes[offset + 1];
    // Standalone markers (RSTn, SOI, EOI) have no length; SOS starts scan data.
    if (marker == 0xD9 || marker == 0xDA) break;
    final segLen = (bytes[offset + 2] << 8) | bytes[offset + 3];
    if (segLen < 2 || offset + 2 + segLen > bytes.length) return null;
    final dataStart = offset + 4;

    // APP1 with the "Exif\0\0" signature holds the TIFF/EXIF block.
    if (marker == 0xE1 &&
        dataStart + 6 <= bytes.length &&
        bytes[dataStart] == 0x45 && // E
        bytes[dataStart + 1] == 0x78 && // x
        bytes[dataStart + 2] == 0x69 && // i
        bytes[dataStart + 3] == 0x66 && // f
        bytes[dataStart + 4] == 0x00 &&
        bytes[dataStart + 5] == 0x00) {
      final patched = _patchExifOrientation(bytes, dataStart + 6, orientation);
      // A present-but-Orientation-less EXIF block returns null → leave the file
      // as-is (the sidecar carries the rotation for these rarer JPEGs).
      return patched;
    }

    // Skip APP0/other segments; stop scanning once we're past the header block
    // (a frame marker SOFn means no EXIF is coming).
    if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xCC) {
      break;
    }
    offset = dataStart + (segLen - 2);
  }

  // No EXIF APP1 found → splice a minimal one in right after the SOI.
  return _insertExifApp1(bytes, orientation);
}

// Patches the Orientation tag inside the TIFF block that starts at [tiffStart].
// Returns the modified bytes, or null if the block is malformed or has no
// Orientation tag.
Uint8List? _patchExifOrientation(Uint8List bytes, int tiffStart, int value) {
  if (tiffStart + 8 > bytes.length) return null;
  final bigEndian = bytes[tiffStart] == 0x4D && bytes[tiffStart + 1] == 0x4D;
  final littleEndian = bytes[tiffStart] == 0x49 && bytes[tiffStart + 1] == 0x49;
  if (!bigEndian && !littleEndian) return null;

  int u16(int at) => bigEndian
      ? (bytes[at] << 8) | bytes[at + 1]
      : (bytes[at + 1] << 8) | bytes[at];
  int u32(int at) => bigEndian
      ? (bytes[at] << 24) |
            (bytes[at + 1] << 16) |
            (bytes[at + 2] << 8) |
            bytes[at + 3]
      : (bytes[at + 3] << 24) |
            (bytes[at + 2] << 16) |
            (bytes[at + 1] << 8) |
            bytes[at];

  final ifdOffset = u32(tiffStart + 4);
  final ifd0 = tiffStart + ifdOffset;
  if (ifd0 + 2 > bytes.length) return null;
  final count = u16(ifd0);
  final entriesStart = ifd0 + 2;
  if (entriesStart + count * 12 > bytes.length) return null;

  for (var i = 0; i < count; i++) {
    final entry = entriesStart + i * 12;
    if (u16(entry) == 0x0112) {
      // SHORT value lives in the first 2 bytes of the entry's value field.
      final valueAt = entry + 8;
      final out = Uint8List.fromList(bytes);
      if (bigEndian) {
        out[valueAt] = 0x00;
        out[valueAt + 1] = value & 0xFF;
      } else {
        out[valueAt] = value & 0xFF;
        out[valueAt + 1] = 0x00;
      }
      return out;
    }
  }
  return null;
}

// Builds a minimal big-endian ("MM") EXIF APP1 segment carrying only the
// Orientation tag and splices it in right after the SOI marker.
Uint8List _insertExifApp1(Uint8List bytes, int orientation) {
  final payload = <int>[
    0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // "Exif\0\0"
    0x4D, 0x4D, // big-endian
    0x00, 0x2A, // TIFF magic
    0x00, 0x00, 0x00, 0x08, // IFD0 at offset 8
    0x00, 0x01, // one entry
    0x01, 0x12, // tag = Orientation
    0x00, 0x03, // type = SHORT
    0x00, 0x00, 0x00, 0x01, // count = 1
    0x00, orientation & 0xFF, 0x00, 0x00, // value (SHORT in the high 2 bytes)
    0x00, 0x00, 0x00, 0x00, // next-IFD offset = 0
  ];
  final segLen = payload.length + 2; // length field counts itself
  final app1 = <int>[
    0xFF,
    0xE1,
    (segLen >> 8) & 0xFF,
    segLen & 0xFF,
    ...payload,
  ];

  final out = BytesBuilder()
    ..add([bytes[0], bytes[1]]) // SOI
    ..add(app1)
    ..add(Uint8List.sublistView(bytes, 2));
  return out.toBytes();
}
