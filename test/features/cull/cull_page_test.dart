import 'package:cullimingo/core/cache/preview_cache.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/features/cull/presentation/cull_page.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/widgets/photo_cell.dart';
import 'package:cullimingo/features/metadata/data/metadata_repository.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Thumbnail source that always yields a placeholder — keeps the decode isolate
/// out of the widget test so the run is deterministic.
class _NullExtractor implements PreviewExtractor {
  @override
  Future<Uint8List?> thumbnail(
    String path, {
    int longEdge = 512,
    CancelToken? cancel,
    JobPriority priority = JobPriority.visible,
  }) async => null;
}

/// Metadata repo that skips sidecar file I/O (which can't progress under the
/// widget tester's fake async).
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
  testWidgets('end-to-end: grid renders, keyboard culls, filter applies', (
    tester,
  ) async {
    // Render at a realistic window size (the app enforces a 960px minimum), so
    // the toolbar's actions + size slider lay out as they do in production.
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
      ],
    );
    addTearDown(container.dispose);

    // Seed three photos directly (ascending capture time = known grid order).
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

    expect(find.byType(PhotoCell), findsNWidgets(3));

    Future<List<Photo>> rows() async =>
        (await tester.runAsync(() => db.watchPhotosForImport(importId).first))!;

    // The first key only establishes focus on the first photo; rate with the
    // second press.
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump();
    expect((await rows()).first.rating, 3);

    // Move to the second photo and flag it as a pick.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect((await rows())[1].flag, PickFlag.pick);

    // Space selects the focused (second) photo → export bar reflects the count.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.text('Export 1 Photo'), findsOneWidget);

    // Filtering to Picks leaves only the flagged photo in the grid.
    await tester.tap(find.textContaining('Picks'));
    await tester.pump();
    expect(find.byType(PhotoCell), findsOneWidget);
  });

  testWidgets('Cmd+A selects every photo in the grid', (tester) async {
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
        .openImport(
          importId: importId,
          sourcePath: '/shoot',
          label: 'shoot',
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CullPage()),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pump();

    expect(find.text('Export 3 Photos'), findsOneWidget);
  });

  testWidgets('rating/colour/flag keys toggle off when pressed twice', (
    tester,
  ) async {
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
      ],
    );
    addTearDown(container.dispose);

    final importId = await db.createImport(sourcePath: '/shoot');
    await db.insertPhotos([
      PhotosCompanion.insert(
        importId: Value(importId),
        path: '/shoot/DSC_0001.jpg',
        mtime: DateTime(2026, 6, 1, 10),
        capturedAt: Value(DateTime(2026, 6, 1, 10)),
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

    Future<Photo> first() async => (await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    ))!.first;

    await tester.sendKeyEvent(LogicalKeyboardKey.digit3); // focus first photo
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3); // → 3 stars
    await tester.pump();
    expect((await first()).rating, 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3); // same key clears it
    await tester.pump();
    expect((await first()).rating, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit6); // → red
    await tester.pump();
    expect((await first()).colorLabel, ColorLabel.red);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit6); // same key → cleared
    await tester.pump();
    expect((await first()).colorLabel, ColorLabel.none);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP); // → pick
    await tester.pump();
    expect((await first()).flag, PickFlag.pick);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP); // P again → cleared
    await tester.pump();
    expect((await first()).flag, PickFlag.none);
  });
}
