import 'dart:typed_data';

import 'package:cullimingo/core/cache/preview_cache.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/features/cull/presentation/cull_page.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/metadata/data/metadata_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NullExtractor implements PreviewExtractor {
  @override
  Future<Uint8List?> thumbnail(
    String path, {
    int longEdge = 512,
    CancelToken? cancel,
    JobPriority priority = JobPriority.visible,
  }) async => null;
}

class _NoopMetadata extends MetadataRepository {
  _NoopMetadata(super.db);

  @override
  Future<void> writeSidecarForPhoto(int photoId) async {}

  @override
  Future<void> writeSidecarsForPhotos(List<int> photoIds) async {}

  @override
  Future<void> applySidecarsForImport(int importId) async {}
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late int importId;

  Future<List<int>> pumpPage(
    WidgetTester tester, {
    required bool propagate,
  }) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        previewCacheProvider.overrideWithValue(
          PreviewCache(extractor: _NullExtractor()),
        ),
        metadataRepositoryProvider.overrideWithValue(_NoopMetadata(db)),
        propagateMarksToStackSeedProvider.overrideWithValue(propagate),
      ],
    );
    addTearDown(container.dispose);

    importId = await db.createImport(sourcePath: '/shoot');
    DateTime at(int s) =>
        DateTime(2026, 5, 29, 12, 44).add(Duration(seconds: s));
    await db.insertPhotos([
      // A detected 0 / +3 / −3 bracket.
      PhotosCompanion.insert(
        importId: Value(importId),
        path: '/shoot/DSCF0001.RAF',
        mtime: at(0),
        capturedAt: Value(at(0)),
        camera: const Value('Fujifilm X-H2S'),
        exposureBias: const Value(0),
        isRaw: const Value(true),
      ),
      PhotosCompanion.insert(
        importId: Value(importId),
        path: '/shoot/DSCF0002.RAF',
        mtime: at(1),
        capturedAt: Value(at(1)),
        camera: const Value('Fujifilm X-H2S'),
        exposureBias: const Value(3),
        isRaw: const Value(true),
      ),
      PhotosCompanion.insert(
        importId: Value(importId),
        path: '/shoot/DSCF0003.RAF',
        mtime: at(2),
        capturedAt: Value(at(2)),
        camera: const Value('Fujifilm X-H2S'),
        exposureBias: const Value(-3),
        isRaw: const Value(true),
      ),
    ]);
    container
        .read(workspaceProvider.notifier)
        .openImport(importId: importId, sourcePath: '/shoot', label: 'shoot');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CullPage()),
      ),
    );
    await tester.pump();
    await tester.pump();

    final photos = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    return photos!.map((p) => p.id).toList();
  }

  testWidgets('with propagation on, rating the reference marks the bracket', (
    tester,
  ) async {
    final ids = await pumpPage(tester, propagate: true);
    // Pick only the 0 EV reference frame.
    container.read(cullControllerProvider.notifier).setSelection({ids.first});
    await container.read(cullControllerProvider.notifier).applyRating(5);
    await tester.pump();

    final rows = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    expect(rows!.every((r) => r.rating == 5), isTrue);
  });

  testWidgets('with propagation off, only the picked frame is marked', (
    tester,
  ) async {
    final ids = await pumpPage(tester, propagate: false);
    container.read(cullControllerProvider.notifier).setSelection({ids.first});
    await container.read(cullControllerProvider.notifier).applyRating(5);
    await tester.pump();

    final rows = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    final rated = rows!.where((r) => r.rating == 5).map((r) => r.id).toList();
    expect(rated, [ids.first]);
  });
}
