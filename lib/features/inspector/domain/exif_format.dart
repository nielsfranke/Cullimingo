/// Pure, presentation-only formatters for the metadata inspector (Phase 8).
///
/// Each takes already-parsed numbers (no `exif` types) so the heavy reading
/// stays in the data layer and these stay trivially unit-testable. Callers
/// guard for null/absent values; these assume a sensible, present input.
library;

/// Trims a double to a compact human string: drops a trailing `.0`, otherwise
/// keeps up to [maxDecimals] fractional digits with trailing zeros removed.
String _trim(double value, {int maxDecimals = 1}) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  var s = value.toStringAsFixed(maxDecimals);
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
  return s;
}

/// Shutter speed from a seconds value: `1/250 s` for fast exposures, `2 s` /
/// `1.3 s` for long ones.
String formatShutter(double seconds) {
  if (seconds <= 0) return '—';
  if (seconds >= 1) return '${_trim(seconds)} s';
  final denom = (1 / seconds).round();
  return '1/$denom s';
}

/// Aperture from an f-number: `f/2.8`, `f/8`.
String formatAperture(double fNumber) => 'f/${_trim(fNumber)}';

/// Focal length in millimetres: `85 mm`, `16.5 mm`.
String formatFocalLength(double mm) => '${_trim(mm)} mm';

/// ISO sensitivity: `ISO 400`.
String formatIso(int iso) => 'ISO $iso';

/// Exposure compensation in EV, sign-prefixed: `+0.3 EV`, `0 EV`, `-1 EV`.
String formatExposureBias(double ev) {
  if (ev == 0) return '0 EV';
  final sign = ev > 0 ? '+' : '-';
  return '$sign${_trim(ev.abs())} EV';
}

/// Pixel dimensions: `6000 × 4000`.
String formatDimensions(int width, int height) => '$width × $height';

/// Megapixel count from dimensions: `24.0 MP`.
String formatMegapixels(int width, int height) {
  final mp = width * height / 1e6;
  return '${mp.toStringAsFixed(1)} MP';
}

/// Human label for a Lightroom/Camera-Raw crop: the kept area as percentages
/// plus the straighten angle when non-zero, e.g. `90% × 75%` or
/// `90% × 75%, +2.1°`.
String formatCrop(double width, double height, double angle) {
  final pct = '${(width * 100).round()}% × ${(height * 100).round()}%';
  if (angle.abs() < 0.05) return pct;
  final sign = angle > 0 ? '+' : '−';
  return '$pct, $sign${angle.abs().toStringAsFixed(1)}°';
}

/// Human label for an EXIF orientation (1–8): `Normal`, `Rotated 90° CW`,
/// mirror variants, etc. Null only for out-of-range input (row shows `—`).
String? formatOrientation(int orientation) => switch (orientation) {
  1 => 'Normal',
  2 => 'Mirrored',
  3 => 'Rotated 180°',
  4 => 'Mirrored, 180°',
  5 => 'Mirrored, 90° CCW',
  6 => 'Rotated 90° CW',
  7 => 'Mirrored, 90° CW',
  8 => 'Rotated 90° CCW',
  _ => null,
};
