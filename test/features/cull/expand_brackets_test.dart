import 'package:cullimingo/core/cache/preview_cache.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/features/cull/presentation/cull_page.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/widgets/grid_cell.dart';
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
  late AppDatabase db;
  late ProviderContainer container;
  late int importId;

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 800);
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
    DateTime at(int s) =>
        DateTime(2026, 5, 29, 12, 44).add(Duration(seconds: s));
    await db.insertPhotos([
      // A 0 / +3 / −3 bracket (id order = insert order).
      PhotosCompanion.insert(
        importId: Value(importId),
        path: '/shoot/DSCF0001.RAF',
        mtime: at(0),
        capturedAt: Value(at(0)),
        camera: const Value('Fujifilm X-H2S'),
        exposureBias: const Value(0),
        isRaw: const Value(true),
      ),
      PhotosCompanion.insert(
        importId: Value(importId),
        path: '/shoot/DSCF0002.RAF',
        mtime: at(2),
        capturedAt: Value(at(2)),
        camera: const Value('Fujifilm X-H2S'),
        exposureBias: const Value(3),
        isRaw: const Value(true),
      ),
      PhotosCompanion.insert(
        importId: Value(importId),
        path: '/shoot/DSCF0003.RAF',
        mtime: at(4),
        capturedAt: Value(at(4)),
        camera: const Value('Fujifilm X-H2S'),
        exposureBias: const Value(-3),
        isRaw: const Value(true),
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

  testWidgets('G expands a picked reference to its whole bracket', (
    tester,
  ) async {
    await pumpPage(tester);

    final photos = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    final ids = photos!.map((p) => p.id).toList();

    // Simulate the client's pick coming back: only the 0 EV reference frame.
    container.read(cullControllerProvider.notifier).setSelection({ids.first});
    await tester.pump();

    // Focus the grid (tap the reference cell — tapping empty space would
    // instead clear the selection) then press G.
    await tester.tap(find.byType(GridCell).first);
    await tester.pump(
      const Duration(milliseconds: 300),
    ); // clear double-tap timer
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pump();

    // The two bracketed exposures are now selected alongside the reference.
    expect(container.read(cullControllerProvider).selectedIds, ids.toSet());
  });

  testWidgets('G leaves a non-bracket selection unchanged', (tester) async {
    await pumpPage(tester);
    // Replace the shoot with a single lone frame (no bracket).
    await db.deletePhotosByPaths(importId, [
      '/shoot/DSCF0002.RAF',
      '/shoot/DSCF0003.RAF',
    ]);
    await tester.pump();
    await tester.pump();

    final photos = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    final loneId = photos!.single.id;
    container.read(cullControllerProvider.notifier).setSelection({loneId});
    await tester.pump();

    await tester.tap(find.byType(GridCell).first);
    await tester.pump(
      const Duration(milliseconds: 300),
    ); // clear double-tap timer
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pump();

    expect(container.read(cullControllerProvider).selectedIds, {loneId});
  });
}
