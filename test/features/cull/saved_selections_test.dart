import 'package:cullimingo/core/cache/preview_cache.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/features/cull/presentation/cull_page.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/metadata/data/metadata_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// No bytes → placeholder cells; keeps the decode isolate out of the test.
class _NullExtractor implements PreviewExtractor {
  @override
  Future<Uint8List?> thumbnail(
    String path, {
    int longEdge = 512,
    CancelToken? cancel,
    JobPriority priority = JobPriority.visible,
  }) async => null;
}

/// Skips sidecar file I/O (can't progress under the tester's fake async).
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

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
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
  }

  testWidgets('save the current selection by name, then reload it', (
    tester,
  ) async {
    await pumpPage(tester);

    final photoIds = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    final ids = photoIds!.map((p) => p.id).toList();

    // Build a selection of the first two photos.
    container.read(cullControllerProvider.notifier).setSelection(
      {ids[0], ids[1]},
    );
    await tester.pump();

    // Open the bookmark menu → "Save current selection…".
    await tester.tap(find.byTooltip('Saved selections'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save current selection…'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'My picks',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = await tester.runAsync(
      () => db.watchSavedSelections(importId).first,
    );
    expect(saved!.single.name, 'My picks');
    expect(saved.single.photoIds, [ids[0], ids[1]]);

    // The bookmark icon now shows the "has saved selections" indicator (the
    // filled bookmark replaces the outline).
    await tester.pump();
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border), findsNothing);

    // Clear the selection, then reload the saved one from the menu.
    container.read(cullControllerProvider.notifier).setSelection({});
    await tester.pump();

    await tester.tap(find.byTooltip('Saved selections'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My picks (2)'));
    await tester.pumpAndSettle();

    expect(
      container.read(cullControllerProvider).selectedIds,
      {ids[0], ids[1]},
    );
  });
}
