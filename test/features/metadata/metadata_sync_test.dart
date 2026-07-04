import 'dart:io';

import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/metadata/data/metadata_repository.dart';
import 'package:cullimingo/features/metadata/data/xmp_codec.dart';
import 'package:cullimingo/features/metadata/data/xmp_sidecar.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/features/metadata/domain/xmp_data.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;
  late MetadataRepository meta;
  late Directory tmp;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    meta = MetadataRepository(db);
    tmp = await Directory.systemTemp.createTemp('cullimingo_xmp');
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  Future<int> insertPhoto(String name) async {
    final importId = await db.createImport(sourcePath: tmp.path);
    await db.insertPhotos([
      PhotosCompanion.insert(
        importId: Value(importId),
        path: p.join(tmp.path, name),
        mtime: DateTime(2026, 6),
      ),
    ]);
    return importId;
  }

  test('sidecar path replaces the extension', () {
    expect(sidecarPath('/x/DSC0001.ARW'), '/x/DSC0001.xmp');
  });

  test('writeSidecarForPhoto mirrors DB marks to a .xmp file', () async {
    await insertPhoto('a.jpg');
    final id = (await db.watchPhotosForImport(1).first).single.id;
    await db.setRating(id, 4);
    await db.setColorLabel(id, ColorLabel.blue);

    await meta.writeSidecarForPhoto(id);

    final xmp = await readSidecar(p.join(tmp.path, 'a.jpg'));
    expect(xmp, isNotNull);
    expect(xmp!.rating, 4);
    expect(xmp.color, ColorLabel.blue);
  });

  test('applySidecarsForImport seeds the DB from existing sidecars', () async {
    final importId = await insertPhoto('b.jpg');
    // A sidecar already exists (e.g. rated earlier in Lightroom).
    await writeSidecar(
      p.join(tmp.path, 'b.jpg'),
      const XmpData(
        rating: 5,
        color: ColorLabel.red,
        flag: PickFlag.pick,
        keywords: ['sunset', 'beach'],
      ),
    );

    await meta.applySidecarsForImport(importId);

    final photo = (await db.watchPhotosForImport(importId).first).single;
    expect(photo.rating, 5);
    expect(photo.colorLabel, ColorLabel.red);
    expect(photo.flag, PickFlag.pick);
    expect(photo.keywords, ['sunset', 'beach']);
    expect(photo.hasXmp, isTrue);
    expect(photo.xmpMtime, isNotNull);
  });

  test(
    'applySidecarsForImport reads XMP embedded in a JPEG (no sidecar)',
    () async {
      final importId = await insertPhoto('embedded.jpg');
      // C1/LR JPEG export: marks embedded inside the file, no .xmp sidecar.
      final packet = encodeXmp(
        const XmpData(
          rating: 5,
          color: ColorLabel.green,
          keywords: ['Basel'],
        ),
      );
      await File(p.join(tmp.path, 'embedded.jpg')).writeAsString('ÿØÿá$packet');

      await meta.applySidecarsForImport(importId);

      final photo = (await db.watchPhotosForImport(importId).first).single;
      expect(photo.rating, 5);
      expect(photo.colorLabel, ColorLabel.green);
      expect(photo.keywords, ['Basel']);
      expect(photo.hasXmp, isTrue);
    },
  );

  test(
    'writeSidecarsForPhotos mirrors a whole batch with one bookkeeping emit',
    () async {
      final importId = await db.createImport(sourcePath: tmp.path);
      await db.insertPhotos([
        for (var i = 1; i <= 3; i++)
          PhotosCompanion.insert(
            importId: Value(importId),
            path: p.join(tmp.path, 'b$i.jpg'),
            mtime: DateTime(2026, 6),
          ),
      ]);
      final ids = (await db.watchPhotosForImport(importId).first)
          .map((photo) => photo.id)
          .toList();
      await db.setRatingAll(ids, 3);

      final emissions = <int>[];
      final sub = db
          .watchPhotosForImport(importId)
          .listen((rows) => emissions.add(rows.length));
      addTearDown(sub.cancel);
      await pumpEventQueue();
      final before = emissions.length;

      await meta.writeSidecarsForPhotos(ids);
      await pumpEventQueue();

      // Every sidecar file exists with the mirrored marks…
      for (var i = 1; i <= 3; i++) {
        final xmp = await readSidecar(p.join(tmp.path, 'b$i.jpg'));
        expect(xmp!.rating, 3);
      }
      // …the bookkeeping landed (write-through recorded, not dirty)…
      final rows = await db.watchPhotosForImport(importId).first;
      for (final photo in rows) {
        expect(photo.hasXmp, isTrue);
        expect(photo.xmpMtime, isNotNull);
        expect(photo.marksMtime, isNull);
      }
      // …in a single transaction: one stream emit for the whole batch.
      expect(emissions.length, before + 1);
    },
  );

  test('reports sidecar-write progress to onSync (+n then -n)', () async {
    await insertPhoto('a.jpg');
    await insertPhoto('b.jpg');
    final ids = [for (final row in await db.select(db.photos).get()) row.id];

    final events = <int>[];
    final tracked = MetadataRepository(db, onSync: events.add);
    await tracked.writeSidecarsForPhotos(ids);

    // Begins with the batch size, ends by releasing it — net zero pending.
    expect(events, [ids.length, -ids.length]);
    expect(events.reduce((a, b) => a + b), 0);
  });

  test('onSync is not called when no rows match', () async {
    final events = <int>[];
    final tracked = MetadataRepository(db, onSync: events.add);
    await tracked.writeSidecarsForPhotos([9999]);
    expect(events, isEmpty);
  });

  test(
    'an unwritable sidecar is reported, not thrown, and never aborts the batch',
    () async {
      // Two photos in one batch: one in a writable folder, one whose path sits
      // under a directory that does not exist, so its `.xmp` write fails (a
      // read-only volume / removed drive in the field).
      final importId = await db.createImport(sourcePath: tmp.path);
      final goodPath = p.join(tmp.path, 'good.jpg');
      final badPath = p.join(tmp.path, 'no', 'such', 'dir', 'bad.jpg');
      await db.insertPhotos([
        PhotosCompanion.insert(
          importId: Value(importId),
          path: goodPath,
          mtime: DateTime(2026, 6),
        ),
        PhotosCompanion.insert(
          importId: Value(importId),
          path: badPath,
          mtime: DateTime(2026, 6),
        ),
      ]);
      final rows = await db.watchPhotosForImport(importId).first;
      final good = rows.firstWhere((r) => r.path == goodPath);
      final bad = rows.firstWhere((r) => r.path == badPath);
      await db.setRatingAll([good.id, bad.id], 4);

      final failures = <int>[];
      final tracked = MetadataRepository(db, onWriteError: failures.add);

      // The whole batch resolves without throwing…
      await tracked.writeSidecarsForPhotos([good.id, bad.id]);

      // …the failure is surfaced (one photo)…
      expect(failures, [1]);

      // …the writable photo still landed on disk with its bookkeeping…
      expect((await readSidecar(goodPath))!.rating, 4);
      final after = await db.watchPhotosForImport(importId).first;
      final goodAfter = after.firstWhere((r) => r.path == goodPath);
      expect(goodAfter.hasXmp, isTrue);
      expect(goodAfter.xmpMtime, isNotNull);
      expect(goodAfter.marksMtime, isNull);

      // …and the failed photo stays locally-dirty so a later sync retries.
      final badAfter = after.firstWhere((r) => r.path == badPath);
      expect(badAfter.hasXmp, isFalse);
      expect(badAfter.marksMtime, isNotNull);
    },
  );

  test('writeSidecarForPhoto round-trips keywords', () async {
    await insertPhoto('k.jpg');
    final id = (await db.watchPhotosForImport(1).first).single.id;
    await db.setKeywords(id, ['portrait', 'studio']);

    await meta.writeSidecarForPhoto(id);

    final xmp = await readSidecar(p.join(tmp.path, 'k.jpg'));
    expect(xmp!.keywords, ['portrait', 'studio']);
  });

  test(
    'writeSidecarForPhoto mirrors IPTC Core fields to the sidecar',
    () async {
      await insertPhoto('iptc.jpg');
      final id = (await db.watchPhotosForImport(1).first).single.id;
      await db.setIptc(
        id,
        const IptcCore(
          caption: 'Goal in the 90th minute.',
          creator: 'Jane Doe',
          credit: 'AP',
          city: 'Munich',
          altText: 'A striker celebrating with arms raised.',
        ),
      );

      await meta.writeSidecarForPhoto(id);

      final xmp = await readSidecar(p.join(tmp.path, 'iptc.jpg'));
      expect(xmp!.iptc.caption, 'Goal in the 90th minute.');
      expect(xmp.iptc.creator, 'Jane Doe');
      expect(xmp.iptc.credit, 'AP');
      expect(xmp.iptc.city, 'Munich');
      expect(xmp.iptc.altText, 'A striker celebrating with arms raised.');
    },
  );

  test(
    'applySidecarsForImport seeds IPTC Core from an existing sidecar',
    () async {
      final importId = await insertPhoto('shot.jpg');
      await writeSidecar(
        p.join(tmp.path, 'shot.jpg'),
        const XmpData(
          rating: 4,
          iptc: IptcCore(caption: 'On the wire', credit: 'Reuters'),
        ),
      );

      await meta.applySidecarsForImport(importId);

      final photo = (await db.watchPhotosForImport(importId).first).single;
      expect(photo.rating, 4);
      expect(photo.iptc.caption, 'On the wire');
      expect(photo.iptc.credit, 'Reuters');
    },
  );

  group('syncSidecarsFromDisk', () {
    Future<Photo> single(int importId) async =>
        (await db.watchPhotosForImport(importId).first).single;

    test('does nothing when a sidecar is unchanged since our write', () async {
      final importId = await insertPhoto('s.jpg');
      final id = (await single(importId)).id;
      await db.setRating(id, 3);
      await meta.writeSidecarForPhoto(id);

      final result = await meta.syncSidecarsFromDisk(importId);

      expect(result.isEmpty, isTrue);
      expect((await single(importId)).rating, 3);
    });

    test('adopts an externally-edited sidecar (last-writer-wins)', () async {
      final importId = await insertPhoto('e.jpg');
      final id = (await single(importId)).id;
      await db.setRating(id, 2);
      await meta.writeSidecarForPhoto(id);

      // Another app rewrites the sidecar later (newer mtime).
      final path = p.join(tmp.path, 'e.jpg');
      await writeSidecar(
        path,
        const XmpData(rating: 5, color: ColorLabel.green),
      );
      await _bumpMtime(path);

      final result = await meta.syncSidecarsFromDisk(importId);

      expect(result.updated, 1);
      expect(result.conflicts, 0);
      final photo = await single(importId);
      expect(photo.rating, 5);
      expect(photo.colorLabel, ColorLabel.green);
      expect(photo.xmpConflict, isFalse);
    });

    test('flags a conflict and the newer side wins it', () async {
      final importId = await insertPhoto('c.jpg');
      final id = (await single(importId)).id;
      // Local change first, written through.
      await db.setRating(id, 4);
      await meta.writeSidecarForPhoto(id);

      // Then BOTH change again: external sidecar edited with a newer mtime,
      // local marks touched but kept older.
      final path = p.join(tmp.path, 'c.jpg');
      await db.setColorLabel(id, ColorLabel.blue); // local edit (older mtime)
      await writeSidecar(path, const XmpData(rating: 1));
      await _bumpMtime(path); // external is the newer write

      final result = await meta.syncSidecarsFromDisk(importId);

      expect(result.conflicts, 1);
      final photo = await single(importId);
      expect(photo.rating, 1); // external won (newer)
      expect(photo.xmpConflict, isTrue);
    });
  });
}

/// Pushes a file's mtime safely past `now` so a sync sees it as newer than the
/// DB's recorded marks (second-granularity mtimes defeat `DateTime.now()`).
Future<void> _bumpMtime(String photoPath) async {
  final file = File(p.setExtension(photoPath, '.xmp'));
  await file.setLastModified(DateTime.now().add(const Duration(seconds: 5)));
}
