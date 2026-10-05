import 'package:cullimingo/core/cache/preview_cache.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/features/cull/presentation/cull_page.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/filter/presentation/filter_providers.dart';
import 'package:cullimingo/features/metadata/data/metadata_repository.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// Two RAF+JPG pairs (GitHub #12). Returns the ids in grid order (capture
  /// time, then path: each JPG sorts before its RAF).
  Future<List<int>> pumpPage(
    WidgetTester tester, {
    required bool propagate,
    bool autoAdvance = false,
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
        propagateMarksToPairSeedProvider.overrideWithValue(propagate),
        autoAdvanceAfterMarkSeedProvider.overrideWithValue(autoAdvance),
      ],
    );
    addTearDown(container.dispose);

    importId = await db.createImport(sourcePath: '/shoot');
    DateTime at(int s) => DateTime(2026, 10, 5, 12).add(Duration(minutes: s));
    PhotosCompanion photo(String name, int minute, {required bool isRaw}) =>
        PhotosCompanion.insert(
          importId: Value(importId),
          path: '/shoot/$name',
          mtime: at(minute),
          capturedAt: Value(at(minute)),
          camera: const Value('Fujifilm X-T5'),
          isRaw: Value(isRaw),
        );
    await db.insertPhotos([
      photo('DSCF8912.RAF', 0, isRaw: true),
      photo('DSCF8912.JPG', 0, isRaw: false),
      photo('DSCF8913.RAF', 1, isRaw: true),
      photo('DSCF8913.JPG', 1, isRaw: false),
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

    return container.read(filteredPhotosProvider).map((p) => p.id).toList();
  }

  Future<Set<int>> picked(WidgetTester tester) async {
    final rows = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    return {
      for (final r in rows!)
        if (r.flag == PickFlag.pick) r.id,
    };
  }

  for (final propagate in [true, false]) {
    testWidgets('picking the RAW with pair propagation '
        '${propagate ? 'on picks its JPEG too' : 'off picks just the RAW'}', (
      tester,
    ) async {
      final ids = await pumpPage(tester, propagate: propagate);
      final raw = ids[1]; // DSCF8912.RAF
      container.read(cullControllerProvider.notifier).setSelection({raw});
      await container
          .read(cullControllerProvider.notifier)
          .applyFlag(PickFlag.pick);
      await tester.pump();

      expect(await picked(tester), propagate ? {ids[0], raw} : {raw});
    });
  }

  testWidgets('auto-advance skips the twin the mark just landed on', (
    tester,
  ) async {
    final ids = await pumpPage(tester, propagate: true, autoAdvance: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // focus first (JPG)
    await tester.pump();
    expect(container.read(cullControllerProvider).focusedId, ids[0]);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(await picked(tester), {ids[0], ids[1]});
    // Straight past DSCF8912.RAF to the next shot.
    expect(container.read(cullControllerProvider).focusedId, ids[2]);
  });
}
