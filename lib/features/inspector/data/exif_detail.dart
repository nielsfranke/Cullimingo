import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:cullimingo/core/files/exif_values.dart';
import 'package:cullimingo/core/raw/libraw_preview_extractor.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:exif/exif.dart';
import 'package:flutter_libraw/flutter_libraw.dart';

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
Future<ExifDetail> readExifDetail(String path) {
  // Resolved on the caller's isolate — the packaged-bundle lookup depends on
  // the app bundle layout (same pattern as `scanExif`).
  final rawLibPath = LibRawPreviewExtractor.resolveLibraryPath();
  return Isolate.run(() => _readExifDetail(path, rawLibPath));
}

Future<ExifDetail> _readExifDetail(String path, String? rawLibPath) async {
  Map<String, IfdTag> tags;
  try {
    tags = await readExifFromFile(File(path));
  } on Object {
    tags = const {};
  }

  // Opaque RAW containers (Fuji `.RAF`) hide their EXIF from the pure-Dart
  // reader, but their embedded preview JPEG carries the standard tags — the
  // same LibRaw fallback the scanner uses (`folder_scanner.dart`). Gate on the
  // direct read coming back *empty*: TIFF-based raws (DNG/ARW/CR2/NEF) satisfy
  // it and never reach the blocking FFI call below.
  var fromPreview = false;
  if (tags.isEmpty && rawLibPath != null && isRawPath(path)) {
    tags = await _embeddedPreviewTags(rawLibPath, path);
    fromPreview = tags.isNotEmpty;
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
    // The embedded preview may be a downscaled render, so its pixel dimensions
    // aren't the full image's — leave them null and let the inspector fall
    // back to the drift row.
    width: fromPreview
        ? null
        : exifNum(tags, 'EXIF ExifImageWidth')?.round() ??
              exifNum(tags, 'Image ImageWidth')?.round(),
    height: fromPreview
        ? null
        : exifNum(tags, 'EXIF ExifImageLength')?.round() ??
              exifNum(tags, 'Image ImageLength')?.round(),
  );
}

/// Pulls the embedded preview JPEG out of the RAW at [path] via LibRaw and
/// reads its EXIF tags. Returns an empty map on any failure.
Future<Map<String, IfdTag>> _embeddedPreviewTags(
  String libPath,
  String path,
) async {
  try {
    final bindings = FlutterLibRawBindings(DynamicLibrary.open(libPath));
    final preview = extractRawThumbnail(bindings, path);
    if (preview == null) return const {};
    return await readExifFromBytes(preview);
  } on Object {
    return const {};
  }
}
