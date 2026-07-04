import 'dart:io';
import 'dart:isolate';

import 'package:exif/exif.dart';

/// The richer EXIF fields the metadata inspector shows beyond what the drift
/// row already carries (camera/capture-time/dimensions). Read lazily for the
/// one focused photo, never during a scan — so the DB stays lean (Phase 8).
class ExifDetail {
  /// Creates an EXIF detail summary.
  const ExifDetail({
    this.lens,
    this.aperture,
    this.shutterSeconds,
    this.iso,
    this.focalLength,
    this.exposureBias,
    this.width,
    this.height,
  });

  /// Lens model (`EXIF LensModel`), when present.
  final String? lens;

  /// Aperture as an f-number (`EXIF FNumber`).
  final double? aperture;

  /// Shutter speed in seconds (`EXIF ExposureTime`).
  final double? shutterSeconds;

  /// ISO sensitivity (`EXIF ISOSpeedRatings`).
  final int? iso;

  /// Focal length in millimetres (`EXIF FocalLength`).
  final double? focalLength;

  /// Exposure compensation in EV (`EXIF ExposureBiasValue`).
  final double? exposureBias;

  /// Full-image pixel width, when present.
  final int? width;

  /// Full-image pixel height, when present.
  final int? height;

  /// True when no useful exposure/lens field was found.
  bool get isEmpty =>
      lens == null &&
      aperture == null &&
      shutterSeconds == null &&
      iso == null &&
      focalLength == null &&
      exposureBias == null &&
      width == null &&
      height == null;
}

/// Reads [ExifDetail] for the file at [path] in a background isolate (Rule 2:
/// never parse on the UI isolate). Returns an empty result on any error.
Future<ExifDetail> readExifDetail(String path) =>
    Isolate.run(() => _readExifDetail(path));

Future<ExifDetail> _readExifDetail(String path) async {
  Map<String, IfdTag> tags;
  try {
    tags = await readExifFromFile(File(path));
  } on Object {
    return const ExifDetail();
  }
  if (tags.isEmpty) return const ExifDetail();

  final iso = _num(tags, 'EXIF ISOSpeedRatings');
  return ExifDetail(
    lens: _text(tags, 'EXIF LensModel'),
    aperture: _num(tags, 'EXIF FNumber'),
    shutterSeconds: _num(tags, 'EXIF ExposureTime'),
    iso: iso?.round(),
    focalLength: _num(tags, 'EXIF FocalLength'),
    exposureBias: _num(tags, 'EXIF ExposureBiasValue'),
    width:
        _num(tags, 'EXIF ExifImageWidth')?.round() ??
        _num(tags, 'Image ImageWidth')?.round(),
    height:
        _num(tags, 'EXIF ExifImageLength')?.round() ??
        _num(tags, 'Image ImageLength')?.round(),
  );
}

String? _text(Map<String, IfdTag> tags, String key) {
  final s = tags[key]?.printable.trim();
  return (s == null || s.isEmpty) ? null : s;
}

/// Parses an EXIF numeric/ratio printable (`28/10`, `2.8`, `[400]`) to a
/// double; tolerant of brackets and comma-separated lists (takes the first).
double? _num(Map<String, IfdTag> tags, String key) {
  var s = tags[key]?.printable.trim();
  if (s == null || s.isEmpty) return null;
  s = s.replaceAll('[', '').replaceAll(']', '').trim();
  if (s.contains(',')) s = s.split(',').first.trim();
  final slash = s.indexOf('/');
  if (slash >= 0) {
    final n = double.tryParse(s.substring(0, slash).trim());
    final d = double.tryParse(s.substring(slash + 1).trim());
    if (n == null || d == null || d == 0) return null;
    return n / d;
  }
  return double.tryParse(s);
}
