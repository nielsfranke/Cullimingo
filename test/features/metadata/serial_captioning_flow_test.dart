import 'dart:io';

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
// Test-only transitive deps (via path_provider) for mocking the platform.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// Test-only transitive dep (via path_provider) for the mock mixin.
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Feeds a fixed app-support dir so `AppSettings.load()` resolves promptly in
/// the test instead of hanging on an unregistered platform channel.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.supportDir);
  final String supportDir;
  @override
  Future<String?> getApplicationSupportPath() async => supportDir;
}

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
  late Directory tempDir;
  late AppDatabase db;
  late ProviderContainer container;
  late int importId;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cm_serial_flow');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
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
    await tester.pump(); // photos stream emits
    await tester.pump(); // grid builds its cells
  }

  testWidgets('M over one photo walks the filtered set: caption, ⌘Enter, '
      'caption, Save — both written, grid focus follows', (tester) async {
    await pumpPage(tester);

    // Focus the first photo, open the editor: serial mode over 2 photos.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pumpAndSettle();
    expect(find.text('1 of 2'), findsOneWidget);
    // Scoped to the dialog — the grid cell behind it shows the filename too.
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('DSC_0001.jpg'),
      ),
      findsOneWidget,
    );

    // Caption photo 1 (with a variable), walk forward with ⌘Enter.
    await tester.enterText(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          )
          .first,
      'First: {name}',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(find.text('2 of 2'), findsOneWidget);
    // The grid's focus followed the walk.
    final photos = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    expect(
      container.read(cullControllerProvider).focusedId,
      photos![1].id,
    );

    // Caption photo 2, close with Save.
    await tester.enterText(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          )
          .first,
      'Second',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    // The editor (an AlertDialog titled "Metadata") is gone. Scope to the
    // dialog — the filter bar's own "Metadata" dropdown label stays on screen.
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Metadata'),
      ),
      findsNothing,
    );

    final rows = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    expect(rows!.first.iptc.caption, 'First: DSC_0001');
    expect(rows[1].iptc.caption, 'Second');
  });
}
