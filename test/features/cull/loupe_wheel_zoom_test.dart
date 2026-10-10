import 'dart:async';
import 'dart:math' as math;

import 'package:cullimingo/core/cache/memory_byte_cache.dart';
import 'package:cullimingo/core/cache/preview_cache.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/features/cull/domain/loupe_zoom.dart';
import 'package:cullimingo/features/cull/presentation/cull_page.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/metadata/data/metadata_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
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

const _path = '/shoot/DSC_0001.jpg';

void main() {
  late ProviderContainer container;

  // A 2:1 frame: a small screen-res preview and a 4000-px "original", so
  // 100% only becomes true 1:1 once the full-res source has been decoded.
  final preview = img.encodePng(img.Image(width: 800, height: 400));
  final full = img.encodePng(img.Image(width: 4000, height: 2000));

  Future<void> openLoupe(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // The grid's native drag-and-drop asks its plugin for an engine handle
    // once real async work runs; there's no plugin under test, so leave that
    // call pending instead of failing.
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
    final memory = MemoryByteCache(maxBytes: 1 << 30)
      ..put('loupe:$_path', preview)
      ..put('full:$_path', full);
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
      PhotosCompanion.insert(
        importId: Value(importId),
        path: _path,
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
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // focus
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // open loupe
    await settle(tester);
  }

  testWidgets('Z, wheel pan and ⌘/Ctrl+wheel zoom', (tester) async {
    await openLoupe(tester);
    final viewer = find.byType(InteractiveViewer);
    expect(viewer, findsOneWidget);
    Matrix4 matrix() => tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!
        .value;
    double scale() => matrix().getMaxScaleOnAxis();
    Offset translation() {
      final t = matrix().getTranslation();
      return Offset(t.x, t.y);
    }

    final area = tester.getRect(viewer);
    expect(scale(), 1); // opens at Fit
    // Fit contains the 2:1 frame in the image area.
    final fitWidth = math.min(area.width, area.height * 2);
    final trueHundred = 4000 / fitWidth;

    // Z zooms to 100% where the mouse points: the content under it stays put,
    // and the scale lands on the full-res original's 1:1, not the preview's.
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    final focal = area.topLeft + Offset(area.width * 0.3, area.height * 0.4);
    await tester.sendEventToBinding(mouse.hover(focal));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await settle(tester);
    expect(scale(), closeTo(trueHundred, 1e-6));
    final local = focal - area.topLeft;
    final scene = (local - translation()) / scale();
    expect(scene.dx, closeTo(local.dx, 1e-6));
    expect(scene.dy, closeTo(local.dy, 1e-6));

    // Plain wheel pans vertically, no zoom.
    final before = translation();
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 60)));
    await tester.pump();
    expect(scale(), closeTo(trueHundred, 1e-6));
    expect(translation().dx, closeTo(before.dx, 1e-6));
    expect(translation().dy, closeTo(before.dy - 60, 1e-6));

    // Shift + wheel pans sideways.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 40)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(translation().dx, closeTo(before.dx - 40, 1e-6));
    expect(translation().dy, closeTo(before.dy - 60, 1e-6));

    // Ctrl + wheel zooms (wheel up = in), and that lets go of the held 100%.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -50)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    final zoomedIn = math.min(trueHundred * math.exp(50 / 200), 4);
    expect(scale(), closeTo(zoomedIn, 1e-6));
    expect(container.read(loupeZoomLevelProvider).mode, LoupeZoomMode.custom);

    // Z from any zoom goes back to Fit.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.pump();
    expect(scale(), 1);
    expect(translation(), Offset.zero);
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
