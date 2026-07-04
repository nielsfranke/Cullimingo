import 'dart:io';
import 'dart:typed_data';

import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/core/raw/preview_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  group('isRawPath', () {
    test('recognises common RAW extensions, case-insensitively', () {
      expect(isRawPath('/x/DSC_0001.ARW'), isTrue);
      expect(isRawPath('/x/img.cr3'), isTrue);
      expect(isRawPath('/x/photo.NEF'), isTrue);
    });

    test('treats JPEG/PNG as non-RAW', () {
      expect(isRawPath('/x/img.jpg'), isFalse);
      expect(isRawPath('/x/img.jpeg'), isFalse);
      expect(isRawPath('/x/img.png'), isFalse);
    });
  });

  group('PreviewService JPEG path', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('cullimingo_preview');
    });

    tearDown(() async {
      await tmp.delete(recursive: true);
    });

    Future<File> writeJpeg(int w, int h) async {
      final image = img.Image(width: w, height: h);
      img.fill(image, color: img.ColorRgb8(40, 110, 255));
      final file = File(p.join(tmp.path, '${w}x$h.jpg'));
      await file.writeAsBytes(img.encodeJpg(image));
      return file;
    }

    test('downscales a large JPEG so its long edge is ~longEdge', () async {
      final file = await writeJpeg(2000, 1000);
      const service = PreviewService();

      final bytes = await service.thumbnail(file.path, longEdge: 256);

      expect(bytes, isNotNull);
      final out = img.decodeJpg(bytes!)!;
      expect(out.width, 256);
      expect(out.height, 128);
    });

    test('does not upscale a small JPEG', () async {
      final file = await writeJpeg(120, 90);
      const service = PreviewService();

      final out = img.decodeJpg((await service.thumbnail(file.path))!)!;
      expect(out.width, 120);
      expect(out.height, 90);
    });

    test('returns null for a missing file', () async {
      const service = PreviewService();
      expect(await service.thumbnail('/no/such/file.jpg'), isNull);
    });

    test('RAW path is stubbed (null) until LibRaw is wired', () async {
      // A .arw routes to the LibRaw extractor, which is intentionally inert.
      final file = File(p.join(tmp.path, 'DSC_0001.arw'))
        ..writeAsBytesSync(Uint8List.fromList(const [0, 1, 2, 3]));
      const service = PreviewService();
      expect(await service.thumbnail(file.path), isNull);
    });
  });
}
