import 'dart:io';
import 'dart:isolate';

import 'package:cullimingo/core/files/exif_values.dart';
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

  final iso = exifNum(tags, 'EXIF ISOSpeedRatings');
  return ExifDetail(
    lens: exifText(tags, 'EXIF LensModel'),
    aperture: exifNum(tags, 'EXIF FNumber'),
    shutterSeconds: exifNum(tags, 'EXIF ExposureTime'),
    iso: iso?.round(),
    focalLength: exifNum(tags, 'EXIF FocalLength'),
    exposureBias: exifNum(tags, 'EXIF ExposureBiasValue'),
    width:
        exifNum(tags, 'EXIF ExifImageWidth')?.round() ??
        exifNum(tags, 'Image ImageWidth')?.round(),
    height:
        exifNum(tags, 'EXIF ExifImageLength')?.round() ??
        exifNum(tags, 'Image ImageLength')?.round(),
  );
}
