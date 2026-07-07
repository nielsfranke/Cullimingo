import 'dart:io';
import 'dart:typed_data';

import 'package:cullimingo/core/cache/preview_cache.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/metadata/data/metadata_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:exif/exif.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Skips sidecar file I/O — the seeded photos have no real files on disk.
class _NoopMetadata extends MetadataRepository {
  _NoopMetadata(super.db);

  @override
  Future<void> writeSidecarForPhoto(int photoId) async {}

  @override
  Future<void> writeSidecarsForPhotos(List<int> photoIds) async {}
}

/// Yields no bytes — the rotate test only cares about the commit branch, not
/// the re-decoded preview.
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
  late List<int> ids;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        metadataRepositoryProvider.overrideWithValue(_NoopMetadata(db)),
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
  CullSelection state() => container.read(cullControllerProvider);

  test('selectOnly replaces the selection and sets focus + anchor', () {
    controller()
      ..selectOnly(ids[2])
      ..selectOnly(ids[0]);
    expect(state().selectedIds, {ids[0]});
    expect(state().focusedId, ids[0]);
    expect(state().anchorId, ids[0]);
  });

  test('⌘-click toggle adds and removes', () {
    controller()
      ..selectOnly(ids[0])
      ..toggleSelect(ids[2]);
    expect(state().selectedIds, {ids[0], ids[2]});
    controller().toggleSelect(ids[2]);
    expect(state().selectedIds, {ids[0]});
  });

  test('Shift-range selects the span from the anchor in grid order', () {
    controller()
      ..selectOnly(ids[1]) // anchor at index 1
      ..extendSelectionTo(ids[3], ids); // to index 3
    expect(state().selectedIds, {ids[1], ids[2], ids[3]});
    expect(state().focusedId, ids[3]);
    expect(state().anchorId, ids[1]); // anchor unchanged
  });

  test('markTargets is the selection only when the focus is part of it', () {
    controller()
      ..selectOnly(ids[0])
      ..toggleSelect(ids[1]); // focus now ids[1], both selected
    expect(state().markTargets, {ids[0], ids[1]});

    // Navigating away (focus only) drops back to the single focused photo.
    controller().focus(ids[3]);
    expect(state().markTargets, {ids[3]});
  });

  test('a click inside a multi-selection defers its collapse', () {
    controller()
      ..selectOnly(ids[0])
      ..toggleSelect(ids[1])
      ..toggleSelect(ids[2]); // {0,1,2}

    // Pressing an already-selected photo must not collapse yet — a drag-out
    // from this press has to carry the whole selection.
    controller().beginPendingCollapse(ids[0]);
    expect(state().selectedIds, {ids[0], ids[1], ids[2]});

    // A drag cancels the pending collapse; the selection stays intact even
    // after a (now no-op) commit.
    controller()
      ..cancelPendingCollapse()
      ..commitPendingCollapse();
    expect(state().selectedIds, {ids[0], ids[1], ids[2]});

    // A plain click (no drag) commits on release: collapse to the clicked one.
    controller()
      ..beginPendingCollapse(ids[0])
      ..commitPendingCollapse();
    expect(state().selectedIds, {ids[0]});
    expect(state().focusedId, ids[0]);
  });

  test('pruneMissing drops deleted ids but keeps the rest selected', () {
    controller()
      ..selectOnly(ids[0])
      ..toggleSelect(ids[1])
      ..toggleSelect(ids[2]);
    controller().pruneMissing({ids[2], ids[3]}); // focus/anchor were ids[2]

    expect(state().selectedIds, {ids[0], ids[1]});
    expect(state().focusedId, isNull);
    expect(state().anchorId, isNull);

    // Ids not in the removed set are untouched.
    controller().focus(ids[0]);
    controller().pruneMissing({ids[3]});
    expect(state().focusedId, ids[0]);
  });

  test('applyRating batches across the whole selection', () async {
    controller()
      ..selectOnly(ids[0])
      ..toggleSelect(ids[1])
      ..toggleSelect(ids[2]);
    await controller().applyRating(5);

    final rows = await db.watchPhotosForImport(1).first;
    final rated = rows.where((r) => r.rating == 5).map((r) => r.id).toSet();
    expect(rated, {ids[0], ids[1], ids[2]});
    expect(rows.firstWhere((r) => r.id == ids[3]).rating, 0);
  });

  test(
    'a batch mark costs one photos-stream emit, not one per photo',
    () async {
      final emissions = <int>[];
      final sub = db
          .watchPhotosForImport(1)
          .listen((rows) => emissions.add(rows.length));
      addTearDown(sub.cancel);
      await pumpEventQueue();
      final before = emissions.length;

      controller()
        ..selectOnly(ids[0])
        ..toggleSelect(ids[1])
        ..toggleSelect(ids[2]);
      await controller().applyRating(5);
      await pumpEventQueue();

      expect(emissions.length, before + 1);
    },
  );

  test(
    'applyRotation accumulates and wraps user rotation across a batch',
    () async {
      Future<int> rotationOf(int id) async =>
          (await db.watchPhotosForImport(1).first)
              .firstWhere((r) => r.id == id)
              .userRotation;

      controller()
        ..selectOnly(ids[0])
        ..toggleSelect(ids[1]);
      await controller().applyRotation(1); // 0 → 1
      await controller().applyRotation(1); // 1 → 2
      expect(await rotationOf(ids[0]), 2);
      expect(await rotationOf(ids[1]), 2);

      // A counter-clockwise turn on a single photo wraps 0 → 3.
      controller().selectOnly(ids[3]);
      await controller().applyRotation(-1);
      expect(await rotationOf(ids[3]), 3);
      // An untouched photo stays at 0.
      expect(await rotationOf(ids[2]), 0);
    },
  );

  test(
    'rotating a real JPEG commits into its EXIF (no widget delta)',
    () async {
      final tmp = await Directory.systemTemp.createTemp('cullimingo_rotate');
      addTearDown(() => tmp.delete(recursive: true));
      final image = img.Image(width: 8, height: 6);
      image.exif.imageIfd['Orientation'] = 1;
      final path = p.join(tmp.path, 'DSC_9999.JPG');
      File(path).writeAsBytesSync(img.encodeJpg(image));

      final importId = await db.createImport(sourcePath: tmp.path);
      await db.insertPhotos([
        PhotosCompanion.insert(
          importId: Value(importId),
          path: path,
          mtime: DateTime(2026, 6, 2),
          orientation: const Value(1),
        ),
      ]);
      final id = (await db.watchPhotosForImport(importId).first).single.id;

      await container.read(cullControllerProvider.notifier).rotate(id, 1);

      final row = (await db.watchPhotosForImport(importId).first).single;
      // The rotation is baked into orientation (1 → 6), not left as a delta.
      expect(row.orientation, 6);
      expect(row.userRotation, 0);
      // …and the file's own EXIF now carries it.
      final tags = await readExifFromFile(File(path));
      expect(tags['Image Orientation']?.values.toList().first, 6);
    },
  );
}
