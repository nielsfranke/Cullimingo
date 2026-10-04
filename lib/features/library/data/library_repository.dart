import 'dart:io';

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
  ///
  /// [scanner] lists a folder (default [scanFolder]); tests inject one that
  /// reports unreadable entries.
  const LibraryRepository(
    AppDatabase db, {
    this.metadata,
    FolderScanner scanner = scanFolder,
  }) : _db = db,
       _scan = scanner;

  // The read-model database. Private: queries stay behind named AppDatabase
  // methods so the schema never becomes this repository's public API.
  final AppDatabase _db;

  /// Optional metadata repository for sidecar sync.
  final MetadataRepository? metadata;

  final FolderScanner _scan;

  /// Finds the import for [root] if it was opened before, else creates an empty
  /// one. Returns `(importId, isNew)`. Reusing the existing import is what lets
  /// a previously-opened folder open again (its photos already exist; a fresh
  /// import would insertOrIgnore nothing and show an empty grid).
  Future<(int, bool)> findOrCreateImport(String root) async {
    final existing =
        await (_db.select(_db.imports)
              ..where((t) => t.sourcePath.equals(root))
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return (existing.id, false);
    final id = await _db.createImport(
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
    final files = (await _scan(
      root,
      recursive: recursive,
      includeVideos: true,
    )).files;
    await _db.claimPhotos(
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
  /// appeared on disk, removes rows whose file is gone, updates rows whose
  /// file changed in place (new mtime — the row keeps its marks but follows
  /// the file), and reads marks for the new files only (existing photos keep
  /// their current DB marks, so a local edit isn't clobbered). Returns counts
  /// for the UI plus the changed paths, so the caller can drop their stale
  /// RAM previews (the disk cache self-invalidates via the mtime in its key;
  /// the RAM tier is keyed by path alone).
  ///
  /// When the folder looks unavailable — [root] is gone, or it lists empty
  /// while the import still has photos — nothing is touched and `unavailable`
  /// is set: an unplugged card or drive (or a Linux mount point left empty)
  /// must not read as "every photo was deleted", which used to drop every row
  /// and the database-only state with it (rotation, stacks, selections).
  ///
  /// Likewise, when the scan couldn't read part of the folder (a permission
  /// error on a sub-folder, a stalled card reader), the listing is incomplete:
  /// new and changed files are still picked up, but nothing is removed, and
  /// `unreadable` counts what the scan skipped.
  Future<
    ({
      int added,
      int removed,
      List<String> changedPaths,
      bool unavailable,
      int unreadable,
    })
  >
  refreshImport(
    int importId,
    String root, {
    bool recursive = true,
  }) async {
    const unavailable = (
      added: 0,
      removed: 0,
      changedPaths: <String>[],
      unavailable: true,
      unreadable: 0,
    );
    // Async on purpose: the root may sit on slow removable media.
    // ignore: avoid_slow_async_io
    if (!await Directory(root).exists()) return unavailable;
    final scan = await _scan(
      root,
      recursive: recursive,
      includeVideos: true,
    );
    final files = scan.files;
    final diskPaths = files.map((f) => f.path).toSet();
    final existing = await _db.photosForImport(importId);
    if (files.isEmpty && existing.isNotEmpty) return unavailable;
    final existingPaths = existing.map((row) => row.path).toSet();
    final rowByPath = {for (final row in existing) row.path: row};

    // Files this import doesn't already own — new to disk *or* owned by another
    // import (e.g. a subfolder opened separately). Both get claimed to this
    // import so a reopened/parent folder shows its full contents.
    final newFiles = files
        .where((f) => !existingPaths.contains(f.path))
        .toList();
    // A file missing from an incomplete listing may just sit in the part the
    // scan couldn't read — never treat that as deleted.
    final removedPaths = scan.complete
        ? existingPaths.difference(diskPaths).toList()
        : const <String>[];

    if (newFiles.isNotEmpty) {
      await _db.claimPhotos(
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
      await _db.deletePhotosByPaths(importId, removedPaths);
    }

    // Files overwritten/edited in place: the on-disk mtime moved past the
    // stored row (compared at whole seconds — drift persists seconds). The
    // marks stay; mtime and EXIF-derived columns follow the new content.
    int secs(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;
    final changedFiles = [
      for (final f in files)
        if (rowByPath[f.path] case final row?
            when secs(f.mtime) != secs(row.mtime))
          f,
    ];
    if (changedFiles.isNotEmpty) {
      await _db.batch((b) {
        for (final f in changedFiles) {
          b.update(
            _db.photos,
            PhotosCompanion(mtime: Value(f.mtime)),
            where: (t) => t.path.equals(f.path),
          );
        }
      });
      await _backfillExif(changedFiles.map((f) => f.path).toList());
    }

    // Backfill exposure fields for rows imported before the v8 schema. Runs
    // once per legacy row (sentinel-guarded), so a reopened shoot picks up
    // bracket detection without a manual re-import.
    await _backfillExposure(existing);
    return (
      added: newFiles.length,
      removed: removedPaths.length,
      changedPaths: [for (final f in changedFiles) f.path],
      unavailable: false,
      unreadable: scan.unreadable.length,
    );
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
    await _db.batch((b) {
      for (final e in exif) {
        b.update(
          _db.photos,
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
    await _db.batch((b) {
      for (final e in exif) {
        b.update(
          _db.photos,
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
      _db.watchPhotosForImport(importId);
}
