import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/raw/orientation_math.dart';
import 'package:cullimingo/features/metadata/data/marks_reader.dart';
import 'package:cullimingo/features/metadata/data/xmp_sidecar.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/features/metadata/domain/xmp_data.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show compute;

/// Outcome of a disk → DB sync pass (`BUILD_PLAN.md` §4).
class SyncResult {
  /// Creates a result.
  const SyncResult({this.updated = 0, this.conflicts = 0});

  /// Photos whose marks were adopted from an externally-changed sidecar.
  final int updated;

  /// Photos changed both locally and externally since the last sync — the
  /// newer side won (last-writer-wins) but the clash is surfaced.
  final int conflicts;

  /// Whether anything changed.
  bool get isEmpty => updated == 0 && conflicts == 0;
}

/// Keeps the drift read model and XMP sidecars in sync (`BUILD_PLAN.md` §4).
///
/// Policy: every local mark change writes through to the sidecar immediately
/// and records the sidecar's mtime (`xmpMtime`). A later
/// [syncSidecarsFromDisk] compares that with the file's current mtime to spot
/// edits made in Capture One / Lightroom; ties between a local and an external
/// change are resolved last-writer-wins by mtime and flagged as a conflict.
class MetadataRepository {
  /// Creates a repository over [db]. [onSync] (optional) is notified with the
  /// photo count as sidecar writes begin (`+n`) and finish (`-n`), so the UI
  /// can show a "Syncing N…" indicator and the quit guard can wait for pending
  /// writes. [onWriteError] (optional) is notified with the number of photos
  /// whose sidecar couldn't be written (a read-only volume, a full disk, a
  /// removed drive), so the UI can warn instead of the failure being invisible.
  /// Both are left null in tests / where the write isn't user-visible.
  const MetadataRepository(this.db, {this.onSync, this.onWriteError});

  /// The read-model database.
  final AppDatabase db;

  /// Sidecar-write progress reporter (see the constructor).
  final void Function(int deltaPhotos)? onSync;

  /// Sidecar-write failure reporter (see the constructor).
  final void Function(int failedPhotos)? onWriteError;

  /// Mirrors a photo's current marks out to its XMP sidecar (call after a
  /// rating/flag/colour/keyword change) and records the new sidecar mtime so a
  /// later sync won't mistake our own write for an external edit.
  Future<void> writeSidecarForPhoto(int photoId) =>
      writeSidecarsForPhotos([photoId]);

  /// Mirrors many photos' marks out to their XMP sidecars in one batch: the
  /// file writes run a few at a time (independent files), then the sync
  /// bookkeeping (`xmpMtime` etc.) lands in a single transaction — the photos
  /// stream emits once for the whole batch instead of once per photo, so the
  /// grid rebuilds once after a batch mark (§0.6).
  Future<void> writeSidecarsForPhotos(List<int> photoIds) async {
    if (photoIds.isEmpty) return;
    final rows = await (db.select(
      db.photos,
    )..where((t) => t.id.isIn(photoIds))).get();
    if (rows.isEmpty) return;

    onSync?.call(rows.length);
    try {
      final failed = await _writeSidecarsForRows(rows);
      if (failed > 0) onWriteError?.call(failed);
    } finally {
      onSync?.call(-rows.length);
    }
  }

  /// Writes each row's sidecar (a few files at a time), then records the sync
  /// bookkeeping for the ones that succeeded in a single transaction. A file we
  /// can't write (a read-only volume, a full disk, a removed drive) is skipped
  /// rather than throwing and aborting the whole batch: the DB marks already
  /// landed, so the row keeps its pending `marksMtime` (stays locally-dirty, so
  /// it's re-written the next time that photo is marked) and counts toward the
  /// returned failure total, which the caller surfaces to the user. Returns the
  /// number of photos whose sidecar write failed.
  Future<int> _writeSidecarsForRows(List<Photo> rows) async {
    final mtimes = <int, DateTime?>{};
    final failed = <int>{};
    var next = 0;
    Future<void> worker() async {
      while (next < rows.length) {
        final photo = rows[next++];
        final orientation = rotateOrientation(
          photo.orientation,
          photo.userRotation,
        );
        try {
          await writeSidecar(
            photo.path,
            XmpData(
              rating: photo.rating,
              color: photo.colorLabel,
              flag: photo.flag,
              keywords: photo.keywords,
              iptc: photo.iptc,
              dateCreated: photo.capturedAt,
              orientation: orientation,
              stackId: photo.stackId,
            ),
          );
          mtimes[photo.id] = await _sidecarMtime(photo.path);
        } on Object {
          failed.add(photo.id);
        }
      }
    }

    const concurrency = 4;
    await Future.wait([
      for (var w = 0; w < concurrency && w < rows.length; w++) worker(),
    ]);

    // Bookkeeping only for the rows we actually wrote; failed rows stay
    // locally-dirty so a later sync tries again.
    final written = [
      for (final p in rows)
        if (!failed.contains(p.id)) p,
    ];
    if (written.isNotEmpty) {
      await db.transaction(() async {
        for (final photo in written) {
          await (db.update(
            db.photos,
          )..where((t) => t.id.equals(photo.id))).write(
            PhotosCompanion(
              hasXmp: const Value(true),
              xmpMtime: Value(mtimes[photo.id]),
              // DB and sidecar now match → no pending local change. (Also
              // dodges a false "locally dirty" from sub-second marksMtime vs
              // second-truncated file mtime.)
              marksMtime: const Value(null),
              xmpConflict: const Value(false),
            ),
          );
        }
      });
    }
    return failed.length;
  }

  /// Seeds the read model from any pre-existing external marks on import —
  /// Capture One / Lightroom are the durable truth, so they override the
  /// freshly-scanned defaults. Marks come from a `.xmp` sidecar (RAW) or from
  /// XMP embedded in the image file (exported JPEG/HEIC/TIFF).
  Future<void> applySidecarsForImport(int importId) => _applyMarks(importId);

  /// Like [applySidecarsForImport] but limited to [paths] — folder refresh uses
  /// it so freshly-appeared files get their marks without re-adopting (and thus
  /// clobbering) local edits on photos that were already in the grid.
  Future<void> applyMarksForPaths(int importId, Set<String> paths) =>
      _applyMarks(importId, onlyPaths: paths);

  Future<void> _applyMarks(int importId, {Set<String>? onlyPaths}) async {
    if (onlyPaths != null && onlyPaths.isEmpty) return;
    final rows = await (db.select(
      db.photos,
    )..where((t) => t.importId.equals(importId))).get();
    final targets = [
      for (final photo in rows)
        if (onlyPaths == null || onlyPaths.contains(photo.path)) photo,
    ];
    if (targets.isEmpty) return;

    // Read every photo's marks + sidecar mtime on a background isolate in one
    // pass — the file I/O and XMP parsing must never block the grid (§2).
    final paths = [for (final photo in targets) photo.path];
    // `compute` sends only [paths] to the isolate — a closure over `readMarks`
    // here would capture `this` (and the unsendable drift `db`) with it.
    final reads = await compute(readMarksForPaths, paths);

    // Apply them in a SINGLE batch so the drift stream re-emits once, not once
    // per photo. A per-row write made ratings/flags trickle in after the
    // thumbnails and forced every visible cell (and the burst grouping) to
    // rebuild N times as the marks landed.
    await db.batch((b) {
      for (var i = 0; i < targets.length; i++) {
        final (xmp, mtime) = reads[i];
        if (xmp == null) continue;
        final turns = _turnsFromSidecar(targets[i].orientation, xmp);
        b.update(
          db.photos,
          PhotosCompanion(
            rating: Value(xmp.rating),
            colorLabel: Value(xmp.color),
            flag: Value(xmp.flag),
            keywords: Value(xmp.keywords),
            iptc: Value(_adoptedIptc(targets[i], xmp)),
            hasXmp: const Value(true),
            xmpMtime: Value(mtime),
            // DB now matches the sidecar → no pending local change.
            marksMtime: const Value(null),
            xmpConflict: const Value(false),
            // Adopt a read-only Lightroom/Camera-Raw crop for display.
            hasCrop: Value(xmp.crop != null),
            cropLeft: Value(xmp.crop?.left),
            cropTop: Value(xmp.crop?.top),
            cropRight: Value(xmp.crop?.right),
            cropBottom: Value(xmp.crop?.bottom),
            cropAngle: Value(xmp.crop?.angle),
            // Adopt a manual bracket-stack decision the sidecar carries.
            stackId: Value(xmp.stackId),
            // Adopt an external rotation (see [_turnsFromSidecar]).
            userRotation: turns == null ? const Value.absent() : Value(turns),
          ),
          where: (t) => t.id.equals(targets[i].id),
        );
      }
    });
  }

  /// The `userRotation` to adopt from a sidecar's `tiff:Orientation`, or null
  /// to leave the stored value untouched: an absent orientation makes no
  /// statement (both "never rotated" and "rotated back to normal" stay
  /// silent), and a mirror-mismatched value can't be expressed as quarter
  /// turns on top of the file's baked orientation.
  static int? _turnsFromSidecar(int baseOrientation, XmpData xmp) {
    final target = xmp.orientation;
    if (target == null) return null;
    return quarterTurnsBetween(baseOrientation, target);
  }

  /// [xmp]'s IPTC to adopt, with a Date Created that merely echoes the
  /// capture time cleared back to "unset". The encoder writes the capture
  /// time as `photoshop:DateCreated` fallback for C1/LR; adopting that echo
  /// as an explicit value would flip the field's "empty = follows capture
  /// time" semantics on the first round-trip. Compared at whole seconds
  /// (drift persists seconds; the XMP value has second precision).
  static IptcCore _adoptedIptc(Photo photo, XmpData xmp) {
    final dateCreated = xmp.iptc.dateCreatedParsed;
    final captured = photo.capturedAt;
    if (dateCreated == null || captured == null) return xmp.iptc;
    final echoesCapture =
        dateCreated.millisecondsSinceEpoch ~/ 1000 ==
        captured.millisecondsSinceEpoch ~/ 1000;
    return echoesCapture
        ? xmp.iptc.withOverrides({IptcField.dateCreated: ''})
        : xmp.iptc;
  }

  /// Re-reads sidecars from disk for [importId] and reconciles them with the DB
  /// (call to pick up edits made in another app). External edits are adopted;
  /// a photo changed on both sides keeps whichever mtime is newer and is
  /// flagged as a conflict. Returns counts for the UI to surface.
  Future<SyncResult> syncSidecarsFromDisk(int importId) async {
    final rows = await (db.select(
      db.photos,
    )..where((t) => t.importId.equals(importId))).get();
    if (rows.isEmpty) return const SyncResult();

    // Scan every sidecar's mtime + (when changed) parse its marks on a
    // background isolate in one pass — the file I/O and XMP parsing must never
    // block the grid (§2). Passing each photo's known xmpMtime lets the isolate
    // skip re-parsing sidecars that haven't moved since our own write.
    final queries = [for (final photo in rows) (photo.path, photo.xmpMtime)];
    // `compute` sends only [queries] to the isolate — a closure here would
    // capture `this` (and the unsendable drift `db`) with it.
    final states = await compute(readSidecarSyncStates, queries);

    var updated = 0;
    var conflicts = 0;
    for (var i = 0; i < rows.length; i++) {
      final photo = rows[i];
      final (fileMtime, xmp) = states[i];
      if (fileMtime == null) continue; // no sidecar on disk
      // Our own last write left xmpMtime == the file's mtime; unchanged means
      // nothing happened outside Cullimingo.
      if (photo.xmpMtime != null && fileMtime == photo.xmpMtime) continue;

      if (xmp == null) continue; // changed since our write but unparseable

      // marksMtime is set on every local edit and cleared whenever the DB and
      // sidecar are brought into agreement (write-through / adopt), so a
      // non-null value means a local change the sidecar hasn't seen.
      final localChanged = photo.marksMtime != null;

      if (!localChanged) {
        // Only the sidecar moved → adopt it (last-writer-wins, trivially).
        // `onlyIfClean` re-checks marksMtime *inside* the UPDATE: this loop
        // runs from a snapshot while the grid is already live (background
        // resync on folder open), so the user may have marked this photo
        // since — blindly adopting would silently erase that fresh mark.
        // A skipped row is left dirty and surfaces as a conflict next sync.
        final adopted = await _adoptSidecar(
          photo,
          xmp,
          mtime: fileMtime,
          onlyIfClean: true,
        );
        if (adopted) updated++;
        continue;
      }

      // Both sides changed since the last sync → conflict; newer mtime wins.
      conflicts++;
      if (fileMtime.isAfter(photo.marksMtime!)) {
        await _adoptSidecar(photo, xmp, mtime: fileMtime, conflict: true);
        updated++;
      } else {
        // Local marks are newer: keep them, push back to the sidecar, but flag
        // that an external change was overruled.
        await writeSidecarForPhoto(photo.id);
        await (db.update(db.photos)..where((t) => t.id.equals(photo.id))).write(
          const PhotosCompanion(xmpConflict: Value(true)),
        );
      }
    }
    return SyncResult(updated: updated, conflicts: conflicts);
  }

  /// Adopts [xmp] into [photo]'s row. With [onlyIfClean] the UPDATE only
  /// applies while the row still has no pending local change (`marksMtime`
  /// IS NULL) — the guard against a mark made while a background sync was
  /// running from its snapshot. Returns whether the row was written.
  Future<bool> _adoptSidecar(
    Photo photo,
    XmpData xmp, {
    DateTime? mtime,
    bool conflict = false,
    bool onlyIfClean = false,
  }) async {
    final turns = _turnsFromSidecar(photo.orientation, xmp);
    final rows =
        await (db.update(db.photos)..where(
              (t) => onlyIfClean
                  ? t.id.equals(photo.id) & t.marksMtime.isNull()
                  : t.id.equals(photo.id),
            ))
            .write(
              PhotosCompanion(
                rating: Value(xmp.rating),
                colorLabel: Value(xmp.color),
                flag: Value(xmp.flag),
                keywords: Value(xmp.keywords),
                iptc: Value(_adoptedIptc(photo, xmp)),
                hasXmp: const Value(true),
                xmpMtime: Value(mtime ?? await _sidecarMtime(photo.path)),
                // DB now matches the sidecar → no pending local change.
                marksMtime: const Value(null),
                xmpConflict: Value(conflict),
                hasCrop: Value(xmp.crop != null),
                cropLeft: Value(xmp.crop?.left),
                cropTop: Value(xmp.crop?.top),
                cropRight: Value(xmp.crop?.right),
                cropBottom: Value(xmp.crop?.bottom),
                cropAngle: Value(xmp.crop?.angle),
                stackId: Value(xmp.stackId),
                // Adopt an external rotation (see [_turnsFromSidecar]).
                userRotation: turns == null
                    ? const Value.absent()
                    : Value(turns),
              ),
            );
    return rows > 0;
  }

  // Whole-second-truncated sidecar mtime (see [readSidecarMtime]); shared with
  // the import mark-read pass so both compare equal against the stored value.
  Future<DateTime?> _sidecarMtime(String photoPath) =>
      readSidecarMtime(photoPath);
}
