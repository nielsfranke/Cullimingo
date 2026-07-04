import 'package:cullimingo/features/inspector/domain/exif_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatShutter', () {
    test('fast exposures as 1/x', () {
      expect(formatShutter(1 / 250), '1/250 s');
      expect(formatShutter(0.004), '1/250 s');
      expect(formatShutter(1 / 8000), '1/8000 s');
    });
    test('one second and longer kept as seconds', () {
      expect(formatShutter(1), '1 s');
      expect(formatShutter(2), '2 s');
      expect(formatShutter(1.3), '1.3 s');
    });
    test('non-positive is em dash', () {
      expect(formatShutter(0), '—');
    });
  });

  group('formatAperture', () {
    test('trims integral, keeps fractional', () {
      expect(formatAperture(2.8), 'f/2.8');
      expect(formatAperture(8), 'f/8');
      expect(formatAperture(1.4), 'f/1.4');
    });
  });

  test('formatFocalLength', () {
    expect(formatFocalLength(85), '85 mm');
    expect(formatFocalLength(16.5), '16.5 mm');
  });

  test('formatIso', () {
    expect(formatIso(400), 'ISO 400');
  });

  group('formatExposureBias', () {
    test('signed and zero', () {
      expect(formatExposureBias(0), '0 EV');
      expect(formatExposureBias(0.3), '+0.3 EV');
      expect(formatExposureBias(-1), '-1 EV');
    });
  });

  test('formatDimensions', () {
    expect(formatDimensions(6000, 4000), '6000 × 4000');
  });

  test('formatMegapixels', () {
    expect(formatMegapixels(6000, 4000), '24.0 MP');
    expect(formatMegapixels(7008, 4672), '32.7 MP');
  });

  test('formatOrientation', () {
    expect(formatOrientation(1), 'Normal');
    expect(formatOrientation(6), 'Rotated 90° CW');
    expect(formatOrientation(8), 'Rotated 90° CCW');
    expect(formatOrientation(3), 'Rotated 180°');
    expect(formatOrientation(99), isNull);
  });

  test('formatCrop', () {
    expect(formatCrop(0.9, 0.75, 0), '90% × 75%');
    expect(formatCrop(0.9, 0.75, 2.1), '90% × 75%, +2.1°');
    expect(formatCrop(0.9, 0.75, -1.5), '90% × 75%, −1.5°');
  });
}
