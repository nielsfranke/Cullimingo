import 'dart:typed_data';

import 'package:cullimingo/core/cache/preview_cache.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/metadata/data/metadata_repository.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Skips sidecar file I/O but records which photos were flushed, so the tests
/// can assert an undo mirrors to XMP like a fresh mark.
class _RecordingMetadata extends MetadataRepository {
  _RecordingMetadata(super.db);

  final List<int> sidecarWrites = [];

  @override
  Future<void> writeSidecarForPhoto(int photoId) async {
    sidecarWrites.add(photoId);
  }

  @override
  Future<void> writeSidecarsForPhotos(List<int> photoIds) async {
    sidecarWrites.addAll(photoIds);
  }
}

class _NullExtractor implements PreviewExtractor {
  @override
  Future<Uint8List?> thumbnail(
    String path, {
    int longEdge = 512,
    CancelToken? cancel,
    JobPriority priority = JobPriority.visible,
  }) async => null;
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late _RecordingMetadata metadata;
  late List<int> ids;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    metadata = _RecordingMetadata(db);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        metadataRepositoryProvider.overrideWithValue(metadata),
        previewCacheProvider.overrideWithValue(
          PreviewCache(extractor: _NullExtractor()),
        ),
      ],
    );
    final importId = await db.createImport(sourcePath: '/shoot');
    await db.insertPhotos([
      for (var i = 1; i <= 4; i++)
        PhotosCompanion.insert(
          importId: Value(importId),
          path: '/shoot/DSC_000$i.jpg',
          mtime: DateTime(2026, 6, 1, 10, i),
          capturedAt: Value(DateTime(2026, 6, 1, 10, i)),
        ),
    ]);
    ids = (await db.watchPhotosForImport(importId).first)
        .map((p) => p.id)
        .toList();
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  CullController controller() =>
      container.read(cullControllerProvider.notifier);

  Future<Photo> row(int id) async =>
      (await db.watchPhotosForImport(1).first).firstWhere((r) => r.id == id);

  test('undo reverts a batch rating in one step; redo re-applies it', () async {
    await controller().setRating(ids[0], 2); // pre-existing distinct value
    controller()
      ..selectOnly(ids[0])
      ..toggleSelect(ids[1]);
    await controller().applyRating(5);
    expect((await row(ids[0])).rating, 5);
    expect((await row(ids[1])).rating, 5);

    // One undo takes back the whole batch, restoring per-photo old values.
    expect(await controller().undo(), 'rating (2 photos)');
    expect((await row(ids[0])).rating, 2);
    expect((await row(ids[1])).rating, 0);

    expect(await controller().redo(), 'rating (2 photos)');
    expect((await row(ids[0])).rating, 5);
    expect((await row(ids[1])).rating, 5);
  });

  test('undo walks flag and colour changes newest-first', () async {
    controller().selectOnly(ids[2]);
    await controller().applyFlag(PickFlag.reject);
    await controller().applyColor(ColorLabel.red);

    expect(await controller().undo(), 'colour label');
    expect((await row(ids[2])).colorLabel, ColorLabel.none);
    expect((await row(ids[2])).flag, PickFlag.reject);

    expect(await controller().undo(), 'flag');
    expect((await row(ids[2])).flag, PickFlag.none);

    expect(await controller().undo(), isNull);
  });

  test('a fresh mark after undo clears the redo side', () async {
    controller().selectOnly(ids[0]);
    await controller().applyRating(4);
    await controller().undo();
    await controller().applyRating(1);

    expect(await controller().redo(), isNull);
    expect((await row(ids[0])).rating, 1);
  });

  test('undo reverses a rotation via the inverse turn', () async {
    // The paths don't exist on disk, so rotate takes the widget-delta branch.
    controller()
      ..selectOnly(ids[0])
      ..toggleSelect(ids[1]);
    await controller().applyRotation(1);
    expect((await row(ids[0])).userRotation, 1);

    expect(await controller().undo(), 'rotation (2 photos)');
    expect((await row(ids[0])).userRotation, 0);
    expect((await row(ids[1])).userRotation, 0);

    expect(await controller().redo(), 'rotation (2 photos)');
    expect((await row(ids[1])).userRotation, 1);
  });

  test('undoing a batch costs one photos-stream emit', () async {
    controller()
      ..selectOnly(ids[0])
      ..toggleSelect(ids[1])
      ..toggleSelect(ids[2]);
    await controller().applyRating(5);

    final emissions = <int>[];
    final sub = db
        .watchPhotosForImport(1)
        .listen((rows) => emissions.add(rows.length));
    addTearDown(sub.cancel);
    await pumpEventQueue();
    final before = emissions.length;

    await controller().undo(); // per-photo old values, one transaction
    await pumpEventQueue();

    expect(emissions.length, before + 1);
  });

  test('undo mirrors the restored marks to the sidecars', () async {
    controller().selectOnly(ids[3]);
    await controller().applyRating(3);
    metadata.sidecarWrites.clear();

    await controller().undo();
    expect(metadata.sidecarWrites, [ids[3]]);
  });

  test('marking a vanished photo id records nothing', () async {
    controller().restore(const CullSelection(focusedId: 999999));
    await controller().applyRating(5);
    expect(await controller().undo(), isNull);
  });
}
