import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/files/move_to_trash.dart';
import 'package:cullimingo/features/cull/data/reject_deleter.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late int importId;
  late List<Photo> photos;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    importId = await db.createImport(sourcePath: '/shoot');
    await db.insertPhotos([
      for (var i = 1; i <= 4; i++)
        PhotosCompanion.insert(
          importId: Value(importId),
          path: '/shoot/DSC_000$i.ARW',
          mtime: DateTime(2026, 6, 1, 10, i),
          flag: Value(i <= 2 ? PickFlag.reject : PickFlag.none),
        ),
    ]);
    photos = await db.watchPhotosForImport(importId).first;
  });

  tearDown(() => db.close());

  List<Photo> rejects() =>
      photos.where((p) => p.flag == PickFlag.reject).toList();

  test('trashes each reject with its sidecar and drops the rows', () async {
    late List<String> trashedPaths;
    final result = await deleteRejectedPhotos(
      db: db,
      importId: importId,
      rejects: rejects(),
      trash: (paths, {onProgress}) async {
        trashedPaths = paths;
        return TrashResult(trashed: paths.length, failed: const []);
      },
    );

    expect(result.deleted, 2);
    expect(result.failedPaths, isEmpty);
    // Photo + .xmp sidecar per reject, pairwise.
    expect(trashedPaths, [
      '/shoot/DSC_0001.ARW',
      '/shoot/DSC_0001.xmp',
      '/shoot/DSC_0002.ARW',
      '/shoot/DSC_0002.xmp',
    ]);

    final remaining = await db.watchPhotosForImport(importId).first;
    expect(remaining.map((p) => p.path), [
      '/shoot/DSC_0003.ARW',
      '/shoot/DSC_0004.ARW',
    ]);
  });

  test('a photo the OS refused to trash keeps its row and marks', () async {
    final result = await deleteRejectedPhotos(
      db: db,
      importId: importId,
      rejects: rejects(),
      trash: (paths, {onProgress}) async => TrashResult(
        trashed: paths.length - 1,
        failed: const ['/shoot/DSC_0001.ARW'],
      ),
    );

    expect(result.deleted, 1);
    expect(result.failedPaths, ['/shoot/DSC_0001.ARW']);

    final remaining = await db.watchPhotosForImport(importId).first;
    expect(remaining.map((p) => p.path), contains('/shoot/DSC_0001.ARW'));
    expect(
      remaining.firstWhere((p) => p.path == '/shoot/DSC_0001.ARW').flag,
      PickFlag.reject, // marks survive with the row
    );
    expect(
      remaining.map((p) => p.path),
      isNot(contains('/shoot/DSC_0002.ARW')),
    );
  });

  test('a failed sidecar alone does not keep the photo row', () async {
    final result = await deleteRejectedPhotos(
      db: db,
      importId: importId,
      rejects: rejects(),
      trash: (paths, {onProgress}) async => TrashResult(
        trashed: paths.length - 1,
        failed: const ['/shoot/DSC_0001.xmp'],
      ),
    );

    expect(result.deleted, 2);
    expect(result.failedPaths, isEmpty);
  });

  test('a run-level trash error deletes nothing and surfaces', () async {
    final result = await deleteRejectedPhotos(
      db: db,
      importId: importId,
      rejects: rejects(),
      trash: (paths, {onProgress}) async => TrashResult(
        trashed: 0,
        failed: paths,
        error: '`gio` was not found',
      ),
    );

    expect(result.deleted, 0);
    expect(result.error, contains('gio'));
    final remaining = await db.watchPhotosForImport(importId).first;
    expect(remaining, hasLength(4));
  });

  test('no rejects is a clean no-op', () async {
    final result = await deleteRejectedPhotos(
      db: db,
      importId: importId,
      rejects: const [],
      trash: (paths, {onProgress}) async =>
          fail('trash must not run for an empty list'),
    );
    expect(result.deleted, 0);
    expect(result.error, isNull);
  });
}
