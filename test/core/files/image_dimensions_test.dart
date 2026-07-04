import 'dart:convert';
import 'dart:io';

import 'package:cullimingo/core/files/exif_reader.dart';
import 'package:cullimingo/core/files/image_dimensions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

// Real 40×24 AVIF and 64×64 HEIC (ImageMagick), used to exercise the ISOBMFF
// `ispe` parse without a codec. The AVIF is non-square so a width/height swap
// would fail the test.
const _avif40x24 =
    'AAAAHGZ0eXBhdmlmAAAAAG1pZjFhdmlmbWlhZgAAANRtZXRhAAAAAAAAACFoZGxyAAAAAAAA'
    'AABwaWN0AAAAAAAAAAAAAAAAAAAAACJpbG9jAAAAAERAAAEAAQAAAAAA+AABAAAAAAAAACoA'
    'AAAjaWluZgAAAAAAAQAAABVpbmZlAgAAAAABAABhdjAxAAAAAA5waXRtAAAAAAABAAAAVGlw'
    'cnAAAAA2aXBjbwAAAAxhdjFDgUBsAAAAABRpc3BlAAAAAAAAACgAAAAYAAAADnBpeGkAAAAA'
    'AQwAAAAWaXBtYQAAAAAAAAABAAEDgQIDAAAAMm1kYXQSAAoJWBUnu1oCGg3CMhsZR4eGIYmm'
    'mmaAFQDcq6l/FFddFmGtwzvbIXA=';
const _heic64x64 =
    'AAAAHGZ0eXBoZWl4AAAAAG1pZjFoZWl4bWlhZgAAAWVtZXRhAAAAAAAAACFoZGxyAAAAAAAA'
    'AABwaWN0AAAAAAAAAAAAAAAAAAAAACJpbG9jAAAAAERAAAEAAQAAAAABiQABAAAAAAAAADQA'
    'AAAjaWluZgAAAAAAAQAAABVpbmZlAgAAAAABAABodmMxAAAAAA5waXRtAAAAAAABAAAA5Wlw'
    'cnAAAADGaXBjbwAAAHRodmNDAQQIAAAAAAAAAAAAHvAA/P38/AAADwNgAAEAF0ABDAH//wQI'
    'AAADAJm4AAADAAAeugJAYQABAClCAQEECAAAAwCZuAAAAwAAHqAggQRSluqumubgIaDAgAAA'
    'DIAAAAMAhGIAAQAGRAHBc8GJAAAAFGlzcGUAAAAAAAAAQAAAAEAAAAAoY2xhcAAAACgAAAAB'
    'AAAAGAAAAAH////oAAAAAv///9gAAAACAAAADnBpeGkAAAAAAQwAAAAXaXBtYQAAAAAAAAAB'
    'AAEEgQIEgwAAADxtZGF0AAAAMCgBrxMhZoLA9Sdtz//q3KIPSHUf+mPU8XfT7dC6/da1lWLl'
    'loCZuVahlKCNS47MHA==';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cm_dims');
  });
  tearDown(() => dir.delete(recursive: true));

  Future<File> write(String name, List<int> bytes) async {
    final f = File(p.join(dir.path, name));
    await f.writeAsBytes(bytes);
    return f;
  }

  group('readImageDimensions', () {
    test('reads JPEG frame size (no EXIF tags present)', () async {
      final jpeg = img.encodeJpg(img.Image(width: 640, height: 427));
      final f = await write('plain.jpg', jpeg);
      expect(await readImageDimensions(f), (width: 640, height: 427));
    });

    test('reads PNG IHDR size', () async {
      final png = img.encodePng(img.Image(width: 123, height: 45));
      final f = await write('plain.png', png);
      expect(await readImageDimensions(f), (width: 123, height: 45));
    });

    test('reads the AVIF ispe box (non-square)', () async {
      final f = await write('s.avif', base64Decode(_avif40x24));
      expect(await readImageDimensions(f), (width: 40, height: 24));
    });

    test('reads the HEIC ispe box', () async {
      final f = await write('s.heic', base64Decode(_heic64x64));
      expect(await readImageDimensions(f), (width: 64, height: 64));
    });

    test('returns null for a non-image file', () async {
      final f = await write('notes.txt', 'hello'.codeUnits);
      expect(await readImageDimensions(f), isNull);
    });

    test(
      'returns null for an ISOBMFF file without an ispe (e.g. MP4)',
      () async {
        // ftyp(isom) + a moov box, no meta/ispe.
        final ftyp = [
          0, 0, 0, 0x10, 0x66, 0x74, 0x79, 0x70, //
          0x69, 0x73, 0x6F, 0x6D, 0, 0, 0, 0,
        ];
        final moov = [0, 0, 0, 8, 0x6D, 0x6F, 0x6F, 0x76];
        final f = await write('clip.mp4', [...ftyp, ...moov]);
        expect(await readImageDimensions(f), isNull);
      },
    );
  });

  group('readPhotoExif dimension fallback', () {
    test('fills width/height from the header when EXIF lacks them', () async {
      final jpeg = img.encodeJpg(img.Image(width: 800, height: 600));
      final f = await write('exifless.jpg', jpeg);
      final exif = await readPhotoExif(f);
      expect(exif.width, 800);
      expect(exif.height, 600);
    });
  });
}
