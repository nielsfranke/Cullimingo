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

const _pathA = '/shoot/DSC_0001.jpg';
const _pathB = '/shoot/DSC_0002.jpg';

void main() {
  late ProviderContainer container;

  // Preview and "original" are the same size, so the native size a photo
  // resolves to never changes mid-zoom: the easing under test is the zoom's,
  // not a re-snap to a better source. 2:1, wider than the viewport, so 100% is
  // a zoom *in*.
  final preview = img.encodePng(img.Image(width: 3000, height: 1500));
  final full = img.encodePng(img.Image(width: 3000, height: 1500));

  Future<void> openLoupe(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
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
    final memory = MemoryByteCache(maxBytes: 1 << 30);
    for (final path in [_pathA, _pathB]) {
      memory
        ..put('loupe:$path', preview)
        ..put('full:$path', full);
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
      PhotosCompanion.insert(
        importId: Value(importId),
        path: _pathA,
        mtime: DateTime(2026, 6, 1, 10),
      ),
      PhotosCompanion.insert(
        importId: Value(importId),
        path: _pathB,
        mtime: DateTime(2026, 6, 1, 10, 1),
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

  testWidgets('Z eases into 100%, one frame at a time, around the pointer', (
    tester,
  ) async {
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
    final fitWidth = math.min(area.width, area.height * 2);
    final hundred = 3000 / fitWidth;
    expect(scale(), 1); // opens at Fit

    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    final focal = area.topLeft + Offset(area.width * 0.3, area.height * 0.4);
    await tester.sendEventToBinding(mouse.hover(focal));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);

    // Frame by frame: the zoom climbs towards 100% without ever snapping to
    // it, and the content under the pointer doesn't drift on the way.
    final local = focal - area.topLeft;
    final scales = <double>[];
    await tester.pump(); // the trip starts where the view already is
    for (var i = 0; i < 4; i++) {
      scales
        ..add(scale())
        ..add(translation().dx);
      final scene = (local - translation()) / scale();
      expect(scene.dx, closeTo(local.dx, 1e-6), reason: 'frame $i, x');
      expect(scene.dy, closeTo(local.dy, 1e-6), reason: 'frame $i, y');
      await tester.pump(const Duration(milliseconds: 30));
    }
    final steps = <double>[
      for (var i = 0; i < scales.length; i += 2) scales[i],
    ];
    expect(steps.first, 1); // starts at Fit, no jump
    for (var i = 1; i < steps.length; i++) {
      expect(steps[i], greaterThan(steps[i - 1]), reason: 'frame $i climbs');
    }
    expect(steps.last, lessThan(hundred)); // still on its way at ~90 ms

    // Lands exactly on 100% where the pointer is — the same place the snapping
    // path puts it (translationForZoom), just eased.
    await settle(tester);
    expect(scale(), closeTo(hundred, 1e-6));
    final scene = (local - translation()) / scale();
    expect(scene.dx, closeTo(local.dx, 1e-6));
    expect(scene.dy, closeTo(local.dy, 1e-6));
    // Reported once, at the landing frame, so the mode carries to the next
    // loupe session.
    expect(container.read(loupeZoomLevelProvider).mode, LoupeZoomMode.hundred);
  });

  testWidgets('stepping to the next frame mid-ease lands the zoom, no replay', (
    tester,
  ) async {
    await openLoupe(tester);
    final viewer = find.byType(InteractiveViewer);
    double scale() => tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!
        .value
        .getMaxScaleOnAxis();

    final area = tester.getRect(viewer);
    final fitWidth = math.min(area.width, area.height * 2);
    final hundred = 3000 / fitWidth;

    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(area.center));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);

    // Part-way through the easing…
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(scale(), greaterThan(1));
    expect(scale(), lessThan(hundred));

    // …step to the next frame. Its bytes come back a frame or two later (the
    // image area shows a placeholder until they do), so sample the whole
    // stretch: not one frame of the new photo may be mid-trip. Had the eased
    // zoom replayed over it, these would climb from where the old one stopped.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    final seen = <double>[];
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      final s = scaleOrNull(tester);
      if (s != null) seen.add(s);
    }
    expect(seen, isNotEmpty);
    for (final s in seen) {
      expect(s, closeTo(hundred, 1e-6));
    }
  });

  testWidgets('stepping between frames at a held zoom never moves the view', (
    tester,
  ) async {
    await openLoupe(tester);
    final viewer = find.byType(InteractiveViewer);
    double scale() => tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!
        .value
        .getMaxScaleOnAxis();

    final area = tester.getRect(viewer);
    final fitWidth = math.min(area.width, area.height * 2);
    final hundred = 3000 / fitWidth;

    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      mouse.hover(area.topLeft + Offset(area.width * 0.25, area.height * 0.5)),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await settle(tester);
    expect(scale(), closeTo(hundred, 1e-6));

    // Both frames are the same size here, so a held 100% must simply stay put
    // — every frame of the stretch after each blit, not just the last one.
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(
        i.isEven ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft,
      );
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        final s = scaleOrNull(tester);
        if (s != null) expect(s, closeTo(hundred, 1e-6), reason: 'blit $i');
      }
      await settle(tester);
      expect(scale(), closeTo(hundred, 1e-6), reason: 'blit $i settled');
    }
  });

  testWidgets('the wheel takes over a zoom that is still easing', (
    tester,
  ) async {
    await openLoupe(tester);
    final viewer = find.byType(InteractiveViewer);
    double scale() => tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!
        .value
        .getMaxScaleOnAxis();

    final area = tester.getRect(viewer);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(area.center));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final midFlight = scale();

    // ⌘/Ctrl+wheel zooms from the frame on screen, and the eased trip stops
    // there instead of pulling the view onwards.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -50)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    final afterWheel = scale();
    expect(afterWheel, greaterThan(midFlight));
    await tester.pump(const Duration(milliseconds: 100));
    expect(scale(), closeTo(afterWheel, 1e-6));
  });
}

/// Lets the preview/full-res decodes, their size lookups and any easing land.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The loupe's zoom scale, or null while the image area is a placeholder (a
/// blitted frame's bytes are still loading, so there's no viewer to read).
double? scaleOrNull(WidgetTester tester) {
  final viewer = find.byType(InteractiveViewer);
  if (viewer.evaluate().isEmpty) return null;
  return tester
      .widget<InteractiveViewer>(viewer)
      .transformationController!
      .value
      .getMaxScaleOnAxis();
}
