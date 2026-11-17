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

const _pathA = '/shoot/DSC_0001.cr3';
const _pathB = '/shoot/DSC_0002.cr3';

void main() {
  late ProviderContainer container;

  // The real thing, unlike the easing test's equal-sized pair: the loupe
  // preview is half the original, so 100% means two different scales and the
  // re-snap when the full-res frame arrives is exactly what must not jump
  // (maintainer's point on PR #23).
  final preview = img.encodePng(img.Image(width: 3000, height: 1500));
  final full = img.encodePng(img.Image(width: 6000, height: 3000));

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

  testWidgets('Z lands on the original 1:1 without a frame that jumps', (
    tester,
  ) async {
    await openLoupe(tester);
    final viewer = find.byType(InteractiveViewer);
    expect(viewer, findsOneWidget);
    double scale() => tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!
        .value
        .getMaxScaleOnAxis();

    final area = tester.getRect(viewer);
    final fitWidth = math.min(area.width, area.height * 2);
    final previewHundred = 3000 / fitWidth;
    final fullHundred = 6000 / fitWidth;
    expect(scale(), 1); // opens at Fit

    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(area.center));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.pump(); // the trip starts where the view already is

    // Sample the whole stretch — the eased trip to the preview's 100%, the
    // full-res decode landing, and the re-snap to the original's 1:1. The
    // clock is the tester's, so the numbers are the animation's, not the
    // machine's: a snap covers the whole way in one 16 ms frame.
    final seen = <({int ms, double scale})>[];
    var ms = 0;
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 16));
      ms += 16;
      final s = scaleOrNull(tester);
      if (s != null) seen.add((ms: ms, scale: s));
    }
    expect(seen.length, greaterThan(8), reason: 'the loupe stayed on screen');

    // Every frame of the whole stretch moves towards the target, never back.
    for (var i = 1; i < seen.length; i++) {
      expect(
        seen[i].scale,
        greaterThanOrEqualTo(seen[i - 1].scale - 1e-6),
        reason:
            'frame $i does not fall back '
            '(${seen[i - 1].scale} → ${seen[i].scale})',
      );
    }
    expect(seen.last.scale, closeTo(fullHundred, 1e-6));
    expect(previewHundred, lessThan(fullHundred));

    // The last leg — preview 100% → original 100% — is a trip of its own, not
    // a snap: it takes a large part of the 190 ms ease, not one frame. A snap
    // here is exactly what the review asked to fix.
    final reachedPreview = seen.firstWhere(
      (f) => f.scale >= previewHundred - 1e-6,
    );
    final reachedFull = seen.firstWhere((f) => f.scale >= fullHundred - 1e-6);
    expect(
      reachedFull.ms - reachedPreview.ms,
      greaterThanOrEqualTo(120),
      reason:
          'the re-snap jumped: '
          '${reachedPreview.scale} → ${reachedFull.scale} '
          'in ${reachedFull.ms - reachedPreview.ms} ms',
    );
    expect(container.read(loupeZoomLevelProvider).mode, LoupeZoomMode.hundred);
  });

  testWidgets('a full-res frame arriving at a held 100% eases, not snaps', (
    tester,
  ) async {
    await openLoupe(tester);
    final viewer = find.byType(InteractiveViewer);
    final area = tester.getRect(viewer);
    final fitWidth = math.min(area.width, area.height * 2);
    final fullHundred = 6000 / fitWidth;

    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(area.center));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    // Two trips back to back (to the preview's 100%, then the eased re-snap to
    // the original's), so wait for the view to stop moving rather than for a
    // fixed time.
    final held = await settleScale(tester);
    expect(held, closeTo(fullHundred, 1e-6));

    // Step to the next frame: it comes in as a preview first and resolves to
    // the full-res original right after, i.e. the re-snap happens while the
    // zoom is held, not while it is travelling. It still must not jump.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    final seen = <double>[];
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 16));
      final s = scaleOrNull(tester);
      if (s != null) seen.add(s);
    }
    expect(seen, isNotEmpty);
    for (var i = 1; i < seen.length; i++) {
      expect(
        seen[i] - seen[i - 1],
        lessThan(0.35 * (fullHundred - 1)),
        reason: 'frame $i jumps: ${seen[i - 1]} → ${seen[i]}',
      );
    }
    expect(seen.last, closeTo(fullHundred, 1e-6));
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

/// Pumps until the zoom stops moving, returning the scale it came to rest on.
/// Two eased trips can run back to back, so a fixed settle is not enough.
Future<double> settleScale(
  WidgetTester tester, {
  int maxFrames = 80,
  int stableFrames = 6,
}) async {
  double? last;
  var still = 0;
  for (var i = 0; i < maxFrames; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final s = scaleOrNull(tester);
    if (s == null) continue;
    if (last != null && (s - last).abs() < 1e-6) {
      still++;
      if (still >= stableFrames) return s;
    } else {
      still = 0;
    }
    last = s;
  }
  return last ?? 0;
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
