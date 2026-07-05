import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/files/supported_files.dart';
import 'package:cullimingo/features/library/data/folder_scanner.dart';
import 'package:cullimingo/features/metadata/data/metadata_repository.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

/// Bridges folder scanning and the drift read model. The import runs in two
/// passes (Phase 2): a fast walk that fills the grid right away, then an EXIF
/// backfill that adds capture time / camera in the background.
class LibraryRepository {
  /// Creates a repository over [db]. When [metadata] is given, existing XMP
  /// sidecars seed the read model on import.
  const LibraryRepository(this.db, {this.metadata});

  /// The read-model database.
  final AppDatabase db;

  /// Optional metadata repository for sidecar sync.
  final MetadataRepository? metadata;

  /// Finds the import for [root] if it was opened before, else creates an empty
  /// one. Returns `(importId, isNew)`. Reusing the existing import is what lets
  /// a previously-opened folder open again (its photos already exist; a fresh
  /// import would insertOrIgnore nothing and show an empty grid).
  Future<(int, bool)> findOrCreateImport(String root) async {
    final existing =
        await (db.select(db.imports)
              ..where((t) => t.sourcePath.equals(root))
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return (existing.id, false);
    final id = await db.createImport(
      sourcePath: root,
      cardLabel: p.basename(root),
    );
    return (id, true);
  }

  /// Fills [importId]: fast pass inserts rows so the grid appears at once, then
  /// an EXIF backfill updates capture time/camera, then sidecars are applied.
  /// [recursive] controls whether sub-folders are included (the cull grid is
  /// always photo-only — videos are never scanned into the read model).
  Future<void> populateImport(
    int importId,
    String root, {
    bool recursive = true,
  }) async {
    // Include videos so clips show in the grid (with a poster frame / placeholder
    // and external-player open); the grid is otherwise photo-centric.
    final files = await scanFolderFast(
      root,
      recursive: recursive,
      includeVideos: true,
    );
    await db.claimPhotos(
      importId,
      files.map(
        (f) => PhotosCompanion.insert(
          importId: Value(importId),
          path: f.path,
          mtime: f.mtime,
          isRaw: Value(f.isRaw),
        ),
      ),
    );
    await _backfillExif(files.map((f) => f.path).toList());
    // Run the metadata pass when the scan saw either a `.xmp` sidecar (RAW) or
    // a file that can carry XMP embedded inside it (JPEG/HEIC/TIFF — how C1/LR
    // store marks on export). A fresh RAW card has neither, so this still skips
    // the per-file read that would otherwise stall the UI on a plain ingest.
    if (files.any((f) => f.hasSidecar || carriesEmbeddedXmp(f.path))) {
      await metadata?.applySidecarsForImport(importId);
    }
  }

  /// Re-scans [root] for an already-open [importId]: inserts files that
  /// appeared on disk, removes rows whose file is gone, and reads marks for the
  /// new files only (existing photos keep their current DB marks, so a local
  /// edit isn't clobbered). Returns `(added, removed)` counts for the UI.
  Future<(int added, int removed)> refreshImport(
    int importId,
    String root, {
    bool recursive = true,
  }) async {
    final files = await scanFolderFast(
      root,
      recursive: recursive,
      includeVideos: true,
    );
    final diskPaths = files.map((f) => f.path).toSet();
    final existing = await (db.select(
      db.photos,
    )..where((t) => t.importId.equals(importId))).get();
    final existingPaths = existing.map((row) => row.path).toSet();

    // Files this import doesn't already own — new to disk *or* owned by another
    // import (e.g. a subfolder opened separately). Both get claimed to this
    // import so a reopened/parent folder shows its full contents.
    final newFiles = files
        .where((f) => !existingPaths.contains(f.path))
        .toList();
    final removedPaths = existingPaths.difference(diskPaths).toList();

    if (newFiles.isNotEmpty) {
      await db.claimPhotos(
        importId,
        newFiles.map(
          (f) => PhotosCompanion.insert(
            importId: Value(importId),
            path: f.path,
            mtime: f.mtime,
            isRaw: Value(f.isRaw),
          ),
        ),
      );
      await _backfillExif(newFiles.map((f) => f.path).toList());
      await metadata?.applyMarksForPaths(
        importId,
        newFiles.map((f) => f.path).toSet(),
      );
    }
    if (removedPaths.isNotEmpty) {
      await db.deletePhotosByPaths(importId, removedPaths);
    }
    // Backfill exposure fields for rows imported before the v8 schema. Runs
    // once per legacy row (sentinel-guarded), so a reopened shoot picks up
    // bracket detection without a manual re-import.
    await _backfillExposure(existing);
    return (newFiles.length, removedPaths.length);
  }

  /// Convenience that finds/creates and fully populates an import (tests).
  Future<int> importFolder(String root, {bool recursive = true}) async {
    final (importId, _) = await findOrCreateImport(root);
    await populateImport(importId, root, recursive: recursive);
    return importId;
  }

  Future<void> _backfillExif(List<String> paths) async {
    final exif = await scanExif(paths);
    if (exif.isEmpty) return;
    await db.batch((b) {
      for (final e in exif) {
        b.update(
          db.photos,
          PhotosCompanion(
            capturedAt: Value(e.capturedAt),
            camera: Value(e.camera),
            width: Value(e.width),
            height: Value(e.height),
            latitude: Value(e.latitude),
            longitude: Value(e.longitude),
            orientation: Value(e.orientation ?? 1),
            exposureBias: Value(e.exposureBias),
            // 0.0 sentinel = "scanned, no shutter tag" so the legacy backfill
            // (which keys off NULL) never re-scans this row again.
            exposureTime: Value(e.exposureTime ?? 0),
          ),
          where: (t) => t.path.equals(e.path),
        );
      }
    });
  }

  /// One-time backfill of the exposure columns for photos imported before the
  /// v8 schema (their [Photo.exposureTime] is still NULL). Touches *only* the
  /// two exposure columns so it never clobbers capture time / camera / GPS that
  /// a later manual edit or sidecar sync may have refined. Runs at most once
  /// per row thanks to the 0.0 sentinel written below.
  Future<void> _backfillExposure(List<Photo> existing) async {
    final stale = existing
        .where((row) => row.exposureTime == null && !isVideoPath(row.path))
        .map((row) => row.path)
        .toList();
    if (stale.isEmpty) return;
    final exif = await scanExif(stale);
    if (exif.isEmpty) return;
    await db.batch((b) {
      for (final e in exif) {
        b.update(
          db.photos,
          PhotosCompanion(
            exposureBias: Value(e.exposureBias),
            exposureTime: Value(e.exposureTime ?? 0),
          ),
          where: (t) => t.path.equals(e.path),
        );
      }
    });
  }

  /// Reactive stream of the photos in [importId], ordered for the grid.
  Stream<List<Photo>> watchImport(int importId) =>
      db.watchPhotosForImport(importId);
}
