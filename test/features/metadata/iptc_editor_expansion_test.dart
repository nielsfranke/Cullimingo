import 'dart:convert';
import 'dart:io';

import 'package:cullimingo/core/cache/preview_cache.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/features/cull/presentation/cull_page.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/metadata/data/metadata_repository.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
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
    tempDir = Directory.systemTemp.createTempSync('cm_iptc_expansion');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    // A code table for the live-expansion path.
    File(p.join(tempDir.path, 'settings.json')).writeAsStringSync(
      jsonEncode({
        'codeReplacements': {
          'delimiter': '=',
          'codes': {
            'ap': ['Associated Press'],
          },
        },
      }),
    );
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

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
    await tester.pump(); // photos stream emits
    await tester.pump(); // grid builds its cells
  }

  Future<IptcCore> savedIptcAfterTypingCaption(
    WidgetTester tester,
    String input,
  ) async {
    // First key press focuses the photo, then M opens the editor.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pumpAndSettle();
    // Scope to the editor's own dialog title — the filter bar behind it now
    // also carries a "Metadata" dropdown label.
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Metadata'),
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          )
          .first,
      input,
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final rows = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    return rows!.first.iptc;
  }

  testWidgets("{variables} in the M editor expand on save with the photo's "
      'own values', (tester) async {
    await pumpPage(tester);
    final iptc = await savedIptcAfterTypingCaption(
      tester,
      '{name} on {date}',
    );
    expect(iptc.caption, 'DSC_0001 on 2026-06-01');
  });

  testWidgets('=codes= from the saved table expand live in the M editor', (
    tester,
  ) async {
    await pumpPage(tester);
    final iptc = await savedIptcAfterTypingCaption(tester, 'Photo: =ap=');
    // Expanded live in the field, and saved expanded.
    expect(iptc.caption, 'Photo: Associated Press');
  });
}
