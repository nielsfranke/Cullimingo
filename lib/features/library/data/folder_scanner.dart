import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:cullimingo/core/files/exif_reader.dart';
import 'package:cullimingo/core/files/supported_files.dart';
import 'package:cullimingo/core/logging/app_logger.dart';
import 'package:cullimingo/core/raw/libraw_metadata.dart';
import 'package:cullimingo/core/raw/libraw_preview_extractor.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:flutter_libraw/flutter_libraw.dart';
import 'package:path/path.dart' as p;

/// How long a single filesystem step (advancing a directory listing, or one
/// file's `stat`/EXIF read) may stall before it's treated as a failing device
/// and skipped, so one bad file/sector on a flaky SD card can't hang the whole
/// scan forever. Generous: a healthy read returns in micro/milliseconds, so
/// this only ever fires on genuinely stuck hardware.
const _scanStallTimeout = Duration(seconds: 8);

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

Future<List<ScannedFile>> _walk(
  String root, {
  required bool recursive,
  required bool includeVideos,
}) async {
  final dir = Directory(root);
  if (!dir.existsSync()) return const [];

  // Listed asynchronously (not `listSync`) so a stalled step (a failing SD
  // card/reader can block the underlying syscall for a long time) only stalls
  // this await, not the whole isolate — letting the timeout below actually
  // fire and hand back whatever was found before the device seized up.
  //
  // `handleError` skips individual unreadable entries instead of aborting the
  // whole walk: a recursive `list` THROWS a FileSystemException (e.g. a
  // macOS-protected `.Trashes` on a camera card → "Operation not permitted")
  // and, unguarded, that error escapes the isolate and the caller — hanging the
  // "Scanning…" spinner forever. Swallowing it lets the walk finish over the
  // real media files.
  final entities = <FileSystemEntity>[];
  try {
    await dir
        .list(recursive: recursive, followLinks: false)
        .handleError(
          (Object e) =>
              appTalker.warning('Scan: skipping unreadable entry: $e'),
          test: (e) => e is FileSystemException,
        )
        .timeout(_scanStallTimeout)
        .forEach(entities.add);
  } on TimeoutException {
    appTalker.warning(
      'Folder scan of $root stalled (device unresponsive); continuing with '
      '${entities.length} entries found so far',
    );
  }

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
    FileStat stat;
    try {
      // Async stat (not statSync) so a stalled read on a failing device only
      // blocks this await, letting the timeout below actually fire.
      // ignore: avoid_slow_async_io
      stat = await e.stat().timeout(_scanStallTimeout);
    } on TimeoutException {
      appTalker.warning(
        'Skipping ${e.path}: stat() stalled (device unresponsive)',
      );
      continue;
    }
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
    var exif = await readPhotoExif(File(path)).timeout(
      _scanStallTimeout,
      onTimeout: () {
        appTalker.warning(
          'EXIF read for $path stalled (device unresponsive); skipping',
        );
        return const PhotoExif();
      },
    );

    // Fuji `.RAF` (and similar wrapped containers) hide their EXIF from the
    // pure-Dart reader, so capture time / camera / bias / shutter come back
    // null. Their embedded preview JPEG *does* carry standard EXIF (incl. the
    // exposure bias that back-to-back bracket detection needs), so read that;
    // fall back to LibRaw's header fields if a preview has no EXIF.
    //
    // Gate on capturedAt being null — i.e. the direct read got *nothing*, the
    // signature of an opaque container like RAF. TIFF-based raws (DNG/ARW/CR2/
    // NEF) satisfy the direct read, so they skip this entirely. That matters
    // for safety, not just speed: the LibRaw calls below are blocking FFI with
    // no timeout, and DJI DNGs (which often lack an ExposureBias tag) could
    // otherwise wedge LibRaw and hang the whole scan.
    if (isRawPath(path) && exif.capturedAt == null) {
      final bindings = libraw();
      if (bindings != null) {
        final previewBytes = extractRawThumbnail(bindings, path);
        final preview = previewBytes == null
            ? const PhotoExif()
            : await readPhotoExifBytes(
                previewBytes,
              ).timeout(_scanStallTimeout, onTimeout: () => const PhotoExif());
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
