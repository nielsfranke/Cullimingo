import 'dart:io';
import 'dart:typed_data';

import 'package:cullimingo/core/files/exif_values.dart';
import 'package:cullimingo/core/files/image_dimensions.dart';
import 'package:exif/exif.dart';

/// The handful of EXIF fields the cull workflow needs: capture time (drives the
/// grid sort and Phase 3 rename tokens), camera, pixel dimensions, and the GPS
/// position (drives reverse geocoding for the IPTC location fields).
class PhotoExif {
  /// Creates an EXIF summary.
  const PhotoExif({
    this.capturedAt,
    this.camera,
    this.width,
    this.height,
    this.latitude,
    this.longitude,
    this.orientation,
    this.exposureBias,
    this.exposureTime,
  });

  /// EXIF DateTimeOriginal, when present.
  final DateTime? capturedAt;

  /// "Make Model", deduplicated (e.g. `Sony ILCE-7M4`).
  final String? camera;

  /// EXIF orientation (1–8), when present; null if the file has no tag.
  final int? orientation;

  /// Full-image pixel width, when present.
  final int? width;

  /// Full-image pixel height, when present.
  final int? height;

  /// GPS latitude in decimal degrees (south negative), when present.
  final double? latitude;

  /// GPS longitude in decimal degrees (west negative), when present.
  final double? longitude;

  /// Exposure compensation in EV (`EXIF ExposureBiasValue`), when present.
  /// Drives exposure-bracket grouping.
  final double? exposureBias;

  /// Shutter speed in seconds (`EXIF ExposureTime`), when present. Bracket
  /// grouping uses it to allow the long gaps long exposures cause.
  final double? exposureTime;

  /// True when nothing useful was found.
  bool get isEmpty =>
      capturedAt == null &&
      camera == null &&
      width == null &&
      height == null &&
      latitude == null &&
      longitude == null &&
      orientation == null &&
      exposureBias == null &&
      exposureTime == null;
}

/// Reads [PhotoExif] from [file] using the streaming `exif` reader (no full
/// decode, works on JPEG and TIFF-based RAW). Returns an empty result on any
/// error, so a missing/odd header never breaks a scan.
Future<PhotoExif> readPhotoExif(File file) async {
  Map<String, IfdTag> tags;
  try {
    tags = await readExifFromFile(file);
  } on Object {
    // Fall through with no tags so the header-based dimension pass below still
    // runs (HEIF/AVIF have no EXIF the reader understands, but they do carry an
    // `ispe` box).
    tags = const {};
  }
  var width = _int(tags['EXIF ExifImageWidth'] ?? tags['Image ImageWidth']);
  var height = _int(tags['EXIF ExifImageLength'] ?? tags['Image ImageLength']);
  // Fall back to the image's own header (JPEG frame / PNG IHDR / HEIF `ispe`)
  // when EXIF has no pixel-dimension tags — many processed/exported JPEGs drop
  // them and HEIF/AVIF never carry them, but the file still knows its true size,
  // so the inspector need not show "—".
  if (width == null || height == null) {
    final header = await readImageDimensions(file);
    if (header != null) {
      width ??= header.width;
      height ??= header.height;
    }
  }
  if (tags.isEmpty && width == null && height == null) return const PhotoExif();

  return _fromTags(tags, width: width, height: height);
}

/// Reads [PhotoExif] from in-memory [bytes] — used to pull EXIF out of a RAW's
/// embedded preview JPEG (extracted by LibRaw) for container formats like Fuji
/// `.RAF` whose EXIF the file-based reader can't reach. Pixel dimensions are
/// deliberately *not* returned: the preview is a downscaled render, so its size
/// isn't the full image's. Returns an empty result on any error.
Future<PhotoExif> readPhotoExifBytes(Uint8List bytes) async {
  Map<String, IfdTag> tags;
  try {
    tags = await readExifFromBytes(bytes);
  } on Object {
    return const PhotoExif();
  }
  if (tags.isEmpty) return const PhotoExif();
  return _fromTags(tags);
}

PhotoExif _fromTags(Map<String, IfdTag> tags, {int? width, int? height}) {
  return PhotoExif(
    capturedAt: _parseExifDate(
      tags['EXIF DateTimeOriginal']?.printable ??
          tags['Image DateTime']?.printable,
    ),
    camera: _camera(tags),
    width: width,
    height: height,
    latitude: _gpsCoordinate(
      tags['GPS GPSLatitude'],
      tags['GPS GPSLatitudeRef'],
      negativeRef: 'S',
      limit: 90,
    ),
    longitude: _gpsCoordinate(
      tags['GPS GPSLongitude'],
      tags['GPS GPSLongitudeRef'],
      negativeRef: 'W',
      limit: 180,
    ),
    orientation: _orientation(tags),
    exposureBias: exifNum(tags, 'EXIF ExposureBiasValue'),
    exposureTime: exifNum(tags, 'EXIF ExposureTime'),
  );
}

/// Reads the EXIF `Image Orientation` value (1–8) numerically — the tag's
/// `printable` is a human string ("Rotated 90 CW"), so we take the raw value.
/// Null when absent or out of the valid 1–8 range.
int? _orientation(Map<String, IfdTag> tags) {
  final parts = tags['Image Orientation']?.values.toList();
  if (parts == null || parts.isEmpty) return null;
  final first = parts.first;
  final n = first is int ? first : int.tryParse('$first');
  if (n == null || n < 1 || n > 8) return null;
  return n;
}

/// Converts an EXIF GPS coordinate — a deg/min/sec rational triple plus a
/// hemisphere ref — to signed decimal degrees. Null for anything malformed or
/// out of range, so junk GPS blocks never produce a bogus position.
double? _gpsCoordinate(
  IfdTag? value,
  IfdTag? ref, {
  required String negativeRef,
  required double limit,
}) {
  if (value == null) return null;
  final parts = value.values.toList();
  if (parts.isEmpty) return null;
  double? part(int i) {
    if (i >= parts.length) return 0;
    final v = parts[i];
    if (v is Ratio) {
      return v.denominator == 0 ? null : v.numerator / v.denominator;
    }
    if (v is num) return v.toDouble();
    return null;
  }

  final deg = part(0);
  final min = part(1);
  final sec = part(2);
  if (deg == null || min == null || sec == null) return null;
  var out = deg + min / 60 + sec / 3600;
  final hemisphere = ref?.printable.trim().toUpperCase() ?? '';
  if (hemisphere.startsWith(negativeRef)) out = -out;
  if (out.abs() > limit) return null;
  // (0,0) is the classic "GPS block present but never got a fix" value; a
  // single zero axis is judged by the caller pairing lat+lon.
  return out;
}

/// Parses the EXIF `YYYY:MM:DD HH:MM:SS` timestamp format.
DateTime? _parseExifDate(String? raw) {
  if (raw == null) return null;
  final m = RegExp(
    r'^(\d{4}):(\d{2}):(\d{2})\s+(\d{2}):(\d{2}):(\d{2})',
  ).firstMatch(raw.trim());
  if (m == null) return null;
  final month = int.parse(m[2]!);
  final day = int.parse(m[3]!);
  // The all-zero placeholder ("0000:00:00 00:00:00", camera clock never set)
  // matches the regex, and DateTime() would happily normalise month/day 0 to
  // a year ~-1 date — sorting the photo to the top of the grid and feeding
  // nonsense into rename tokens. Treat any impossible date as "unknown".
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return DateTime(
    int.parse(m[1]!),
    month,
    day,
    int.parse(m[4]!),
    int.parse(m[5]!),
    int.parse(m[6]!),
  );
}

String? _camera(Map<String, IfdTag> tags) {
  final make = tags['Image Make']?.printable.trim();
  final model = tags['Image Model']?.printable.trim();
  if (model == null || model.isEmpty) {
    return (make == null || make.isEmpty) ? null : make;
  }
  if (make == null || make.isEmpty || model.startsWith(make)) return model;
  return '$make $model';
}

int? _int(IfdTag? tag) => int.tryParse(tag?.printable.trim() ?? '');
