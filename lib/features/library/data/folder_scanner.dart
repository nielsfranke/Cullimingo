import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:cullimingo/core/files/exif_reader.dart';
import 'package:cullimingo/core/files/supported_files.dart';
import 'package:cullimingo/core/raw/libraw_metadata.dart';
import 'package:cullimingo/core/raw/libraw_preview_extractor.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:flutter_libraw/flutter_libraw.dart';
import 'package:path/path.dart' as p;

/// One file found by the fast scan pass: just path + stat, no EXIF yet.
class ScannedFile {
  /// Creates a scanned-file record.
  const ScannedFile({
    required this.path,
    required this.mtime,
    required this.isRaw,
    this.sizeBytes = 0,
    this.companions = const [],
  });

  /// Absolute file path.
  final String path;

  /// File modification time.
  final DateTime mtime;

  /// File size in bytes (from the scan's stat — free).
  final int sizeBytes;

  /// Whether this is a RAW file (embedded-preview path).
  final bool isRaw;

  /// Sibling companion/sidecar files sharing this file's basename (`.xmp`,
  /// `.thm`, …), derived from the walk for free — the ingest copies these
  /// alongside, and the library uses `.xmp` to seed marks.
  final List<String> companions;

  /// Whether a sibling `.xmp` sidecar exists (lets the import skip the sidecar
  /// pass entirely when there are none).
  bool get hasSidecar =>
      companions.any((c) => p.extension(c).toLowerCase() == '.xmp');
}

/// EXIF read for one file, produced by the slower backfill pass.
class ScannedExif {
  /// Creates an EXIF record keyed by [path].
  const ScannedExif({
    required this.path,
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

  /// The file this EXIF belongs to.
  final String path;

  /// EXIF capture time, when available.
  final DateTime? capturedAt;

  /// Camera make/model, when available.
  final String? camera;

  /// Full-image pixel width, when available.
  final int? width;

  /// Full-image pixel height, when available.
  final int? height;

  /// GPS latitude in decimal degrees, when available.
  final double? latitude;

  /// GPS longitude in decimal degrees, when available.
  final double? longitude;

  /// EXIF orientation (1–8), when available.
  final int? orientation;

  /// Exposure compensation in EV, when available.
  final double? exposureBias;

  /// Shutter speed in seconds, when available.
  final double? exposureTime;
}

/// Fast pass: list [root] and `stat` each matching file — no EXIF decode, so it
/// returns quickly and the grid can populate near-instantly. Runs on a one-off
/// background isolate (§0.6, Phase 2 incremental scan).
///
/// [recursive] walks sub-folders (default on). [includeVideos] also matches
/// video files (for ingest; the cull grid keeps it off so it stays photo-only).
Future<List<ScannedFile>> scanFolderFast(
  String root, {
  bool recursive = true,
  bool includeVideos = false,
}) {
  return Isolate.run(
    () => _walk(root, recursive: recursive, includeVideos: includeVideos),
  );
}

List<ScannedFile> _walk(
  String root, {
  required bool recursive,
  required bool includeVideos,
}) {
  final dir = Directory(root);
  if (!dir.existsSync()) return const [];

  final entities = dir.listSync(recursive: recursive, followLinks: false);
  // Index sidecar files by their stem (dir + basename-no-ext) so each media
  // file can claim its companions with a single map lookup — no extra stat.
  final sidecarsByStem = <String, List<String>>{};
  for (final e in entities) {
    if (e is File && isSidecarPath(e.path)) {
      sidecarsByStem.putIfAbsent(_stem(e.path), () => []).add(e.path);
    }
  }

  bool matches(String path) =>
      isSupportedPhoto(path) || (includeVideos && isVideoPath(path));

  final out = <ScannedFile>[];
  for (final e in entities) {
    if (e is! File || !matches(e.path)) continue;
    final stat = e.statSync();
    out.add(
      ScannedFile(
        path: e.path,
        mtime: stat.modified,
        sizeBytes: stat.size,
        isRaw: isRawPath(e.path),
        companions: sidecarsByStem[_stem(e.path)] ?? const [],
      ),
    );
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

/// Lower-cased "stem" — directory + basename without extension — used to pair a
/// media file with its same-named sidecars across case-insensitive filesystems.
String _stem(String path) =>
    p.join(p.dirname(path), p.basenameWithoutExtension(path)).toLowerCase();

/// Backfill pass: read EXIF for [paths] on a background isolate. This is the
/// slow part (opening each file), kept off the import critical path. The RAW
/// libraw path (resolved on the caller's isolate, since it needs the packaged
/// bundle layout) lets the pass fall back to LibRaw for container formats whose
/// EXIF the `exif` package can't reach (Fuji `.RAF`).
Future<List<ScannedExif>> scanExif(List<String> paths) {
  final rawLibPath = LibRawPreviewExtractor.resolveLibraryPath();
  return Isolate.run(() => _readExif(paths, rawLibPath));
}

Future<List<ScannedExif>> _readExif(
  List<String> paths,
  String? rawLibPath,
) async {
  // Open libraw once for the whole batch (only if we actually hit a RAW that
  // the exif package couldn't read).
  FlutterLibRawBindings? lr;
  FlutterLibRawBindings? libraw() {
    if (rawLibPath == null) return null;
    try {
      return lr ??= FlutterLibRawBindings(DynamicLibrary.open(rawLibPath));
    } on Object {
      return null;
    }
  }

  final out = <ScannedExif>[];
  for (final path in paths) {
    var exif = await readPhotoExif(File(path));

    // Fuji `.RAF` (and similar wrapped containers) hide their EXIF from the
    // pure-Dart reader, so capture time / camera / bias / shutter come back
    // null. Their embedded preview JPEG *does* carry standard EXIF (incl. the
    // exposure bias that back-to-back bracket detection needs), so read that;
    // fall back to LibRaw's header fields if a preview has no EXIF. TIFF-based
    // raws (DNG/ARW/CR2/NEF) satisfy the direct read and skip all of this.
    if (isRawPath(path) &&
        (exif.capturedAt == null ||
            exif.exposureTime == null ||
            exif.exposureBias == null ||
            exif.camera == null)) {
      final bindings = libraw();
      if (bindings != null) {
        final previewBytes = extractRawThumbnail(bindings, path);
        final preview = previewBytes == null
            ? const PhotoExif()
            : await readPhotoExifBytes(previewBytes);
        final raw = readRawMetadata(bindings, path);
        exif = PhotoExif(
          capturedAt: exif.capturedAt ?? preview.capturedAt ?? raw.capturedAt,
          camera: exif.camera ?? preview.camera ?? raw.camera,
          width: exif.width,
          height: exif.height,
          latitude: exif.latitude,
          longitude: exif.longitude,
          orientation: exif.orientation,
          exposureBias: exif.exposureBias ?? preview.exposureBias,
          exposureTime:
              exif.exposureTime ?? preview.exposureTime ?? raw.exposureTime,
        );
      }
    }

    // Emit a record even when nothing was found, so the caller can write the
    // "scanned, no exposure tag" sentinel and never re-scan the file; skip only
    // videos (they carry no bracket signal and shouldn't get the sentinel).
    if (exif.isEmpty && isVideoPath(path)) continue;
    // (0,0) means "GPS block present but no fix" — treat as no position.
    final hasFix =
        exif.latitude != null &&
        exif.longitude != null &&
        !(exif.latitude == 0 && exif.longitude == 0);
    out.add(
      ScannedExif(
        path: path,
        capturedAt: exif.capturedAt,
        camera: exif.camera,
        width: exif.width,
        height: exif.height,
        latitude: hasFix ? exif.latitude : null,
        longitude: hasFix ? exif.longitude : null,
        orientation: exif.orientation,
        exposureBias: exif.exposureBias,
        exposureTime: exif.exposureTime,
      ),
    );
  }
  return out;
}
