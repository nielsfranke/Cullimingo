import 'dart:io';

import 'package:cullimingo/core/raw/libraw_preview_extractor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  final libPath = LibRawPreviewExtractor.resolveLibraryPath();
  final hasLibRaw = libPath != null;

  test(
    'resolveLibraryPath points at a real dylib when libraw is installed',
    () {
      if (!hasLibRaw) {
        markTestSkipped('libraw not installed on this machine');
        return;
      }
      expect(File(libPath).existsSync(), isTrue);
    },
  );

  test('returns null for a missing file', () async {
    expect(
      await const LibRawPreviewExtractor().thumbnail('/no/such.arw'),
      null,
    );
  });

  test('loads the FFI lib and fails gracefully on a non-RAW file', () async {
    if (!hasLibRaw) {
      markTestSkipped('libraw not installed on this machine');
      return;
    }
    final tmp = await Directory.systemTemp.createTemp('libraw_test');
    addTearDown(() => tmp.delete(recursive: true));
    final jpg = File(p.join(tmp.path, 'x.jpg'))
      ..writeAsBytesSync(img.encodeJpg(img.Image(width: 8, height: 8)));

    // A JPEG is not a RAW: libraw_open_file fails, so we get null — proving the
    // dylib loads and the FFI sequence degrades cleanly (no crash).
    expect(await const LibRawPreviewExtractor().thumbnail(jpg.path), isNull);
  });
}
