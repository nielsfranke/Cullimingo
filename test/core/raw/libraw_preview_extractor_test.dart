import 'dart:io';
import 'dart:typed_data';

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

  group('EmbeddedRawPreview.isUsable', () {
    EmbeddedRawPreview preview(int width, int height) => EmbeddedRawPreview(
      bytes: Uint8List(0),
      width: width,
      height: height,
    );

    test('rejects a tiny embedded thumbnail', () {
      expect(preview(160, 120).isUsable, isFalse);
    });

    test('accepts a normal embedded preview regardless of cache tier', () {
      expect(preview(512, 341).isUsable, isTrue);
      expect(preview(1600, 1067).isUsable, isTrue);
    });

    test('keeps the old fast path when dimensions are unknown', () {
      expect(preview(0, 0).isUsable, isTrue);
    });
  });

  test('reads JPEG dimensions without decoding pixels', () {
    final encoded = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 37, height: 23)),
    );
    expect(jpegDimensions(encoded), (width: 37, height: 23));
    expect(
      jpegDimensions(Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9])),
      isNull,
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
