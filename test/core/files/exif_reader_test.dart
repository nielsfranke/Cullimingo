import 'dart:io';
import 'dart:typed_data';

import 'package:cullimingo/core/files/exif_reader.dart';
import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
// Rational isn't re-exported from package:image, but building a GPS fixture
// needs multi-value rationals assigned as raw IfdValues (the string-keyed
// setter resolves GPS tag ids against the image tag table and drops them).
import 'package:image/src/util/rational.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cullimingo_exif');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  File writeJpegWithExif({String dateTimeOriginal = '2026:06:01 10:30:45'}) {
    final image = img.Image(width: 24, height: 16);
    image.exif.imageIfd['Make'] = 'Sony';
    image.exif.imageIfd['Model'] = 'ILCE-7M4';
    image.exif.exifIfd['DateTimeOriginal'] = dateTimeOriginal;
    final file = File(p.join(tmp.path, 'shot.jpg'))
      ..writeAsBytesSync(img.encodeJpg(image));
    return file;
  }

  /// A JPEG whose GPS block holds 52°31'12.3" N, 13°24'36.9" W (deg/min/sec
  /// rationals, the standard camera encoding).
  File writeJpegWithGps() {
    final image = img.Image(width: 24, height: 16);
    // At least one ifd0 entry, or the encoder writes no EXIF block at all.
    image.exif.imageIfd['Make'] = 'Sony';
    image.exif.gpsIfd['GPSLatitudeRef'] = img.IfdValueAscii('N');
    image.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational.list([
      Rational(52, 1),
      Rational(31, 1),
      Rational(1230, 100),
    ]);
    image.exif.gpsIfd['GPSLongitudeRef'] = img.IfdValueAscii('W');
    image.exif.gpsIfd['GPSLongitude'] = img.IfdValueRational.list([
      Rational(13, 1),
      Rational(24, 1),
      Rational(3690, 100),
    ]);
    final file = File(p.join(tmp.path, 'gps.jpg'))
      ..writeAsBytesSync(img.encodeJpg(image));
    return file;
  }

  test('parses capture time and camera from EXIF', () async {
    final exif = await readPhotoExif(writeJpegWithExif());

    expect(exif.capturedAt, DateTime(2026, 6, 1, 10, 30, 45));
    expect(exif.camera, 'Sony ILCE-7M4');
  });

  test('an impossible capture date is unknown, not rolled over', () async {
    // DateTime(2026, 2, 31) is March 3 — the photo would land in the wrong
    // day folder. A corrupt clock must read as "no date" instead.
    for (final raw in ['2026:02:31 10:00:00', '2026:06:01 24:10:00']) {
      final exif = await readPhotoExif(
        writeJpegWithExif(dateTimeOriginal: raw),
      );
      expect(exif.capturedAt, isNull, reason: raw);
    }
  });

  test('reads the EXIF orientation value', () async {
    final image = img.Image(width: 24, height: 16);
    image.exif.imageIfd['Make'] = 'Sony';
    image.exif.imageIfd['Orientation'] = 6; // rotated 90° CW
    final file = File(p.join(tmp.path, 'portrait.jpg'))
      ..writeAsBytesSync(img.encodeJpg(image));

    expect((await readPhotoExif(file)).orientation, 6);
  });

  test('orientation is null when the tag is absent', () async {
    expect((await readPhotoExif(writeJpegWithExif())).orientation, isNull);
  });

  test(
    'converts the GPS deg/min/sec rationals to signed decimal degrees',
    () async {
      final exif = await readPhotoExif(writeJpegWithGps());

      // 52 + 31/60 + 12.30/3600 = 52.520083…; west longitude is negative.
      expect(exif.latitude, closeTo(52.520083, 0.000001));
      expect(exif.longitude, closeTo(-13.410250, 0.000001));
    },
  );

  test('a photo without a GPS block has no coordinates', () async {
    final exif = await readPhotoExif(writeJpegWithExif());
    expect(exif.latitude, isNull);
    expect(exif.longitude, isNull);
  });

  test('parses exposure bias and exposure time', () async {
    final image = img.Image(width: 24, height: 16);
    image.exif.imageIfd['Make'] = 'FUJIFILM';
    image.exif.exifIfd['ExposureBiasValue'] = img.IfdValueSRational(-3, 1);
    image.exif.exifIfd['ExposureTime'] = img.IfdValueRational(1, 100);
    final file = File(p.join(tmp.path, 'bracket.jpg'))
      ..writeAsBytesSync(img.encodeJpg(image));

    final exif = await readPhotoExif(file);
    expect(exif.exposureBias, -3.0);
    expect(exif.exposureTime, closeTo(0.01, 0.000001));
  });

  test('exposure fields are null when the tags are absent', () async {
    final exif = await readPhotoExif(writeJpegWithExif());
    expect(exif.exposureBias, isNull);
    expect(exif.exposureTime, isNull);
  });

  test('returns empty for a file without EXIF', () async {
    final plain = File(p.join(tmp.path, 'plain.jpg'))
      ..writeAsBytesSync(img.encodeJpg(img.Image(width: 8, height: 8)));

    final exif = await readPhotoExif(plain);
    expect(exif.capturedAt, isNull);
    expect(exif.camera, isNull);
  });

  test('returns empty (no throw) for a non-image file', () async {
    final junk = File(p.join(tmp.path, 'x.arw'))
      ..writeAsBytesSync(const [0, 1, 2, 3, 4]);

    expect((await readPhotoExif(junk)).isEmpty, isTrue);
  });

  group('header-only reads', () {
    test('a large JPEG is read from its first bytes', () async {
      // Noise doesn't compress: well over the largest header prefix.
      final image = img.Image(width: 1200, height: 1200);
      for (final px in image) {
        px
          ..r = (px.x * 7919 + px.y * 104729) % 256
          ..g = (px.x * 31 + px.y * 17) % 256
          ..b = (px.x ^ px.y) % 256;
      }
      image.exif.imageIfd['Make'] = 'Sony';
      image.exif.exifIfd['DateTimeOriginal'] = '2026:06:01 10:30:45';
      final file = File(p.join(tmp.path, 'big.jpg'))
        ..writeAsBytesSync(img.encodeJpg(image));
      expect(file.lengthSync(), greaterThan(kExifHeadSizes.last));

      final exif = await readPhotoExif(file);
      expect(exif.capturedAt, DateTime(2026, 6, 1, 10, 30, 45));
      expect(exif.camera, 'Sony');
    });

    test('tags beyond the header prefix are still found', () async {
      // A little-endian TIFF whose only IFD sits past the largest prefix, as
      // a RAW with its metadata at the end would.
      final ifdAt = kExifHeadSizes.last + 4096;
      const date = '2025:12:24 18:00:00\u0000'; // 20 bytes incl. NUL
      final bytes = ByteData(ifdAt + 2 + 12 + 4 + date.length)
        ..setUint8(0, 0x49) // I
        ..setUint8(1, 0x49) // I
        ..setUint16(2, 42, Endian.little)
        ..setUint32(4, ifdAt, Endian.little)
        ..setUint16(ifdAt, 1, Endian.little) // one entry
        ..setUint16(ifdAt + 2, 0x0132, Endian.little) // DateTime
        ..setUint16(ifdAt + 4, 2, Endian.little) // ASCII
        ..setUint32(ifdAt + 6, date.length, Endian.little)
        ..setUint32(ifdAt + 10, ifdAt + 18, Endian.little) // value offset
        ..setUint32(ifdAt + 14, 0, Endian.little); // no next IFD
      for (var i = 0; i < date.length; i++) {
        bytes.setUint8(ifdAt + 18 + i, date.codeUnitAt(i));
      }
      final file = File(p.join(tmp.path, 'late.tif'))
        ..writeAsBytesSync(bytes.buffer.asUint8List());

      final exif = await readPhotoExif(file);
      expect(exif.capturedAt, DateTime(2025, 12, 24, 18));
    });

    // Opt-in, local only (see test/core/raw/raw_samples_test.dart): every real
    // camera file in CULLIMINGO_SAMPLES must read exactly as the exif
    // package's full file reader reads it, for every tag PhotoExif uses.
    final samples = Platform.environment['CULLIMINGO_SAMPLES'];
    test(
      'real camera files read the same as a full read',
      skip: samples == null ? 'set CULLIMINGO_SAMPLES' : false,
      () async {
        const used = [
          'EXIF DateTimeOriginal',
          'Image DateTime',
          'Image Make',
          'Image Model',
          'Image Orientation',
          'EXIF ExifImageWidth',
          'EXIF ExifImageLength',
          'Image ImageWidth',
          'Image ImageLength',
          'EXIF ExposureBiasValue',
          'EXIF ExposureTime',
          'GPS GPSLatitude',
          'GPS GPSLatitudeRef',
          'GPS GPSLongitude',
          'GPS GPSLongitudeRef',
        ];
        final files = Directory(samples!)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => !f.path.endsWith('.md') && !f.path.endsWith('.json'))
            .toList();
        expect(files, isNotEmpty);
        for (final file in files) {
          final full = await readExifFromFile(file);
          final fast = await readExifTags(file);
          for (final key in used) {
            expect(
              fast[key]?.printable,
              full[key]?.printable,
              reason: '${file.path}: $key',
            );
          }
        }
      },
    );
  });
}
