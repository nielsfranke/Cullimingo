import 'dart:io';

import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:path/path.dart' as p;

/// Shared-stem sidecar for [photoPath]: same folder, basename + `.xmp` — the
/// Lightroom/Bridge/Capture One convention for proprietary RAW
/// (`DSC0001.ARW` → `DSC0001.xmp`).
///
/// Lives in core (not the metadata feature) because copy/move/rename/delete
/// flows across features pair the sidecar with its photo — only the XMP
/// *content* handling belongs to metadata.
String stemSidecarPath(String photoPath) => p.setExtension(photoPath, '.xmp');

/// Per-file sidecar for [photoPath]: the full filename + `.xmp`
/// (`DSC0001.JPG` → `DSC0001.JPG.xmp`, the darktable convention). Used for the
/// non-RAW half of a RAW+JPEG pair, so the JPEG keeps its own marks instead of
/// sharing — and overwriting — the RAW's `DSC0001.xmp`.
String fileSidecarPath(String photoPath) => '$photoPath.xmp';

/// Where [sidecar] (a companion of [photoPath]) goes when the photo moves to
/// [newPhotoPath]: a per-file sidecar (`DSC1.JPG.xmp`) follows the full new
/// filename, anything else (`DSC1.xmp`, `DSC1.thm`) swaps in its own
/// extension on the new stem. Works on relative paths too.
String followSidecarPath(
  String sidecar,
  String photoPath,
  String newPhotoPath,
) {
  final isFileForm =
      p.basename(sidecar).toLowerCase() ==
      p.basename(fileSidecarPath(photoPath)).toLowerCase();
  return isFileForm
      ? fileSidecarPath(newPhotoPath)
      : p.setExtension(newPhotoPath, p.extension(sidecar));
}

/// Which sidecar [photoPath] uses, given what sits next to it on disk:
///
/// * RAW → always the shared-stem sidecar (LR/C1 round-trip).
/// * Non-RAW with a RAW sibling of the same stem → its own per-file sidecar.
/// * Non-RAW alone → the shared-stem sidecar, unless only a per-file one
///   exists (its RAW was deleted after marking) — then that one, so the marks
///   aren't orphaned.
String chooseSidecarPath(
  String photoPath, {
  required bool hasRawSibling,
  required bool hasFileSidecar,
  required bool hasStemSidecar,
}) {
  if (isRawPath(photoPath)) return stemSidecarPath(photoPath);
  if (hasRawSibling || (hasFileSidecar && !hasStemSidecar)) {
    return fileSidecarPath(photoPath);
  }
  return stemSidecarPath(photoPath);
}

/// Resolves sidecar paths against the filesystem ([chooseSidecarPath]),
/// listing each folder at most once — reuse one instance across a batch so a
/// thousand-photo sync costs one listing per folder, not one per photo.
///
/// RAW paths never touch the disk. Callers run off the UI isolate (the
/// listing is async I/O).
class SidecarResolver {
  final _dirs = <String, Future<_DirIndex>>{};

  /// The sidecar path for [photoPath].
  Future<String> resolve(String photoPath) async {
    if (isRawPath(photoPath)) return stemSidecarPath(photoPath);
    final index = await _dirs.putIfAbsent(
      p.dirname(photoPath),
      () => _DirIndex.list(p.dirname(photoPath)),
    );
    final stem = p.basenameWithoutExtension(photoPath).toLowerCase();
    final fileSidecar = p.basename(fileSidecarPath(photoPath)).toLowerCase();
    return chooseSidecarPath(
      photoPath,
      hasRawSibling: index.rawStems.contains(stem),
      hasFileSidecar: index.names.contains(fileSidecar),
      hasStemSidecar: index.names.contains('$stem.xmp'),
    );
  }
}

/// Lower-cased file names and RAW stems of one folder.
class _DirIndex {
  _DirIndex(this.names, this.rawStems);

  static Future<_DirIndex> list(String dir) async {
    final names = <String>{};
    final rawStems = <String>{};
    try {
      await for (final e in Directory(dir).list(followLinks: false)) {
        final name = p.basename(e.path).toLowerCase();
        names.add(name);
        if (isRawPath(name)) rawStems.add(p.basenameWithoutExtension(name));
      }
    } on FileSystemException {
      // Unreadable/vanished folder: fall back to the plain stem convention.
    }
    return _DirIndex(names, rawStems);
  }

  final Set<String> names;
  final Set<String> rawStems;
}

/// One-off [SidecarResolver.resolve] for a single photo.
Future<String> resolveSidecarPath(String photoPath) =>
    SidecarResolver().resolve(photoPath);
