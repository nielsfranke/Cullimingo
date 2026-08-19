import 'package:cullimingo/core/cache/preview_cache.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/features/cull/presentation/cull_page.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/widgets/photo_cell.dart';
import 'package:cullimingo/features/metadata/data/metadata_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
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

/// Pointer handling for a multi-selection in the grid: a press that turns into
/// a drag-out (to Finder, or just a scroll) must keep every selected photo,
/// while a plain click inside the selection still collapses to the clicked one.
void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late List<int> ids;

  Future<void> pumpGrid(WidgetTester tester) async {
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
    ids = [for (final p in container.read(photosProvider).value!) p.id];
    container.read(cullControllerProvider.notifier).setSelection({
      ids[0],
      ids[1],
      ids[2],
    });
    await tester.pump();
  }

  Set<int> selection() => container.read(cullControllerProvider).selectedIds;

  // A right-click opens the thumbnail context menu, which installs a global
  // pointer route while it is up. Dismiss it before the test ends so the route
  // is removed with it instead of leaking into the next test.
  Future<void> closeMenu(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('press + move (drag-out) keeps the multi-selection', (
    tester,
  ) async {
    await pumpGrid(tester);
    expect(selection().length, 3);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PhotoCell).at(1)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(80, -40));
    await tester.pump();
    await gesture.up();
    // Drain the double-tap + prefetch-debounce timers so the frame settles.
    await tester.pump(const Duration(milliseconds: 400));

    expect(selection(), {ids[0], ids[1], ids[2]});
  });

  testWidgets('plain click inside the selection still collapses it', (
    tester,
  ) async {
    await pumpGrid(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PhotoCell).at(1)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect(selection(), {ids[1]});
  });

  testWidgets('a right-click cannot cash in a swallowed press', (tester) async {
    // A drag-out ends in the native drag session, so the pressed cell may never
    // see its pointer-up. That stale press must not collapse the selection when
    // the next release — here a right-click on another photo — comes in.
    await pumpGrid(tester);

    final drag = await tester.startGesture(
      tester.getCenter(find.byType(PhotoCell).at(1)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    // ...no matching up: the drag session took the pointer.

    final click = await tester.startGesture(
      tester.getCenter(find.byType(PhotoCell).at(2)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pump();
    await click.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect(selection(), {ids[0], ids[1], ids[2]});
    await drag.cancel();
    await tester.pump(const Duration(milliseconds: 400));
    await closeMenu(tester);
  });

  testWidgets('right-click inside the selection keeps it', (tester) async {
    await pumpGrid(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PhotoCell).at(1)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect(selection(), {ids[0], ids[1], ids[2]});
    await closeMenu(tester);
  });
}
