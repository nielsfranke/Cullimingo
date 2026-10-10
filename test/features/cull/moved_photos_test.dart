import 'dart:io';

import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/cull/data/moved_photos.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;
  late Directory shoot;
  late int importId;

  String photo(int i) => p.join(shoot.path, 'DSC_000$i.ARW');

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    shoot = Directory.systemTemp.createTempSync('cm_moved');
    importId = await db.createImport(sourcePath: shoot.path);
    await db.insertPhotos([
      for (var i = 1; i <= 3; i++)
        PhotosCompanion.insert(
          importId: Value(importId),
          path: photo(i),
          mtime: DateTime(2026, 10, 1, 10, i),
        ),
    ]);
    for (var i = 1; i <= 3; i++) {
      File(photo(i)).writeAsStringSync('raw $i');
    }
  });

  tearDown(() async {
    await db.close();
    shoot.deleteSync(recursive: true);
  });

  test('drops only the moved photos whose original is gone (#14)', () async {
    // 1 moved away; 2 was part of the move but failed, so it's still there.
    File(photo(1)).deleteSync();

    final gone = await forgetMovedPhotos(
      db: db,
      importId: importId,
      sources: [photo(1), photo(2)],
    );

    expect(gone, [photo(1)]);
    final remaining = await db.watchPhotosForImport(importId).first;
    expect(remaining.map((r) => r.path), [photo(2), photo(3)]);
  });
}
