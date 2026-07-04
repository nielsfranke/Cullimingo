import 'dart:convert';
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
import 'package:path/path.dart' as p;
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
    tempDir = Directory.systemTemp.createTempSync('cm_apply_template');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  /// Seeds `settings.json` in the fake app-support dir before the page loads.
  void seedSettings(Map<String, dynamic> data) => File(
    p.join(tempDir.path, 'settings.json'),
  ).writeAsStringSync(jsonEncode(data));

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

  /// Focuses the first photo, then presses T (the apply-template default key).
  Future<void> pressT(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pumpAndSettle();
  }

  testWidgets('T with no template saved surfaces the set-one-up notice', (
    tester,
  ) async {
    await pumpPage(tester);
    await pressT(tester);

    expect(
      find.text('No metadata template set up — add one in Settings'),
      findsOneWidget,
    );
  });

  testWidgets('T stamps the legacy single template (migration path)', (
    tester,
  ) async {
    seedSettings({
      'metadataTemplate': {
        'fields': {'credit': 'Reuters'},
      },
    });
    await pumpPage(tester);
    await pressT(tester);

    expect(
      find.text('Applied the metadata template to 1 photo(s)'),
      findsOneWidget,
    );
    final rows = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    expect(rows!.first.iptc.credit, 'Reuters');
    expect(rows[1].iptc.credit, isEmpty); // only the focused photo
  });

  testWidgets('T stamps the active snapshot, not the others', (tester) async {
    seedSettings({
      'metadataTemplates': {
        'active': 'Agency',
        'templates': [
          {
            'name': 'Wire',
            'template': {
              'fields': {'credit': 'Reuters'},
            },
          },
          {
            'name': 'Agency',
            'template': {
              'fields': {'credit': 'dpa'},
            },
          },
        ],
      },
      // A stale legacy key must lose against the snapshots key.
      'metadataTemplate': {
        'fields': {'credit': 'stale'},
      },
    });
    await pumpPage(tester);
    await pressT(tester);

    expect(
      find.text('Applied the metadata template to 1 photo(s)'),
      findsOneWidget,
    );
    final rows = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    expect(rows!.first.iptc.credit, 'dpa');
  });
}
