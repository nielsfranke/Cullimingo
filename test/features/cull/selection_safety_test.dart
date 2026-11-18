import 'package:cullimingo/core/cache/preview_cache.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/features/cull/presentation/cull_page.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/filter/presentation/filter_providers.dart';
import 'package:cullimingo/features/metadata/data/metadata_repository.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
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

  Future<void> pumpPage(
    WidgetTester tester, {
    PickFlag flag = PickFlag.none,
  }) async {
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
          flag: Value(flag),
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

  testWidgets('a batch mark skips selected photos the filter hides; Esc '
      'clears the selection (#28)', (tester) async {
    await pumpPage(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // focus first
    await tester.pump();
    final controller = container.read(cullControllerProvider.notifier);
    final rows = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    for (final r in rows!) {
      controller.toggleSelect(r.id);
    }
    controller.focus(rows.first.id);
    await tester.pump();
    expect(find.textContaining('3 selected · Esc clears'), findsOneWidget);

    // Narrow the grid to the first photo: the other two stay selected but
    // hidden, and the status bar says so.
    container.read(photoFilterControllerProvider.notifier).setQuery('0001');
    await tester.pump();
    expect(
      find.textContaining('3 selected (2 hidden by filter)'),
      findsOneWidget,
    );

    // A digit rates only what the grid shows.
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump();
    final after = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    expect([for (final r in after!) r.rating], [3, 0, 0]);

    // Esc drops the selection; the next digit hits the focused photo only.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(container.read(cullControllerProvider).selectedIds, isEmpty);
    expect(find.textContaining('0 selected'), findsOneWidget);
    expect(find.textContaining('Esc clears'), findsNothing);
  });
}
