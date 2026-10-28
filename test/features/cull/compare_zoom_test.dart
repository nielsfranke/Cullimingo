import 'dart:async';
import 'dart:math' as math;

import 'package:cullimingo/core/cache/memory_byte_cache.dart';
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
import 'package:image/image.dart' as img;

/// Never reached — every tier is pre-seeded in RAM.
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

const _a = '/shoot/DSC_0001.jpg';
const _b = '/shoot/DSC_0002.jpg';

void main() {
  late ProviderContainer container;

  // 2:1 frames: a small screen-res preview and a 4000-px "original".
  final preview = img.encodePng(img.Image(width: 800, height: 400));
  final full = img.encodePng(img.Image(width: 4000, height: 2000));

  Future<void> openCompare(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const dragChannel = MethodChannel('dev.irondash.engine_context');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      dragChannel,
      (_) => Completer<Object?>().future,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        dragChannel,
        null,
      ),
    );

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final memory = MemoryByteCache(maxBytes: 1 << 30);
    for (final p in [_a, _b]) {
      memory
        ..put('loupe:$p', preview)
        ..put('full:$p', full);
    }
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        previewCacheProvider.overrideWithValue(
          PreviewCache(extractor: _NullExtractor(), memory: memory),
        ),
        metadataRepositoryProvider.overrideWithValue(_NoopMetadata(db)),
      ],
    );
    addTearDown(container.dispose);

    final importId = await db.createImport(sourcePath: '/shoot');
    await db.insertPhotos([
      for (final p in [_a, _b])
        PhotosCompanion.insert(
          importId: Value(importId),
          path: p,
          mtime: DateTime(2026, 6, 1, 10),
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
    final photos = await container.read(photosProvider.future);
    container.read(cullControllerProvider.notifier)
      ..selectOnly(photos.first.id)
      ..toggleSelect(photos.last.id);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await settle(tester);
  }

  testWidgets('zoom is linked across tiles, Z toggles 100%, link frees them', (
    tester,
  ) async {
    await openCompare(tester);
    final viewers = find.byType(InteractiveViewer);
    expect(viewers, findsNWidgets(2));
    double scaleOf(int i) => tester
        .widget<InteractiveViewer>(viewers.at(i))
        .transformationController!
        .value
        .getMaxScaleOnAxis();

    expect(scaleOf(0), 1);
    expect(scaleOf(1), 1);

    // Z → true 100% of the 4000-px original, in both tiles at once.
    final area = tester.getRect(viewers.first);
    final fitWidth = math.min(area.width, area.height * 2);
    final trueHundred = 4000 / fitWidth;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await settle(tester);
    expect(scaleOf(0), closeTo(trueHundred, 0.05));
    expect(scaleOf(1), closeTo(trueHundred, 0.05));

    // Zoomed past the trigger, the tiles now hold the full-res bitmap.
    final img0 = tester.widget<Image>(
      find.descendant(of: viewers.first, matching: find.byType(Image)),
    );
    expect(
      (img0.image as MemoryImage).bytes.lengthInBytes,
      full.lengthInBytes,
    );

    // Z again → back to Fit everywhere.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.pump();
    expect(scaleOf(0), 1);
    expect(scaleOf(1), 1);

    // Unlink, zoom (Z acts on the focused tile only), then Fit resets all.
    await tester.tap(find.byIcon(Icons.link_rounded));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await settle(tester);
    final scales = [scaleOf(0), scaleOf(1)]..sort();
    expect(scales.first, 1);
    expect(scales.last, greaterThan(1));
    await tester.tap(find.text('Fit'));
    await tester.pump();
    expect(scaleOf(0), 1);
    expect(scaleOf(1), 1);
  });
}

/// Lets the preview/full-res decodes and their size lookups land.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}
