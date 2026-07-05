import 'dart:typed_data';

import 'package:cullimingo/core/cache/preview_cache.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/features/cull/presentation/cull_page.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/filter/presentation/filter_providers.dart';
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

  Future<List<int>> pumpPage(WidgetTester tester) async {
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
      ],
    );
    addTearDown(container.dispose);

    importId = await db.createImport(sourcePath: '/shoot');
    await db.insertPhotos([
      for (var i = 1; i <= 3; i++)
        PhotosCompanion.insert(
          importId: Value(importId),
          path: '/shoot/IMG_000$i.jpg',
          mtime: DateTime(2026, 6, 1, 10, i),
          // Deliberately no exposure data → detection would never group these.
          capturedAt: Value(DateTime(2026, 6, 1, 10, i)),
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

  testWidgets('stacking unrelated photos forms one manual bracket', (
    tester,
  ) async {
    final ids = await pumpPage(tester);
    expect(container.read(bracketGroupsProvider).bracketCount, 0);

    container.read(cullControllerProvider.notifier).setSelection(ids.toSet());
    await container.read(cullControllerProvider.notifier).stackSelection();
    await tester.pump();

    final groups = container.read(bracketGroupsProvider);
    expect(groups.bracketCount, 1);
    expect(groups.memberIds, ids.toSet());

    // The override persisted to the DB with a shared non-empty id.
    final rows = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    final stackIds = rows!.map((r) => r.stackId).toSet();
    expect(stackIds, hasLength(1));
    expect(stackIds.single, isNotNull);
    expect(stackIds.single, isNotEmpty);

    // Undo restores the previous (null) override and dissolves the stack.
    await container.read(cullControllerProvider.notifier).undo();
    await tester.pump();
    expect(container.read(bracketGroupsProvider).bracketCount, 0);
    final reverted = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    expect(reverted!.every((r) => r.stackId == null), isTrue);
  });

  testWidgets('unstacking removes the override (empty-string sentinel)', (
    tester,
  ) async {
    final ids = await pumpPage(tester);
    container.read(cullControllerProvider.notifier).setSelection(ids.toSet());
    await container.read(cullControllerProvider.notifier).stackSelection();
    await tester.pump();
    expect(container.read(bracketGroupsProvider).bracketCount, 1);

    // Now unstack all three.
    container.read(cullControllerProvider.notifier).setSelection(ids.toSet());
    await container.read(cullControllerProvider.notifier).unstackSelection();
    await tester.pump();

    expect(container.read(bracketGroupsProvider).bracketCount, 0);
    final rows = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    expect(rows!.every((r) => r.stackId == ''), isTrue);
  });
}
