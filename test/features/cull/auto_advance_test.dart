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
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Placeholder thumbnails — keeps the decode isolate out of the widget test.
class _NullExtractor implements PreviewExtractor {
  @override
  Future<Uint8List?> thumbnail(
    String path, {
    int longEdge = 512,
    CancelToken? cancel,
    JobPriority priority = JobPriority.visible,
  }) async => null;
}

/// Metadata repo that skips sidecar file I/O (can't progress under fake async).
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
  // Builds a 3-photo grid; [autoAdvance] seeds the setting. Returns the
  // container so tests can read focus/selection state and the photo ids in
  // grid order.
  Future<(ProviderContainer, List<int>)> pumpGrid(
    WidgetTester tester, {
    required bool autoAdvance,
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        previewCacheProvider.overrideWithValue(
          PreviewCache(extractor: _NullExtractor()),
        ),
        metadataRepositoryProvider.overrideWithValue(_NoopMetadata(db)),
        autoAdvanceAfterMarkSeedProvider.overrideWithValue(autoAdvance),
      ],
    );
    addTearDown(container.dispose);

    final importId = await db.createImport(sourcePath: '/shoot');
    await db.insertPhotos([
      for (var i = 1; i <= 3; i++)
        PhotosCompanion.insert(
          importId: Value(importId),
          path: '/shoot/DSC_000$i.jpg',
          mtime: DateTime(2026, 6, 1, 10, i),
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
    await tester.pump(); // photos stream emits
    await tester.pump(); // grid builds its cells

    final ids = [
      for (final p in container.read(filteredPhotosProvider)) p.id,
    ];
    return (container, ids);
  }

  int? focusOf(ProviderContainer c) => c.read(cullControllerProvider).focusedId;

  testWidgets('off by default: rating keeps focus on the same photo', (
    tester,
  ) async {
    final (container, ids) = await pumpGrid(tester, autoAdvance: false);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit3); // focus first photo
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3); // rate it 3
    await tester.pump();

    expect(focusOf(container), ids.first, reason: 'focus should not advance');
  });

  testWidgets('on: rating a single photo advances focus to the next', (
    tester,
  ) async {
    final (container, ids) = await pumpGrid(tester, autoAdvance: true);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit3); // focus first photo
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3); // rate → advance
    await tester.pump();
    expect(focusOf(container), ids[1]);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP); // flag → advance
    await tester.pump();
    expect(focusOf(container), ids[2]);
  });

  testWidgets('on: does not advance past the last photo', (tester) async {
    final (container, ids) = await pumpGrid(tester, autoAdvance: true);

    // Walk focus to the last photo, then rate it.
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3); // focus first
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3); // rate → to [1]
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3); // rate → to [2]
    await tester.pump();
    expect(focusOf(container), ids[2]);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit3); // rate last → stays
    await tester.pump();
    expect(focusOf(container), ids[2]);
  });

  testWidgets('on: a batch mark (multi-selection) does not advance', (
    tester,
  ) async {
    final (container, ids) = await pumpGrid(tester, autoAdvance: true);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit3); // focus first
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space); // select [0]
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // focus [1]
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space); // select [1]
    await tester.pump();
    expect(container.read(cullControllerProvider).selectedIds, {
      ids[0],
      ids[1],
    });

    await tester.sendKeyEvent(LogicalKeyboardKey.digit3); // batch rate
    await tester.pump();
    expect(
      focusOf(container),
      ids[1],
      reason: 'batch marking should keep focus put',
    );
  });
}
