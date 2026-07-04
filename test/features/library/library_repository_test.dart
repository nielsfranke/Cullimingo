import 'dart:io';

import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/library/data/library_repository.dart';
import 'package:cullimingo/features/metadata/data/metadata_repository.dart';
import 'package:cullimingo/features/metadata/data/xmp_sidecar.dart';
import 'package:cullimingo/features/metadata/domain/xmp_data.dart';
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

  test('orders by EXIF capture time, not filename', () async {
    // Filename order (a, b) is the reverse of capture order.
    writeJpegAt('a_later.jpg', '2026:06:01 18:00:00');
    writeJpegAt('b_earlier.jpg', '2026:06:01 09:00:00');

    final importId = await repo.importFolder(tmp.path);
    final photos = await repo.watchImport(importId).first;

    expect(photos.map((p) => p.path.split('/').last).toList(), [
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
      'opening a parent claims files a subfolder import already owns',
      () async {
        final sub = Directory(p.join(tmp.path, 'sub'))..createSync();
        File(p.join(sub.path, 'a.jpg')).writeAsBytesSync(
          img.encodeJpg(img.Image(width: 8, height: 8)),
        );

        // Open the subfolder first — it claims the file.
        final subId = await repo.importFolder(sub.path);
        final subPhoto = (await repo.watchImport(subId).first).single;
        await db.setRating(
          subPhoto.id,
          5,
        ); // a mark that must survive re-parenting

        // Now open the parent recursively: it must show the same file (not the
        // empty grid `insertOrIgnore` used to leave), keeping the rating.
        final parentId = await repo.importFolder(tmp.path);
        final parentPhotos = await repo.watchImport(parentId).first;
        expect(parentPhotos, hasLength(1));
        expect(p.basename(parentPhotos.single.path), 'a.jpg');
        expect(parentPhotos.single.rating, 5);

        // Re-parented (one row per physical file), so the subfolder no longer
        // owns it.
        expect(await repo.watchImport(subId).first, isEmpty);
      },
    );

    test('reopening a folder left empty finally populates it', () async {
      // Simulate the DCIM case: a subfolder import owns the files, and a parent
      // import exists but empty. A refresh (what reopening triggers) heals it.
      final sub = Directory(p.join(tmp.path, 'sub'))..createSync();
      File(p.join(sub.path, 'a.jpg')).writeAsBytesSync(
        img.encodeJpg(img.Image(width: 8, height: 8)),
      );
      await repo.importFolder(sub.path); // subfolder claims the file
      final (parentId, _) = await repo.findOrCreateImport(tmp.path);
      expect(await repo.watchImport(parentId).first, isEmpty);

      final (added, removed) = await repo.refreshImport(parentId, tmp.path);
      expect(added, 1);
      expect(removed, 0);
      expect(await repo.watchImport(parentId).first, hasLength(1));
    });
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

      final (added, removed) = await repo.refreshImport(importId, tmp.path);

      expect(added, 1);
      expect(removed, 1);
      final names = (await repo.watchImport(importId).first)
          .map((ph) => p.basename(ph.path))
          .toSet();
      expect(names, {'b.jpg', 'c.jpg'});
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
      final (added, removed) = await metaRepo.refreshImport(
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
    final sidecar = sidecarPath(p.join(tmp.path, 'a.jpg'));
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
