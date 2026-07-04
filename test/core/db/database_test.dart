import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('inserts photos and reads them back ordered for an import', () async {
    final importId = await db.createImport(sourcePath: '/cards/shootA');

    await db.insertPhotos([
      PhotosCompanion.insert(
        importId: Value(importId),
        path: '/cards/shootA/DSC_0002.ARW',
        mtime: DateTime(2026, 6, 1, 10, 30),
        capturedAt: Value(DateTime(2026, 6, 1, 10, 30)),
        isRaw: const Value(true),
      ),
      PhotosCompanion.insert(
        importId: Value(importId),
        path: '/cards/shootA/DSC_0001.ARW',
        mtime: DateTime(2026, 6, 1, 10),
        capturedAt: Value(DateTime(2026, 6, 1, 10)),
        isRaw: const Value(true),
      ),
    ]);

    final photos = await db.watchPhotosForImport(importId).first;

    expect(photos, hasLength(2));
    // Ordered by capture time: 10:00 before 10:30.
    expect(photos.first.path, endsWith('DSC_0001.ARW'));
    expect(photos.first.rating, 0);
    expect(photos.first.flag, PickFlag.none);
    expect(photos.first.colorLabel, ColorLabel.none);
  });

  test('insertOrIgnore keeps unique paths from duplicating', () async {
    final importId = await db.createImport(sourcePath: '/cards/shootA');
    final row = PhotosCompanion.insert(
      importId: Value(importId),
      path: '/cards/shootA/DSC_0001.ARW',
      mtime: DateTime(2026, 6, 1, 10),
    );

    await db.insertPhotos([row]);
    await db.insertPhotos([row]); // same path again

    final photos = await db.watchPhotosForImport(importId).first;
    expect(photos, hasLength(1));
  });

  test('bulk mark setters hit only the listed photos', () async {
    final importId = await db.createImport(sourcePath: '/s');
    await db.insertPhotos([
      for (var i = 1; i <= 3; i++)
        PhotosCompanion.insert(
          importId: Value(importId),
          path: '/s/$i.ARW',
          mtime: DateTime(2026, 6, 1, 10, i),
        ),
    ]);
    final ids = (await db.watchPhotosForImport(importId).first)
        .map((p) => p.id)
        .toList();

    await db.setRatingAll([ids[0], ids[1]], 9); // clamped to 5
    await db.setFlagAll([ids[1]], PickFlag.reject);
    await db.setColorLabelAll([ids[0], ids[2]], ColorLabel.green);

    final rows = await db.watchPhotosForImport(importId).first;
    Photo byId(int id) => rows.firstWhere((r) => r.id == id);
    expect(byId(ids[0]).rating, 5);
    expect(byId(ids[1]).rating, 5);
    expect(byId(ids[2]).rating, 0);
    expect(byId(ids[1]).flag, PickFlag.reject);
    expect(byId(ids[0]).colorLabel, ColorLabel.green);
    expect(byId(ids[1]).colorLabel, ColorLabel.none);
    // Bulk marks stamp marksMtime like the single setters. (isA, not
    // isNotNull — drift's unprefixed import shadows the matcher.)
    expect(byId(ids[0]).marksMtime, isA<DateTime>());
  });

  test('per-photo map setters restore distinct values (undo path)', () async {
    final importId = await db.createImport(sourcePath: '/s');
    await db.insertPhotos([
      for (var i = 1; i <= 2; i++)
        PhotosCompanion.insert(
          importId: Value(importId),
          path: '/s/$i.ARW',
          mtime: DateTime(2026, 6, 1, 10, i),
        ),
    ]);
    final ids = (await db.watchPhotosForImport(importId).first)
        .map((p) => p.id)
        .toList();

    await db.setRatings({ids[0]: 2, ids[1]: 4});
    await db.setFlags({ids[0]: PickFlag.pick, ids[1]: PickFlag.none});
    await db.setColorLabels({ids[0]: ColorLabel.red, ids[1]: ColorLabel.blue});

    final rows = await db.watchPhotosForImport(importId).first;
    Photo byId(int id) => rows.firstWhere((r) => r.id == id);
    expect(byId(ids[0]).rating, 2);
    expect(byId(ids[1]).rating, 4);
    expect(byId(ids[0]).flag, PickFlag.pick);
    expect(byId(ids[0]).colorLabel, ColorLabel.red);
    expect(byId(ids[1]).colorLabel, ColorLabel.blue);
  });

  test('renamePhotoPaths rewrites paths and survives a name shuffle', () async {
    final importId = await db.createImport(sourcePath: '/s');
    await db.insertPhotos([
      PhotosCompanion.insert(
        importId: Value(importId),
        path: '/s/a.ARW',
        mtime: DateTime(2026, 6, 1, 10),
      ),
      PhotosCompanion.insert(
        importId: Value(importId),
        path: '/s/b.ARW',
        mtime: DateTime(2026, 6, 1, 11),
      ),
    ]);
    var photos = await db.watchPhotosForImport(importId).first;
    final a = photos.firstWhere((p) => p.path.endsWith('a.ARW'));
    final b = photos.firstWhere((p) => p.path.endsWith('b.ARW'));
    // a → b.ARW while b → c.ARW: the temp-then-final transaction must not trip
    // the `path` UNIQUE index even though a takes b's still-current name.
    await db.setRating(a.id, 4);
    await db.renamePhotoPaths({a.id: '/s/b.ARW', b.id: '/s/c.ARW'});

    photos = await db.watchPhotosForImport(importId).first;
    final byId = {for (final p in photos) p.id: p};
    expect(byId[a.id]!.path, '/s/b.ARW');
    expect(byId[b.id]!.path, '/s/c.ARW');
    // The rename preserved the mark.
    expect(byId[a.id]!.rating, 4);
  });

  test('rating, flag and colour persist on the row', () async {
    final importId = await db.createImport(sourcePath: '/cards/shootA');
    await db.insertPhotos([
      PhotosCompanion.insert(
        importId: Value(importId),
        path: '/cards/shootA/DSC_0001.ARW',
        mtime: DateTime(2026, 6, 1, 10),
      ),
    ]);
    final id = (await db.watchPhotosForImport(importId).first).single.id;

    await db.setRating(id, 4);
    await db.setFlag(id, PickFlag.pick);
    await db.setColorLabel(id, ColorLabel.green);

    final photo = (await db.watchPhotosForImport(importId).first).single;
    expect(photo.rating, 4);
    expect(photo.flag, PickFlag.pick);
    expect(photo.colorLabel, ColorLabel.green);
  });

  test('IPTC Core fields default empty and persist via setIptc', () async {
    final importId = await db.createImport(sourcePath: '/cards/shootA');
    await db.insertPhotos([
      PhotosCompanion.insert(
        importId: Value(importId),
        path: '/cards/shootA/DSC_0001.ARW',
        mtime: DateTime(2026, 6, 1, 10),
      ),
    ]);
    final id = (await db.watchPhotosForImport(importId).first).single.id;

    // Default column value decodes to an empty payload.
    expect(
      (await db.watchPhotosForImport(importId).first).single.iptc.isEmpty,
      isTrue,
    );

    await db.setIptc(
      id,
      const IptcCore(caption: 'On the field', credit: 'AP', countryCode: 'DE'),
    );

    final photo = (await db.watchPhotosForImport(importId).first).single;
    expect(photo.iptc.caption, 'On the field');
    expect(photo.iptc.credit, 'AP');
    expect(photo.iptc.countryCode, 'DE');
    expect(photo.iptc.headline, isEmpty);
    // The setter stamps a local-edit time for the sync layer.
    expect(photo.marksMtime != null, isTrue);
  });

  test('setRating clamps to the 0–5 range', () async {
    final importId = await db.createImport(sourcePath: '/cards/shootA');
    await db.insertPhotos([
      PhotosCompanion.insert(
        importId: Value(importId),
        path: '/cards/shootA/DSC_0001.ARW',
        mtime: DateTime(2026, 6, 1, 10),
      ),
    ]);
    final id = (await db.watchPhotosForImport(importId).first).single.id;

    await db.setRating(id, 9);
    expect((await db.watchPhotosForImport(importId).first).single.rating, 5);
  });

  group('saved selections', () {
    test('save, watch (per-import) and delete round-trip', () async {
      final shootA = await db.createImport(sourcePath: '/cards/shootA');
      final shootB = await db.createImport(sourcePath: '/cards/shootB');

      final id = await db.saveSelection(
        importId: shootA,
        name: 'Client picks',
        photoIds: [3, 1, 2],
      );
      await db.saveSelection(
        importId: shootB,
        name: 'Other shoot',
        photoIds: [9],
      );

      final forA = await db.watchSavedSelections(shootA).first;
      expect(forA, hasLength(1));
      expect(forA.single.name, 'Client picks');
      expect(forA.single.photoIds, [3, 1, 2]);

      await db.deleteSavedSelection(id);
      expect(await db.watchSavedSelections(shootA).first, isEmpty);
      // The other import's selection is untouched.
      expect(await db.watchSavedSelections(shootB).first, hasLength(1));
    });

    test('re-saving the same name replaces the ids in place', () async {
      final importId = await db.createImport(sourcePath: '/cards/shootA');
      await db.saveSelection(
        importId: importId,
        name: 'Picks',
        photoIds: [1, 2],
      );
      await db.saveSelection(
        importId: importId,
        name: 'Picks',
        photoIds: [5, 6, 7],
      );

      final saved = await db.watchSavedSelections(importId).first;
      expect(saved, hasLength(1));
      expect(saved.single.photoIds, [5, 6, 7]);
    });
  });

  test('onUpgrade is idempotent against an already-current schema', () async {
    // A dev database can drift: the physical table already carries a column
    // while the stored schema version lags. Re-running the upgrade steps must
    // then skip what's present instead of failing with "duplicate column name"
    // (which used to strand every folder open). Simulate it by running the
    // whole upgrade path over a freshly-created (current) schema.
    await db.createImport(sourcePath: '/seed'); // forces onCreate → full schema
    final onUpgrade = db.migration.onUpgrade;
    await onUpgrade(Migrator(db), 1, db.schemaVersion);

    // The schema is intact and usable afterwards — no crash, no lost table.
    final id = await db.createImport(sourcePath: '/after-upgrade');
    expect(id, greaterThan(0));
    expect(await db.watchSavedSelections(id).first, isEmpty);
  });
}
