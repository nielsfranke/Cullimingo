import 'dart:io';

import 'package:cullimingo/core/files/exif_reader.dart';
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

  File writeJpegWithExif() {
    final image = img.Image(width: 24, height: 16);
    image.exif.imageIfd['Make'] = 'Sony';
    image.exif.imageIfd['Model'] = 'ILCE-7M4';
    image.exif.exifIfd['DateTimeOriginal'] = '2026:06:01 10:30:45';
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
}
