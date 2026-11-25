import 'dart:io';

import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/library/data/folder_scanner.dart';
import 'package:cullimingo/features/library/data/library_repository.dart';
import 'package:cullimingo/features/metadata/data/metadata_repository.dart';
import 'package:cullimingo/features/metadata/data/xmp_sidecar.dart';
import 'package:cullimingo/features/metadata/domain/xmp_data.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
// Rational isn't re-exported from package:image; GPS fixtures need raw
// IfdValues (the string-keyed setter drops GPS tags — wrong tag table).
import 'package:image/src/util/rational.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;
  late LibraryRepository repo;
  late Directory tmp;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = LibraryRepository(db);
    tmp = await Directory.systemTemp.createTemp('cullimingo_scan');
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  void writeJpeg(String name) {
    final image = img.Image(width: 8, height: 8);
    File(p.join(tmp.path, name)).writeAsBytesSync(img.encodeJpg(image));
  }

  void writeJpegAt(String name, String dateTimeOriginal) {
    final image = img.Image(width: 8, height: 8);
    image.exif.exifIfd['DateTimeOriginal'] = dateTimeOriginal;
    File(p.join(tmp.path, name)).writeAsBytesSync(img.encodeJpg(image));
  }

  test('imports only supported photos and flags RAW correctly', () async {
    writeJpeg('a.jpg');
    writeJpeg('b.JPG');
    // A nested folder is scanned recursively.
    final sub = Directory(p.join(tmp.path, 'sub'))..createSync();
    File(p.join(sub.path, 'c.arw')).writeAsBytesSync(const [0, 1, 2]);
    // Non-photo files are ignored.
    File(p.join(tmp.path, 'notes.txt')).writeAsBytesSync(const [9]);

    final importId = await repo.importFolder(tmp.path);
    final photos = await repo.watchImport(importId).first;

    expect(photos, hasLength(3));
    final raws = photos.where((ph) => ph.isRaw).toList();
    expect(raws, hasLength(1));
    expect(raws.single.path, endsWith('c.arw'));
    expect(photos.every((ph) => ph.importId == importId), isTrue);
  });

  test('includes video files alongside photos in the grid', () async {
    writeJpeg('a.jpg');
    File(p.join(tmp.path, 'clip.mp4')).writeAsBytesSync(const [0, 0, 0]);
    File(p.join(tmp.path, 'notes.txt')).writeAsBytesSync(const [9]);

    final importId = await repo.importFolder(tmp.path);
    final photos = await repo.watchImport(importId).first;

    expect(
      photos.map((ph) => p.basename(ph.path)).toSet(),
      {'a.jpg', 'clip.mp4'}, // video included, junk ignored
    );
  });

  test('backfills the GPS position into the photo row', () async {
    final image = img.Image(width: 8, height: 8);
    image.exif.imageIfd['Make'] = 'Sony';
    image.exif.gpsIfd['GPSLatitudeRef'] = img.IfdValueAscii('S');
    image.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational.list([
      Rational(33, 1),
      Rational(51, 1),
      Rational(0, 1),
    ]);
    image.exif.gpsIfd['GPSLongitudeRef'] = img.IfdValueAscii('E');
    image.exif.gpsIfd['GPSLongitude'] = img.IfdValueRational.list([
      Rational(151, 1),
      Rational(12, 1),
      Rational(0, 1),
    ]);
    File(p.join(tmp.path, 'gps.jpg')).writeAsBytesSync(img.encodeJpg(image));
    writeJpeg('plain.jpg');

    final importId = await repo.importFolder(tmp.path);
    final photos = await repo.watchImport(importId).first;

    final gps = photos.singleWhere((ph) => ph.path.endsWith('gps.jpg'));
    expect(gps.latitude, closeTo(-33.85, 0.001)); // south → negative
    expect(gps.longitude, closeTo(151.2, 0.001));
    final plain = photos.singleWhere((ph) => ph.path.endsWith('plain.jpg'));
    expect(plain.latitude, isNull);
    expect(plain.longitude, isNull);
  });

  void writeJpegWithExposure(String name, {num? bias, num? shutter}) {
    final image = img.Image(width: 8, height: 8);
    image.exif.imageIfd['Make'] = 'Sony';
    if (bias != null) {
      image.exif.exifIfd['ExposureBiasValue'] = img.IfdValueSRational(
        bias.round(),
        1,
      );
    }
    if (shutter != null) {
      image.exif.exifIfd['ExposureTime'] = img.IfdValueRational(
        1,
        shutter ~/ 1,
      );
    }
    File(p.join(tmp.path, name)).writeAsBytesSync(img.encodeJpg(image));
  }

  test('backfills exposure bias and shutter into the photo row', () async {
    writeJpegWithExposure('bracket.jpg', bias: -2, shutter: 200);
    writeJpeg('noexif.jpg');

    final importId = await repo.importFolder(tmp.path);
    final photos = await repo.watchImport(importId).first;

    final b = photos.singleWhere((ph) => ph.path.endsWith('bracket.jpg'));
    expect(b.exposureBias, -2.0);
    expect(b.exposureTime, closeTo(1 / 200, 0.000001));
    // A photo with no exposure tag is still marked scanned (0.0 sentinel), so
    // the legacy backfill never revisits it.
    final n = photos.singleWhere((ph) => ph.path.endsWith('noexif.jpg'));
    expect(n.exposureBias, isNull);
    expect(n.exposureTime, 0.0);
  });

  test('refreshImport backfills exposure for pre-v8 rows', () async {
    writeJpegWithExposure('legacy.jpg', bias: 1, shutter: 60);
    final importId = await repo.importFolder(tmp.path);

    // Simulate a row imported before the v8 columns existed: NULL exposureTime.
    await (db.update(
      db.photos,
    )..where((t) => t.path.equals(p.join(tmp.path, 'legacy.jpg')))).write(
      const PhotosCompanion(
        exposureBias: Value(null),
        exposureTime: Value(null),
      ),
    );
    expect(
      (await repo.watchImport(importId).first).single.exposureTime,
      isNull,
    );

    await repo.refreshImport(importId, tmp.path);

    final row = (await repo.watchImport(importId).first).single;
    expect(row.exposureBias, 1.0);
    expect(row.exposureTime, closeTo(1 / 60, 0.000001));
  });

  test('orders by EXIF capture time, not filename', () async {
    // Filename order (a, b) is the reverse of capture order.
    writeJpegAt('a_later.jpg', '2026:06:01 18:00:00');
    writeJpegAt('b_earlier.jpg', '2026:06:01 09:00:00');

    final importId = await repo.importFolder(tmp.path);
    final photos = await repo.watchImport(importId).first;

    expect(photos.map((photo) => p.basename(photo.path)).toList(), [
      'b_earlier.jpg',
      'a_later.jpg',
    ]);
    expect(photos.first.capturedAt, DateTime(2026, 6, 1, 9));
  });

  test(
    're-opening the same folder reuses the import (no duplicates)',
    () async {
      writeJpeg('a.jpg');

      final first = await repo.importFolder(tmp.path);
      final second = await repo.importFolder(tmp.path);

      // The folder is recognised and its existing import reused — so it opens
      // again, with its photos, instead of creating an empty second import.
      expect(second, first);
      expect(await repo.watchImport(first).first, hasLength(1));
    },
  );

  group('overlapping folders', () {
    test(
      'a parent and its subfolder both show the shared file, marks shared',
      () async {
        final sub = Directory(p.join(tmp.path, 'sub'))..createSync();
        File(p.join(sub.path, 'a.jpg')).writeAsBytesSync(
          img.encodeJpg(img.Image(width: 8, height: 8)),
        );

        final subId = await repo.importFolder(sub.path);
        final subPhoto = (await repo.watchImport(subId).first).single;
        await db.setRating(subPhoto.id, 5);

        // Opening the parent shows the same row (one per physical file) and
        // leaves the subfolder tab showing it too (#31).
        final parentId = await repo.importFolder(tmp.path);
        final parentPhotos = await repo.watchImport(parentId).first;
        expect(parentPhotos.single.id, subPhoto.id);
        expect(parentPhotos.single.rating, 5);
        expect(await repo.watchImport(subId).first, hasLength(1));
      },
    );

    test(
      'parent and subfolder tabs stay full through any refresh (#31)',
      () async {
        final sub = Directory(p.join(tmp.path, 'day2'))..createSync();
        final jpg = img.encodeJpg(img.Image(width: 8, height: 8));
        File(p.join(tmp.path, 'a.jpg')).writeAsBytesSync(jpg);
        File(p.join(sub.path, 'b.jpg')).writeAsBytesSync(jpg);
        final parentId = await repo.importFolder(tmp.path);
        final subId = await repo.importFolder(sub.path);

        Future<void> expectBoth() async {
          expect(await repo.watchImport(parentId).first, hasLength(2));
          expect(await repo.watchImport(subId).first, hasLength(1));
        }

        await expectBoth();
        // Restart: both tabs rescan concurrently.
        await Future.wait([
          repo.refreshImport(parentId, tmp.path),
          repo.refreshImport(subId, sub.path),
        ]);
        await expectBoth();
        // Ctrl+R on either tab.
        await repo.refreshImport(parentId, tmp.path);
        await expectBoth();
        await repo.refreshImport(subId, sub.path);
        await expectBoth();
      },
    );

    test('sub-folders off hides their photos without deleting them', () async {
      final sub = Directory(p.join(tmp.path, 'day2'))..createSync();
      final jpg = img.encodeJpg(img.Image(width: 8, height: 8));
      File(p.join(tmp.path, 'a.jpg')).writeAsBytesSync(jpg);
      File(p.join(sub.path, 'b.jpg')).writeAsBytesSync(jpg);
      final parentId = await repo.importFolder(tmp.path);
      final subId = await repo.importFolder(sub.path);

      // The toggle off re-scans non-recursively: nothing may be removed.
      final r = await repo.refreshImport(parentId, tmp.path, recursive: false);
      expect(r.removed, 0);
      final flat = await repo.watchImport(parentId, recursive: false).first;
      expect(flat.map((ph) => p.basename(ph.path)), ['a.jpg']);
      expect(await repo.watchImport(subId).first, hasLength(1));
      expect(await repo.watchImport(parentId).first, hasLength(2));
    });

    test('a sibling folder sharing a name prefix is not included', () async {
      final shoot = Directory(p.join(tmp.path, 'shoot'))..createSync();
      final sibling = Directory(p.join(tmp.path, 'shoot2'))..createSync();
      final jpg = img.encodeJpg(img.Image(width: 8, height: 8));
      File(p.join(shoot.path, 'a.jpg')).writeAsBytesSync(jpg);
      File(p.join(sibling.path, 'b.jpg')).writeAsBytesSync(jpg);
      await repo.importFolder(sibling.path);
      final shootId = await repo.importFolder(shoot.path);
      final photos = await repo.watchImport(shootId).first;
      expect(photos.map((ph) => p.basename(ph.path)), ['a.jpg']);
    });

    test(
      'a parent shows what a subfolder brought in, before any scan',
      () async {
        // The DCIM case: a subfolder was opened first, the parent import exists
        // but was never scanned. It shows the subfolder's file straight away,
        // and its refresh neither re-adds nor removes it.
        final sub = Directory(p.join(tmp.path, 'sub'))..createSync();
        File(p.join(sub.path, 'a.jpg')).writeAsBytesSync(
          img.encodeJpg(img.Image(width: 8, height: 8)),
        );
        await repo.importFolder(sub.path);
        final (parentId, _) = await repo.findOrCreateImport(tmp.path);
        expect(await repo.watchImport(parentId).first, hasLength(1));

        final r = await repo.refreshImport(parentId, tmp.path);
        expect(r.added, 0);
        expect(r.removed, 0);
        expect(await repo.watchImport(parentId).first, hasLength(1));
      },
    );
  });

  group('refreshImport', () {
    test('adds new files and removes vanished ones', () async {
      writeJpeg('a.jpg');
      writeJpeg('b.jpg');
      final importId = await repo.importFolder(tmp.path);
      expect(await repo.watchImport(importId).first, hasLength(2));

      // A new file is copied in; an old one is deleted.
      writeJpeg('c.jpg');
      File(p.join(tmp.path, 'a.jpg')).deleteSync();

      final (
        :added,
        :removed,
        changedPaths: _,
        unavailable: _,
        unreadable: _,
      ) = await repo.refreshImport(
        importId,
        tmp.path,
      );

      expect(added, 1);
      expect(removed, 1);
      final names = (await repo.watchImport(importId).first)
          .map((ph) => p.basename(ph.path))
          .toSet();
      expect(names, {'b.jpg', 'c.jpg'});
    });

    test('a vanished folder is reported, never emptied', () async {
      writeJpeg('a.jpg');
      writeJpeg('b.jpg');
      final importId = await repo.importFolder(tmp.path);
      final missing = p.join(tmp.path, 'unplugged');

      final result = await repo.refreshImport(importId, missing);

      expect(result.unavailable, isTrue);
      expect(result.removed, 0);
      expect(await repo.watchImport(importId).first, hasLength(2));
    });

    test('an empty listing (bare mount point) removes nothing', () async {
      final card = Directory(p.join(tmp.path, 'card'))..createSync();
      writeJpeg(p.join('card', 'a.jpg'));
      final importId = await repo.importFolder(card.path);
      File(p.join(card.path, 'a.jpg')).deleteSync(); // card "unmounted"

      final result = await repo.refreshImport(importId, card.path);

      expect(result.unavailable, isTrue);
      expect(await repo.watchImport(importId).first, hasLength(1));
    });

    test('a partial scan adds new files but removes nothing', () async {
      writeJpeg('a.jpg');
      final sub = Directory(p.join(tmp.path, 'sub'))..createSync();
      writeJpeg(p.join('sub', 'b.jpg'));
      final importId = await repo.importFolder(tmp.path);
      expect(await repo.watchImport(importId).first, hasLength(2));

      // `sub` turns unreadable (permissions, a flaky reader) and a new file
      // lands at the top: the scan sees a.jpg + c.jpg and an error for `sub`.
      writeJpeg('c.jpg');
      Future<FolderScan> partial(
        String root, {
        bool recursive = true,
        bool includeVideos = false,
      }) async {
        final full = await scanFolder(
          root,
          recursive: recursive,
          includeVideos: includeVideos,
        );
        return FolderScan(
          [
            for (final f in full.files)
              if (!p.isWithin(sub.path, f.path)) f,
          ],
          unreadable: [ScanProblem(sub.path, 'Permission denied')],
        );
      }

      final result = await LibraryRepository(
        db,
        scanner: partial,
      ).refreshImport(importId, tmp.path);

      expect(result.unavailable, isFalse);
      expect(result.added, 1);
      expect(result.removed, 0);
      expect(result.unreadable, 1);
      final names = (await repo.watchImport(importId).first)
          .map((ph) => p.basename(ph.path))
          .toSet();
      expect(names, {'a.jpg', 'b.jpg', 'c.jpg'});
    });

    test('preserves local edits on existing photos', () async {
      final meta = MetadataRepository(db);
      final metaRepo = LibraryRepository(db, metadata: meta);
      writeJpeg('a.jpg');
      final importId = await metaRepo.importFolder(tmp.path);
      final photo = (await metaRepo.watchImport(importId).first).single;
      // A local rating the refresh must not clobber.
      await db.setRating(photo.id, 4);

      writeJpeg('new.jpg');
      final (
        :added,
        :removed,
        changedPaths: _,
        unavailable: _,
        unreadable: _,
      ) = await metaRepo.refreshImport(
        importId,
        tmp.path,
      );

      expect(added, 1);
      expect(removed, 0);
      final kept = (await metaRepo.watchImport(importId).first).firstWhere(
        (ph) => p.basename(ph.path) == 'a.jpg',
      );
      expect(kept.rating, 4);
    });

    test('reads marks for newly-appeared files', () async {
      final meta = MetadataRepository(db);
      final metaRepo = LibraryRepository(db, metadata: meta);
      writeJpeg('a.jpg');
      final importId = await metaRepo.importFolder(tmp.path);

      // A new file arrives that already carries a sidecar (rated in LR).
      writeJpeg('rated.jpg');
      await writeSidecar(
        p.join(tmp.path, 'rated.jpg'),
        const XmpData(rating: 5),
      );

      await metaRepo.refreshImport(importId, tmp.path);

      final rated = (await metaRepo.watchImport(importId).first).firstWhere(
        (ph) => p.basename(ph.path) == 'rated.jpg',
      );
      expect(rated.rating, 5);
    });
  });

  test('re-scan adopts a sidecar edited outside Cullimingo', () async {
    final meta = MetadataRepository(db);
    final metaRepo = LibraryRepository(db, metadata: meta);
    writeJpeg('a.jpg');
    final sidecar = stemSidecarPath(p.join(tmp.path, 'a.jpg'));
    // A sidecar already exists (rated 3 elsewhere) — import seeds it.
    await writeSidecar(p.join(tmp.path, 'a.jpg'), const XmpData(rating: 3));

    final importId = await metaRepo.importFolder(tmp.path);
    expect((await metaRepo.watchImport(importId).first).single.rating, 3);

    // Another app re-rates it to 5, leaving a newer mtime.
    await writeSidecar(p.join(tmp.path, 'a.jpg'), const XmpData(rating: 5));
    await File(
      sidecar,
    ).setLastModified(DateTime.now().add(const Duration(seconds: 5)));

    // What _backgroundResync runs when the folder is re-opened.
    final result = await meta.syncSidecarsFromDisk(importId);

    expect(result.updated, 1);
    expect((await metaRepo.watchImport(importId).first).single.rating, 5);
  });
}
