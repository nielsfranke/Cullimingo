import 'package:cullimingo/core/cache/preview_cache.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/files/open_external.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/features/cull/presentation/cull_page.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/widgets/loupe_view.dart';
import 'package:cullimingo/features/cull/presentation/widgets/photo_cell.dart';
import 'package:cullimingo/features/metadata/data/metadata_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Yields no bytes, so the loupe shows its placeholder — keeps the decode
/// isolate out of the widget test (the loupe behaviour is what we're testing).
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

  testWidgets('Enter opens the loupe, [/] blits, Esc closes', (tester) async {
    await pumpPage(tester);
    expect(find.byType(LoupeView), findsNothing);

    // First Enter establishes focus on the first photo; second opens the loupe.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byType(LoupeView), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);

    // `]` moves to the next photo; the position indicator follows.
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);

    // Esc returns to the grid.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(LoupeView), findsNothing);
  });

  testWidgets('cull keys still work inside the loupe', (tester) async {
    await pumpPage(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // focus first
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // open loupe
    await tester.pump();
    expect(find.byType(LoupeView), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.pump();

    final rows = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    expect(rows!.first.rating, 4);
  });

  testWidgets('loupe rating buttons set the rating with a click', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // focus first
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // open loupe
    await tester.pump();

    await tester.tap(find.byTooltip('Rate 3'));
    await tester.pump();

    final rows = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    expect(rows!.first.rating, 3);

    // Clicking the active rating again clears it (toggle).
    await tester.tap(find.byTooltip('Rate 3'));
    await tester.pump();
    final after = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    expect(after!.first.rating, 0);
  });

  testWidgets('loupe toolbar rotates the shown photo', (tester) async {
    await pumpPage(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // focus first
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // open loupe
    await tester.pump();

    expect(find.byTooltip('Rotate left'), findsOneWidget);
    expect(find.byTooltip('Edit metadata (M)'), findsOneWidget);

    await tester.tap(find.byTooltip('Rotate right'));
    await tester.pump();
    final rows = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    expect(rows!.first.userRotation, 1);
  });

  testWidgets('the analysis menu toggles histogram/clipping/peaking', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // focus first
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // open loupe
    await tester.pump();

    expect(find.byTooltip('Analysis overlays'), findsOneWidget);

    // Open the menu and confirm all three overlays are listed, initially off.
    await tester.tap(find.byTooltip('Analysis overlays'));
    await tester.pumpAndSettle();
    expect(find.text('Histogram'), findsOneWidget);
    expect(find.text('Clipping warnings'), findsOneWidget);
    expect(find.text('Focus peaking'), findsOneWidget);
    expect(
      container.read(loupeHistogramVisibleProvider),
      isFalse,
    );

    // Toggling one flips its provider state (the menu closes on selection —
    // matching the existing sort menu's behaviour).
    await tester.tap(find.text('Histogram'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(container.read(loupeHistogramVisibleProvider), isTrue);

    // Toggling clipping and peaking works the same way, independently.
    await tester.tap(find.byTooltip('Analysis overlays'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Focus peaking'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(container.read(loupeFocusPeakingVisibleProvider), isTrue);
    expect(container.read(loupeClippingVisibleProvider), isFalse);
  });

  testWidgets('right-click in the loupe opens the context menu', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // focus first
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // open loupe
    await tester.pump();

    await tester.tap(
      find.byType(LoupeView),
      buttons: kSecondaryButton,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.text(revealInFileManagerLabel), findsOneWidget);
    expect(find.text('Edit metadata…'), findsOneWidget);
  });

  testWidgets('loupe shows a toggle for a cropped photo', (tester) async {
    await pumpPage(tester);
    // Mark the first photo as carrying a Lightroom crop.
    await tester.runAsync(
      () =>
          (db.update(
            db.photos,
          )..where((t) => t.path.equals('/shoot/DSC_0001.jpg'))).write(
            const PhotosCompanion(
              hasCrop: Value(true),
              cropLeft: Value(0.1),
              cropTop: Value(0.1),
              cropRight: Value(0.9),
              cropBottom: Value(0.9),
            ),
          ),
    );
    await tester.pump(); // stream re-emits the cropped row

    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // focus first
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // open loupe
    await tester.pump();

    expect(find.byTooltip('Hide crop outline'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide crop outline'));
    await tester.pump();
    expect(find.byTooltip('Show crop outline'), findsOneWidget);
  });

  testWidgets('loupe shows a play affordance for a video file', (
    tester,
  ) async {
    await pumpPage(tester);
    await db.insertPhotos([
      PhotosCompanion.insert(
        importId: Value(importId),
        path: '/shoot/DSC_0004.mov',
        mtime: DateTime(2026, 6, 1, 10, 4),
        capturedAt: Value(DateTime(2026, 6, 1, 10, 4)),
      ),
    ]);
    await tester.pump(); // stream re-emits with the video row

    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // focus first
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // open loupe
    await tester.pump();
    expect(find.byTooltip('Open in system player'), findsNothing);

    // Blit to the video (4th photo).
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.pump();
    expect(find.text('4 / 4'), findsOneWidget);
    expect(find.byTooltip('Open in system player'), findsOneWidget);
  });

  testWidgets('double-tap a cell opens the loupe on it', (tester) async {
    await pumpPage(tester);
    expect(find.byType(LoupeView), findsNothing);

    // Second cell (DSC_0002) → loupe should show "2 / 3".
    await tester.tap(find.byType(PhotoCell).at(1));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(PhotoCell).at(1));
    // Drain the double-tap + prefetch-debounce timers so the frame settles.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(LoupeView), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
  });
}
