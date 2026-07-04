import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:path/path.dart' as p;

/// Non-RAW bitmap formats the `image` package can decode for previews.
const Set<String> kBitmapExtensions = {
  'jpg',
  'jpeg',
  'png',
  'tif',
  'tiff',
  'webp',
  'bmp',
};

/// HEIF/AVIF photo containers (iPhone, Sony `.hif`, …). Decoded for previews by
/// libvips (the bundled vips-heif module) via `Vips.thumbnail`; the grid falls
/// back to a placeholder only when libvips/libheif can't decode a given file.
const Set<String> kHeifExtensions = {'heic', 'heif', 'hif', 'avif'};

/// Video / cinema container formats cameras write. Not shown in the cull grid,
/// but the ingest copies them so footage on the card isn't lost.
const Set<String> kVideoExtensions = {
  // Common containers
  'mov', 'mp4', 'm4v', 'avi', 'mts', 'm2ts', 'm2t', 'm2v', 'ts',
  '3gp', '3g2', 'mpg', 'mpeg', 'mpe', 'mkv', 'webm', 'wmv', 'flv',
  'f4v', 'vob', 'ogv', 'mod', 'tod', 'dv', 'mqv', 'mxf',
  // Action / 360 cams
  'lrv', 'insv',
  // Cinema RAW
  'braw', 'r3d', 'crm', 'cine',
};

/// Companion/sidecar files that belong to a media file (same basename): editor
/// metadata (`.xmp`/`.dop`/`.pp3`/`.on1`), camera thumbnails (`.thm`) and Apple
/// edit instructions (`.aae`). The ingest carries them along, renamed to match.
const Set<String> kSidecarExtensions = {
  'xmp',
  'thm',
  'aae',
  'dop',
  'pp3',
  'on1',
  'exv',
};

String _ext(String path) =>
    p.extension(path).replaceFirst('.', '').toLowerCase();

/// Whether [path] is a photo Cullimingo can ingest (RAW, bitmap, or HEIF).
bool isSupportedPhoto(String path) {
  final ext = _ext(path);
  return kRawExtensions.contains(ext) ||
      kBitmapExtensions.contains(ext) ||
      kHeifExtensions.contains(ext);
}

/// Whether [path] is a plain bitmap Flutter's engine can render directly
/// (JPEG/PNG/…) — i.e. safe to hand to `Image.memory` un-transcoded.
bool isBitmapPath(String path) => kBitmapExtensions.contains(_ext(path));

/// Whether [path] is a JPEG — the one format whose embedded EXIF Orientation
/// we patch losslessly on rotate (RAW containers aren't writable; other bitmaps
/// use the sidecar only).
bool isJpegPath(String path) {
  final ext = _ext(path);
  return ext == 'jpg' || ext == 'jpeg';
}

/// Whether [path] is a non-RAW image that carries metadata embedded *inside*
/// the file (JPEG/TIFF/HEIC… — how Capture One / Lightroom store rating, label
/// and keywords on export). RAW uses `.xmp` sidecars by convention and is
/// excluded so we never read a huge RAW just to look for a packet.
bool carriesEmbeddedXmp(String path) {
  final ext = _ext(path);
  return kBitmapExtensions.contains(ext) || kHeifExtensions.contains(ext);
}

/// Whether [path] is a video file.
bool isVideoPath(String path) => kVideoExtensions.contains(_ext(path));

/// Whether [path] is media the ingest should copy (photo or video).
bool isSupportedMedia(String path) =>
    isSupportedPhoto(path) || isVideoPath(path);

/// Whether [path] is a companion/sidecar metadata file.
bool isSidecarPath(String path) => kSidecarExtensions.contains(_ext(path));
