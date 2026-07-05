import 'dart:convert';

import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:drift/drift.dart';

/// Stores a photo's keyword list (`dc:subject`) as a JSON array in one text
/// column. Empty list ⇄ empty string so the default is cheap and queryable.
class KeywordsConverter extends TypeConverter<List<String>, String> {
  /// Const constructor (drift requires it).
  const KeywordsConverter();

  @override
  List<String> fromSql(String fromDb) => fromDb.isEmpty
      ? const []
      : (jsonDecode(fromDb) as List<dynamic>).cast<String>();

  @override
  String toSql(List<String> value) => value.isEmpty ? '' : jsonEncode(value);
}

/// Stores the descriptive IPTC Core fields ([IptcCore]) as a compact JSON
/// object in one text column. Empty payload ⇄ empty string so the default is
/// cheap. We never query by these fields, so one column beats fourteen.
class IptcCoreConverter extends TypeConverter<IptcCore, String> {
  /// Const constructor (drift requires it).
  const IptcCoreConverter();

  @override
  IptcCore fromSql(String fromDb) => fromDb.isEmpty
      ? const IptcCore()
      : IptcCore.fromJson(jsonDecode(fromDb) as Map<String, dynamic>);

  @override
  String toSql(IptcCore value) =>
      value.isEmpty ? '' : jsonEncode(value.toJson());
}

/// Stores a list of photo ids as a JSON array in one text column (saved
/// selections). Empty list ⇄ empty string so the default is cheap.
class IntListConverter extends TypeConverter<List<int>, String> {
  /// Const constructor (drift requires it).
  const IntListConverter();

  @override
  List<int> fromSql(String fromDb) => fromDb.isEmpty
      ? const []
      : (jsonDecode(fromDb) as List<dynamic>).cast<int>();

  @override
  String toSql(List<int> value) => value.isEmpty ? '' : jsonEncode(value);
}

/// One import / shoot folder — the unit of work (`BUILD_PLAN.md` §3). Ingest
/// (Phase 3) populates [sourcePath]/[destPath]; a plain "open folder" in Phase 1
/// records only the folder it scanned.
class Imports extends Table {
  /// Primary key.
  IntColumn get id => integer().autoIncrement()();

  /// Folder that was scanned / copied from.
  TextColumn get sourcePath => text()();

  /// Destination root (ingest only; null for a plain open-folder).
  TextColumn get destPath => text().nullable()();

  /// When this import row was created.
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Optional human label (e.g. card name).
  TextColumn get cardLabel => text().nullable()();
}

/// A single photo (RAW or JPEG). The drift row is the fast read model; the file
/// + XMP sidecar are the durable truth (`BUILD_PLAN.md` §3).
class Photos extends Table {
  /// Primary key.
  IntColumn get id => integer().autoIncrement()();

  /// Owning import.
  IntColumn get importId => integer().nullable().references(Imports, #id)();

  /// Absolute path to the image file (RAW or JPEG).
  TextColumn get path => text().unique()();

  /// Fast content hash for cache keys / ingest verification (filled lazily).
  TextColumn get contentHash => text().nullable()();

  /// File modification time — part of the cache key.
  DateTimeColumn get mtime => dateTime()();

  /// EXIF DateTimeOriginal, when known. Drives capture-time sort.
  DateTimeColumn get capturedAt => dateTime().nullable()();

  /// Camera model from EXIF.
  TextColumn get camera => text().nullable()();

  /// Lens model from EXIF.
  TextColumn get lens => text().nullable()();

  /// Pixel width of the full image, when known.
  IntColumn get width => integer().nullable()();

  /// Pixel height of the full image, when known.
  IntColumn get height => integer().nullable()();

  /// GPS latitude in decimal degrees (south negative), from EXIF.
  RealColumn get latitude => real().nullable()();

  /// GPS longitude in decimal degrees (west negative), from EXIF.
  RealColumn get longitude => real().nullable()();

  /// EXIF orientation (1–8) as read from the file; 1 = normal. The baseline the
  /// preview is already rendered at. See [userRotation] for the user's edit.
  IntColumn get orientation => integer().withDefault(const Constant(1))();

  /// Extra clockwise quarter-turns (0–3) the user applied on top of the file's
  /// [orientation]. Applied at the widget layer + on export; written through to
  /// the XMP sidecar (and, for JPEG, the embedded EXIF) for interop.
  IntColumn get userRotation => integer().withDefault(const Constant(0))();

  /// Whether the source carries a non-destructive Lightroom/Camera-Raw crop
  /// (`crs:HasCrop`). Read-only, surfaced in the inspector + loupe.
  BoolColumn get hasCrop => boolean().withDefault(const Constant(false))();

  /// The crop rectangle edges + straighten angle from `crs:` (fractions 0–1 of
  /// the frame; angle in degrees). Null when [hasCrop] is false.
  RealColumn get cropLeft => real().nullable()();

  /// See [cropLeft].
  RealColumn get cropTop => real().nullable()();

  /// See [cropLeft].
  RealColumn get cropRight => real().nullable()();

  /// See [cropLeft].
  RealColumn get cropBottom => real().nullable()();

  /// See [cropLeft].
  RealColumn get cropAngle => real().nullable()();

  /// Star rating 0–5.
  IntColumn get rating => integer().withDefault(const Constant(0))();

  /// Pick/reject flag, stored as [PickFlag] index.
  IntColumn get flag => intEnum<PickFlag>().withDefault(const Constant(0))();

  /// Colour label, stored as [ColorLabel] index.
  IntColumn get colorLabel =>
      intEnum<ColorLabel>().withDefault(const Constant(0))();

  /// Keywords (`dc:subject` bag), stored as a JSON array (Phase 4).
  TextColumn get keywords =>
      text().map(const KeywordsConverter()).withDefault(const Constant(''))();

  /// Descriptive IPTC Core fields (caption, creator, credit, location…),
  /// stored as a compact JSON object (Phase 9 Layer 1 / Phase 4b).
  TextColumn get iptc =>
      text().map(const IptcCoreConverter()).withDefault(const Constant(''))();

  /// True if a `.xmp` sidecar exists for this file (Phase 4).
  BoolColumn get hasXmp => boolean().withDefault(const Constant(false))();

  /// Filesystem mtime of the XMP sidecar the last time Cullimingo read or wrote
  /// it. Null = never synced. Used to detect external edits (Phase 4 sync).
  DateTimeColumn get xmpMtime => dateTime().nullable()();

  /// When the cull marks were last changed *inside* Cullimingo. Compared with
  /// [xmpMtime] for last-writer-wins and conflict detection (Phase 4 sync).
  DateTimeColumn get marksMtime => dateTime().nullable()();

  /// True when a sidecar was edited externally while Cullimingo also had local
  /// changes since the last sync — surfaced to the user (Phase 4 sync).
  BoolColumn get xmpConflict => boolean().withDefault(const Constant(false))();

  /// True once a disk-cached preview has been written (Phase 2).
  BoolColumn get previewCached =>
      boolean().withDefault(const Constant(false))();

  /// True for RAW files (embedded-preview path); false for plain JPEG/PNG.
  BoolColumn get isRaw => boolean().withDefault(const Constant(false))();

  /// Exposure compensation in EV (`EXIF ExposureBiasValue`), when the file
  /// exposes it. Feeds exposure-bracket detection. Null when the tag is absent
  /// or unreadable (e.g. Fuji `.RAF`, which falls back to [exposureTime]).
  RealColumn get exposureBias => real().nullable()();

  /// Shutter speed in seconds (`EXIF ExposureTime` / LibRaw `shutter`). Bracket
  /// detection uses it both as the varying signal (when [exposureBias] is
  /// absent) and to size the shutter-aware time-gap tolerance. Sentinel: NULL =
  /// not yet EXIF-scanned, 0.0 = scanned but the tag was absent (0 s is never a
  /// real shutter speed), which is what lets the legacy backfill run once.
  RealColumn get exposureTime => real().nullable()();

  /// Manual exposure-bracket stack override, round-tripped via `cullimingo:
  /// StackId` in XMP. **NULL** = let automatic detection decide (the default);
  /// an **empty string** = the user manually removed this photo from any stack;
  /// a **non-empty id** = the user manually grouped this photo into that stack.
  /// Automatic detection only ever sees NULL photos, so a manual decision is
  /// never re-grouped away.
  TextColumn get stackId => text().nullable()();
}

/// A named, persisted selection of photos within one import (`BUILD_PLAN.md`
/// §5: "saved selections"). Scoped to an import so re-opening a shoot brings
/// back the picks made for it. Names are unique per import.
class SavedSelections extends Table {
  /// Primary key.
  IntColumn get id => integer().autoIncrement()();

  /// Owning import (selections are per-shoot).
  IntColumn get importId => integer().references(Imports, #id)();

  /// Human label for the selection.
  TextColumn get name => text()();

  /// The selected photo ids, stored as a JSON array.
  TextColumn get photoIds =>
      text().map(const IntListConverter()).withDefault(const Constant(''))();

  /// When this selection was created or last replaced.
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {importId, name},
  ];
}
