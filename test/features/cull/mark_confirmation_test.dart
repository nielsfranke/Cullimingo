import 'package:cullimingo/core/cache/preview_cache.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/core/settings/app_settings.dart';
import 'package:cullimingo/features/cull/presentation/cull_page.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/metadata/data/metadata_repository.dart';
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
  setUp(AppSettings.resetWriteQueueForTests);

  // Opens the loupe on the first photo; [enabled] seeds the overlay setting,
  // [autoAdvance] the auto-advance-after-mark setting.
  Future<void> openLoupe(
    WidgetTester tester, {
    required bool enabled,
    bool autoAdvance = false,
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
        markConfirmationEnabledSeedProvider.overrideWithValue(enabled),
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
    await tester.pump(); // photos stream
    await tester.pump(); // grid cells
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // focus first
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // open loupe
    await tester.pump();
  }

  Future<void> pumpFlash(WidgetTester tester) async {
    await tester.pump(); // key handled → mark dispatched
    await tester.pump(const Duration(milliseconds: 60)); // DB emit + rebuild
    await tester.pump(const Duration(milliseconds: 120)); // post-frame + fade
  }

  testWidgets('flashes a confirmation when a mark is applied in the loupe', (
    tester,
  ) async {
    await openLoupe(tester, enabled: true);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyX); // reject
    await pumpFlash(tester);
    expect(find.text('Rejected'), findsOneWidget);
  });

  testWidgets('no confirmation flash when the setting is off', (tester) async {
    await openLoupe(tester, enabled: false);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyX); // reject
    await pumpFlash(tester);
    expect(find.text('Rejected'), findsNothing);
  });

  testWidgets('suppressed under auto-advance (the advance is the confirm)', (
    tester,
  ) async {
    await openLoupe(tester, enabled: true, autoAdvance: true);

    // Rejecting photo 1 advances to photo 2; flashing over that next photo
    // would be confusing, so no confirmation is shown.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await pumpFlash(tester);
    expect(find.text('2 / 3'), findsOneWidget); // advanced
    expect(find.text('Rejected'), findsNothing); // but not flashed
  });
}
