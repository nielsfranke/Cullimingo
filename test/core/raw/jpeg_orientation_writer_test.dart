import 'dart:typed_data';

import 'package:cullimingo/core/raw/jpeg_orientation_writer.dart';
import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Future<int?> _readOrientation(Uint8List bytes) async {
  final tags = await readExifFromBytes(bytes);
  final v = tags['Image Orientation']?.values.toList();
  if (v == null || v.isEmpty) return null;
  final first = v.first;
  return first is int ? first : int.tryParse('$first');
}

void main() {
  test('patches an existing EXIF Orientation tag losslessly', () async {
    final image = img.Image(width: 8, height: 6);
    image.exif.imageIfd['Orientation'] = 6; // rotated 90° CW
    final original = Uint8List.fromList(img.encodeJpg(image));

    final patched = setJpegOrientation(original, 8);
    expect(patched, isNotNull);
    // In-place patch: same length, only the tag's bytes differ.
    expect(patched!.length, original.length);
    expect(await _readOrientation(patched), 8);
  });

  test('inserts a minimal EXIF block when the JPEG carries none', () async {
    // A bare SOI + EOI JPEG — no APP1 at all.
    final bare = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

    final patched = setJpegOrientation(bare, 6);
    expect(patched, isNotNull);
    expect(patched!.length, greaterThan(bare.length));
    expect(await _readOrientation(patched), 6);
  });

  test('handles a little-endian ("II") TIFF block', () async {
    // The `image` encoder writes big-endian; craft a little-endian file by hand
    // and confirm the patcher respects the byte order.
    final le = Uint8List.fromList([
      0xFF, 0xD8, // SOI
      0xFF, 0xE1, 0x00, 0x20, // APP1, length 32
      0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // "Exif\0\0"
      0x49, 0x49, 0x2A, 0x00, // little-endian TIFF
      0x08, 0x00, 0x00, 0x00, // IFD0 at offset 8
      0x01, 0x00, // one entry
      0x12, 0x01, 0x03, 0x00, // tag=Orientation, type=SHORT
      0x01, 0x00, 0x00, 0x00, // count 1
      0x01, 0x00, 0x00, 0x00, // value = 1
      0x00, 0x00, 0x00, 0x00, // next IFD
      0xFF, 0xD9, // EOI
    ]);

    final patched = setJpegOrientation(le, 6);
    expect(patched, isNotNull);
    expect(await _readOrientation(patched!), 6);
  });

  test('returns null for non-JPEG or out-of-range input', () {
    expect(setJpegOrientation(Uint8List.fromList([1, 2, 3]), 6), isNull);
    final jpeg = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 2, height: 2)),
    );
    expect(setJpegOrientation(jpeg, 0), isNull);
    expect(setJpegOrientation(jpeg, 9), isNull);
  });
}
