import 'dart:typed_data';

import 'package:cullimingo/core/cache/preview_cache.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/files/open_external.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/features/cull/presentation/cull_page.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/widgets/photo_cell.dart';
import 'package:cullimingo/features/handoff/presentation/send_to_providers.dart';
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
    WidgetTester tester, {
    bool? contactSheetConfigured,
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
        if (contactSheetConfigured != null)
          contactSheetConfiguredProvider.overrideWith(
            (ref) async => contactSheetConfigured,
          ),
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

  testWidgets('ContactSheet rows appear when the connection is configured', (
    tester,
  ) async {
    // The page must keep contactSheetConfiguredProvider warm, or the first
    // menu after launch reads an unresolved future and hides these rows.
    await pumpGrid(tester, contactSheetConfigured: true);

    await tester.tap(find.byType(PhotoCell).first, buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text('Send to ContactSheet…'), findsOneWidget);
    expect(find.text('Pull marks from ContactSheet…'), findsOneWidget);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
  });

  testWidgets('ContactSheet rows are hidden when not configured', (
    tester,
  ) async {
    await pumpGrid(tester, contactSheetConfigured: false);

    await tester.tap(find.byType(PhotoCell).first, buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text(revealInFileManagerLabel), findsOneWidget); // menu is open
    expect(find.text('Send to ContactSheet…'), findsNothing);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
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

    // Close it (tap the barrier, away from the menu itself): the chain's
    // `_showContextMenuChain` loop only unregisters its global secondary-click
    // route once its menu actually closes — leaving it open here would leak
    // that route into whichever test runs next in this file.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'right-click inside an existing multi-selection keeps the selection',
    (tester) async {
      final (db, container, importId) = await pumpGrid(tester);
      final photos = await tester.runAsync(
        () => db.watchPhotosForImport(importId).first,
      );
      final ids = photos!.map((p) => p.id).toList();

      // Select both photos directly (mirrors a Shift/Ctrl-click multi-select),
      // then right-click one of the already-selected cells.
      container.read(cullControllerProvider.notifier)
        ..selectOnly(ids[0])
        ..toggleSelect(ids[1]);
      expect(container.read(cullControllerProvider).selectedIds, ids.toSet());

      await tester.tap(find.byType(PhotoCell).first, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      // The multi-selection must survive the right-click (bug: it used to
      // collapse to just the clicked cell before the context menu opened).
      expect(container.read(cullControllerProvider).selectedIds, ids.toSet());
      // (Two matches are expected: the toolbar's library-count label happens
      // to read the same for this 2-photo fixture, plus the menu's own
      // selection-count header.)
      expect(find.text('2 photos'), findsNWidgets(2));

      // Close it — see the cleanup note in the previous test.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Delete… on a multi-selection asks before deleting all of it', (
    tester,
  ) async {
    final (db, container, importId) = await pumpGrid(tester);
    final photos = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    final ids = photos!.map((p) => p.id).toList();

    container.read(cullControllerProvider.notifier)
      ..selectOnly(ids[0])
      ..toggleSelect(ids[1]);

    await tester.tap(find.byType(PhotoCell).first, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('2 photos'), findsNWidgets(2));

    // The menu has many entries and overflows the test viewport, so "Delete…"
    // (last, alone behind a divider) needs scrolling into view first.
    await tester.ensureVisible(find.text('Delete…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete…'));
    await tester.pumpAndSettle();

    // Confirmation names the whole selection, not just the clicked photo.
    expect(find.textContaining('Move 2 photos to the Trash?'), findsOneWidget);

    // Cancel must leave both rows and the selection untouched.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoCell), findsNWidgets(2));
    final remaining = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    expect(remaining, hasLength(2));
  });
}
