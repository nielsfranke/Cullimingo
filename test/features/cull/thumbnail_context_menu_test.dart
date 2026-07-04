import 'dart:typed_data';

import 'package:cullimingo/core/cache/preview_cache.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/files/open_external.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/features/cull/presentation/cull_page.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/widgets/photo_cell.dart';
import 'package:cullimingo/features/metadata/data/metadata_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
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
  // Pumps a two-photo grid and returns (db, container, importId).
  Future<(AppDatabase, ProviderContainer, int)> pumpGrid(
    WidgetTester tester,
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
      for (var i = 1; i <= 2; i++)
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
    await tester.pump();
    await tester.pump();
    return (db, container, importId);
  }

  testWidgets('right-click a cell shows the menu and rates it', (tester) async {
    final (db, _, importId) = await pumpGrid(tester);

    // Right-click the first thumbnail.
    await tester.tap(find.byType(PhotoCell).first, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text(revealInFileManagerLabel), findsOneWidget);
    // The metadata editor + rotate actions are reachable from the menu.
    expect(find.text('Edit metadata…'), findsOneWidget);
    expect(find.text('Rotate left'), findsOneWidget);
    expect(find.text('Rotate right'), findsOneWidget);

    // Rate it 3 from the menu's star palette.
    await tester.tap(find.byTooltip('Rate 3'));
    await tester.pumpAndSettle();

    final rows = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    expect(rows!.first.rating, 3);
  });

  testWidgets('right-click another cell moves the open menu to it', (
    tester,
  ) async {
    final (db, container, importId) = await pumpGrid(tester);
    final photos = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    final ids = photos!.map((p) => p.id).toList();

    // Open the menu on the first cell (selects photo 1).
    await tester.tap(find.byType(PhotoCell).first, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text(revealInFileManagerLabel), findsOneWidget);
    expect(container.read(cullControllerProvider).selectedIds, {ids[0]});

    // A single right-click on the *second* cell (over the menu's barrier)
    // should close the first menu and reopen on the second — no double click.
    await tester.tap(
      find.byType(PhotoCell).at(1),
      buttons: kSecondaryButton,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    // The menu is still open, now targeting photo 2.
    expect(find.text(revealInFileManagerLabel), findsOneWidget);
    expect(container.read(cullControllerProvider).selectedIds, {ids[1]});
  });
}
