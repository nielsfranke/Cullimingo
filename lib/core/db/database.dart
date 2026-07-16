import 'package:cullimingo/core/db/connection.dart';
import 'package:cullimingo/core/db/tables.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:drift/drift.dart';

part 'database.g.dart';

/// The Cullimingo read model: a typed SQLite database (drift). Reactive queries
/// (`watch*`) drive the grid instantly; writes are mirrored to XMP later
/// (Phase 4). See `BUILD_PLAN.md` §3.
@DriftDatabase(tables: [Imports, Photos, SavedSelections])
class AppDatabase extends _$AppDatabase {
  /// Opens the on-disk database. Pass an in-memory [executor] in tests.
  AppDatabase([QueryExecutor? executor]) : super(executor ?? openConnection());

  @override
  int get schemaVersion => 10;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // A development database can drift out of step: a table recreated during
      // an earlier build may already carry a column while the stored schema
      // version lags behind it. A plain ALTER TABLE ADD COLUMN would then fail
      // with "duplicate column name", stranding the whole app. So each step
      // adds only the columns/tables actually missing, making the upgrade
      // idempotent and self-healing.
      final photoCols = await _existingColumns(photos.actualTableName);
      Future<void> addPhotoColumn(GeneratedColumn<Object> column) async {
        if (photoCols.contains(column.name)) return;
        await m.addColumn(photos, column);
      }

      if (from < 2) {
        // Phase 4: keyword storage + XMP sync bookkeeping.
        await addPhotoColumn(photos.keywords);
        await addPhotoColumn(photos.xmpMtime);
        await addPhotoColumn(photos.marksMtime);
        await addPhotoColumn(photos.xmpConflict);
      }
      if (from < 3) {
        // Phase 5: persisted, per-import named selections.
        if (!await _tableExists(savedSelections.actualTableName)) {
          await m.createTable(savedSelections);
        }
      }
      if (from < 4) {
        // Phase 4b: descriptive IPTC Core fields for journalist captioning.
        await addPhotoColumn(photos.iptc);
      }
      if (from < 5) {
        // Phase 9: GPS position for reverse geocoding. Existing rows backfill
        // on the next folder open (the EXIF pass re-runs).
        await addPhotoColumn(photos.latitude);
        await addPhotoColumn(photos.longitude);
      }
      if (from < 6) {
        // Editable rotate: the user's extra clockwise quarter-turns on top of
        // the file's EXIF orientation.
        await addPhotoColumn(photos.userRotation);
      }
      if (from < 7) {
        // Read-only Lightroom/Camera-Raw crop, adopted from XMP.
        await addPhotoColumn(photos.hasCrop);
        await addPhotoColumn(photos.cropLeft);
        await addPhotoColumn(photos.cropTop);
        await addPhotoColumn(photos.cropRight);
        await addPhotoColumn(photos.cropBottom);
        await addPhotoColumn(photos.cropAngle);
      }
      if (from < 8) {
        // Exposure-bracket detection: EV bias + shutter speed. Existing rows
        // stay NULL and backfill once on the next folder open (refreshImport
        // re-scans EXIF for rows whose exposureTime is still NULL).
        await addPhotoColumn(photos.exposureBias);
        await addPhotoColumn(photos.exposureTime);
      }
      if (from < 9) {
        // Manual exposure-bracket stack override (NULL = auto-detect).
        await addPhotoColumn(photos.stackId);
      }
      if (from < 10) {
        // Index for watchPhotosForImport (see the @TableIndex on Photos).
        // Raw IF NOT EXISTS keeps the step idempotent against a drifted dev
        // database, same self-healing rule as the column adds above.
        await customStatement(
          'CREATE INDEX IF NOT EXISTS photos_import_captured '
          'ON photos (import_id, captured_at, path)',
        );
      }
    },
  );

  /// The column names physically present on [table] (via `PRAGMA table_info`),
  /// used to keep migrations idempotent against a drifted dev database.
  Future<Set<String>> _existingColumns(String table) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return {for (final r in rows) r.read<String>('name')};
  }

  /// Whether [table] already exists (so a re-run doesn't recreate it).
  Future<bool> _tableExists(String table) async {
    final rows = await customSelect(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable.withString(table)],
    ).get();
    return rows.isNotEmpty;
  }

  /// Creates an import row and returns its id.
  Future<int> createImport({
    required String sourcePath,
    String? cardLabel,
  }) {
    return into(imports).insert(
      ImportsCompanion.insert(
        sourcePath: sourcePath,
        cardLabel: Value.absentIfNull(cardLabel),
      ),
    );
  }

  /// Inserts many photos in a single batch (ignoring paths already present).
  Future<void> insertPhotos(Iterable<PhotosCompanion> rows) {
    return batch(
      (b) => b.insertAll(photos, rows, mode: InsertMode.insertOrIgnore),
    );
  }

  /// Inserts [rows], or — when a path already exists, possibly under another
  /// import — re-parents that row to [importId], keeping all its marks. Lets a
  /// folder show files that an overlapping folder/tab already claimed (e.g.
  /// opening a parent of already-opened subfolders), where `insertOrIgnore`
  /// would silently drop them. `path` is globally unique by design (one row per
  /// physical file, so marks stay consistent), so ownership just moves.
  Future<void> claimPhotos(int importId, Iterable<PhotosCompanion> rows) {
    return batch((b) {
      for (final row in rows) {
        b.insert(
          photos,
          row,
          onConflict: DoUpdate(
            (_) => PhotosCompanion(importId: Value(importId)),
            target: [photos.path],
          ),
        );
      }
    });
  }

  /// Removes the [paths] from [importId] (used by folder refresh when files
  /// disappear from disk). No-op for an empty list.
  Future<void> deletePhotosByPaths(int importId, List<String> paths) {
    if (paths.isEmpty) return Future.value();
    return (delete(photos)..where(
          (t) => t.importId.equals(importId) & t.path.isIn(paths),
        ))
        .go();
  }

  /// Rewrites the on-disk path of each photo after an in-place rename
  /// ([idToPath]: photo id → new absolute path), preserving every mark. Runs in
  /// one transaction, setting each row to a throwaway temp value first and then
  /// its final path, so a name shuffle within the batch (a→b, b→c) never trips
  /// the `path` UNIQUE index mid-update. Deliberately does **not** stamp
  /// [Photos.marksMtime] — a rename isn't a marks edit.
  Future<void> renamePhotoPaths(Map<int, String> idToPath) {
    if (idToPath.isEmpty) return Future.value();
    return transaction(() async {
      for (final id in idToPath.keys) {
        await (update(photos)..where((t) => t.id.equals(id))).write(
          PhotosCompanion(path: Value('\u0000cullrename:$id')),
        );
      }
      for (final entry in idToPath.entries) {
        await (update(photos)..where((t) => t.id.equals(entry.key))).write(
          PhotosCompanion(path: Value(entry.value)),
        );
      }
    });
  }

  /// One-shot list of an import's photos (see [watchPhotosForImport] for the
  /// reactive variant that drives the grid).
  Future<List<Photo>> photosForImport(int importId) =>
      (select(photos)..where((t) => t.importId.equals(importId))).get();

  /// The current rows for [ids] (missing ids are simply absent).
  Future<List<Photo>> photosByIds(List<int> ids) {
    if (ids.isEmpty) return Future.value(const []);
    return (select(photos)..where((t) => t.id.isIn(ids))).get();
  }

  /// The row for [photoId], or null when it no longer exists.
  Future<Photo?> photoById(int photoId) =>
      (select(photos)..where((t) => t.id.equals(photoId))).getSingleOrNull();

  /// Watches all photos for an import, ordered by capture time then path.
  Stream<List<Photo>> watchPhotosForImport(int importId) {
    return (select(photos)
          ..where((t) => t.importId.equals(importId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.capturedAt),
            (t) => OrderingTerm(expression: t.path),
          ]))
        .watch();
  }

  /// Sets the star rating (0–5) for a photo. Stamps [Photos.marksMtime] so the
  /// sync layer can tell a local edit from an external sidecar change.
  Future<void> setRating(int photoId, int rating) {
    return (update(photos)..where((t) => t.id.equals(photoId))).write(
      PhotosCompanion(rating: Value(rating.clamp(0, 5)), marksMtime: _now),
    );
  }

  /// Sets the same [rating] on every photo in [photoIds] with one UPDATE —
  /// a batch mark costs a single stream emit (one grid rebuild), not one per
  /// photo (§0.6).
  Future<void> setRatingAll(List<int> photoIds, int rating) {
    if (photoIds.isEmpty) return Future.value();
    return (update(photos)..where((t) => t.id.isIn(photoIds))).write(
      PhotosCompanion(rating: Value(rating.clamp(0, 5)), marksMtime: _now),
    );
  }

  /// Sets the manual bracket-stack override on every photo in [photoIds] with
  /// one UPDATE. [stackId] is a non-empty id (manually stacked together), the
  /// empty string (manually unstacked), or null (hand back to auto-detection).
  /// Stamps [Photos.marksMtime] like the other setters so the change mirrors to
  /// the sidecar.
  Future<void> setStackIdAll(List<int> photoIds, String? stackId) {
    if (photoIds.isEmpty) return Future.value();
    return (update(photos)..where((t) => t.id.isIn(photoIds))).write(
      PhotosCompanion(stackId: Value(stackId), marksMtime: _now),
    );
  }

  /// Restores per-photo stack overrides (photo id → stackId) in one
  /// transaction — the undo path for a manual stack/unstack.
  Future<void> setStackIds(Map<int, String?> stackIdByPhotoId) {
    if (stackIdByPhotoId.isEmpty) return Future.value();
    return transaction(() async {
      for (final entry in stackIdByPhotoId.entries) {
        await (update(photos)..where((t) => t.id.equals(entry.key))).write(
          PhotosCompanion(stackId: Value(entry.value), marksMtime: _now),
        );
      }
    });
  }

  /// Restores per-photo ratings (photo id → rating) in one transaction —
  /// the undo path, where each photo gets its own old value back but the
  /// stream still emits once.
  Future<void> setRatings(Map<int, int> ratingByPhotoId) {
    if (ratingByPhotoId.isEmpty) return Future.value();
    return transaction(() async {
      for (final entry in ratingByPhotoId.entries) {
        await setRating(entry.key, entry.value);
      }
    });
  }

  /// Sets the pick/reject flag for a photo.
  Future<void> setFlag(int photoId, PickFlag flag) {
    return (update(photos)..where((t) => t.id.equals(photoId))).write(
      PhotosCompanion(flag: Value(flag), marksMtime: _now),
    );
  }

  /// Sets the same [flag] on every photo in [photoIds] with one UPDATE (see
  /// [setRatingAll]).
  Future<void> setFlagAll(List<int> photoIds, PickFlag flag) {
    if (photoIds.isEmpty) return Future.value();
    return (update(photos)..where((t) => t.id.isIn(photoIds))).write(
      PhotosCompanion(flag: Value(flag), marksMtime: _now),
    );
  }

  /// Restores per-photo flags in one transaction (see [setRatings]).
  Future<void> setFlags(Map<int, PickFlag> flagByPhotoId) {
    if (flagByPhotoId.isEmpty) return Future.value();
    return transaction(() async {
      for (final entry in flagByPhotoId.entries) {
        await setFlag(entry.key, entry.value);
      }
    });
  }

  /// Sets the colour label for a photo.
  Future<void> setColorLabel(int photoId, ColorLabel label) {
    return (update(photos)..where((t) => t.id.equals(photoId))).write(
      PhotosCompanion(colorLabel: Value(label), marksMtime: _now),
    );
  }

  /// Sets the same [label] on every photo in [photoIds] with one UPDATE (see
  /// [setRatingAll]).
  Future<void> setColorLabelAll(List<int> photoIds, ColorLabel label) {
    if (photoIds.isEmpty) return Future.value();
    return (update(photos)..where((t) => t.id.isIn(photoIds))).write(
      PhotosCompanion(colorLabel: Value(label), marksMtime: _now),
    );
  }

  /// Restores per-photo colour labels in one transaction (see [setRatings]).
  Future<void> setColorLabels(Map<int, ColorLabel> labelByPhotoId) {
    if (labelByPhotoId.isEmpty) return Future.value();
    return transaction(() async {
      for (final entry in labelByPhotoId.entries) {
        await setColorLabel(entry.key, entry.value);
      }
    });
  }

  /// Commits a rotation into the file's baked [Photos.orientation] and clears
  /// [Photos.userRotation] — used when the rotate was written into the JPEG's
  /// embedded EXIF, so the re-decoded preview already shows it (no widget-layer
  /// turn needed). Stamps [Photos.marksMtime] like the other mark setters.
  Future<void> setBakedOrientation(int photoId, int orientation) {
    return (update(photos)..where((t) => t.id.equals(photoId))).write(
      PhotosCompanion(
        orientation: Value(orientation),
        userRotation: const Value(0),
        marksMtime: _now,
      ),
    );
  }

  /// Adds [deltaQuarterTurnsCW] clockwise quarter-turns to a photo's
  /// [Photos.userRotation] (wrapping to 0–3), in one read-modify-write
  /// transaction so concurrent rotates can't race. Stamps [Photos.marksMtime]
  /// like the other mark setters (a rotate mirrors to the sidecar).
  Future<void> rotatePhoto(int photoId, int deltaQuarterTurnsCW) {
    return transaction(() async {
      final row = await (select(
        photos,
      )..where((t) => t.id.equals(photoId))).getSingleOrNull();
      if (row == null) return;
      final next = ((row.userRotation + deltaQuarterTurnsCW) % 4 + 4) % 4;
      await (update(photos)..where((t) => t.id.equals(photoId))).write(
        PhotosCompanion(userRotation: Value(next), marksMtime: _now),
      );
    });
  }

  /// Replaces the keyword list for a photo (`dc:subject`).
  Future<void> setKeywords(int photoId, List<String> keywords) {
    return (update(photos)..where((t) => t.id.equals(photoId))).write(
      PhotosCompanion(keywords: Value(keywords), marksMtime: _now),
    );
  }

  /// Replaces the descriptive IPTC Core fields for a photo (Phase 4b). Stamps
  /// [Photos.marksMtime] like the other setters so the sync layer treats it as
  /// a local edit.
  Future<void> setIptc(int photoId, IptcCore iptc) {
    return (update(photos)..where((t) => t.id.equals(photoId))).write(
      PhotosCompanion(iptc: Value(iptc), marksMtime: _now),
    );
  }

  /// Saves [photoIds] under [name] for [importId], replacing any existing
  /// selection with the same name (so re-saving updates in place). Returns the
  /// row id.
  Future<int> saveSelection({
    required int importId,
    required String name,
    required List<int> photoIds,
  }) {
    return into(savedSelections).insert(
      SavedSelectionsCompanion.insert(
        importId: importId,
        name: name,
        photoIds: Value(photoIds),
      ),
      onConflict: DoUpdate(
        (_) => SavedSelectionsCompanion(
          photoIds: Value(photoIds),
          createdAt: _now,
        ),
        target: [savedSelections.importId, savedSelections.name],
      ),
    );
  }

  /// Watches the saved selections for [importId], newest first.
  Stream<List<SavedSelection>> watchSavedSelections(int importId) {
    return (select(savedSelections)
          ..where((t) => t.importId.equals(importId))
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.createdAt,
              mode: OrderingMode.desc,
            ),
          ]))
        .watch();
  }

  /// Deletes the saved selection with [id].
  Future<void> deleteSavedSelection(int id) {
    return (delete(savedSelections)..where((t) => t.id.equals(id))).go();
  }

  Value<DateTime> get _now => Value(DateTime.now());
}
