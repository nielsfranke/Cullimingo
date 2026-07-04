import 'dart:typed_data';

import 'package:cullimingo/core/cache/preview_cache.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/core/settings/app_settings.dart';
import 'package:cullimingo/features/cull/presentation/cull_page.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/metadata/data/metadata_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Placeholder thumbnails — keeps the decode isolate out of the widget test.
class _NullExtractor implements PreviewExtractor {
  @override
  Future<Uint8List?> thumbnail(
    String path, {
    int longEdge = 512,
    CancelToken? cancel,
    JobPriority priority = JobPriority.visible,
  }) async => null;
}

/// Metadata repo that skips sidecar file I/O (can't progress under fake async).
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
  // markSeen() persists a setting, so detach the write queue from any prior
  // test's dead zone (see AppSettings.resetWriteQueueForTests).
  setUp(AppSettings.resetWriteQueueForTests);

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required bool seen,
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
        shortcutsHintSeenSeedProvider.overrideWithValue(seen),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CullPage()),
      ),
    );
    await tester.pump(); // first frame → post-frame callback fires
    await tester.pump(const Duration(milliseconds: 400)); // dialog transition
    return container;
  }

  testWidgets('first run pops the welcome cheat sheet and marks it seen', (
    tester,
  ) async {
    final container = await pump(tester, seen: false);

    expect(find.text('Welcome to Cullimingo'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
    expect(container.read(shortcutsHintSeenProvider), isTrue);

    await tester.tap(find.text('Got it'));
    await tester.pump(); // start the pop
    await tester.pump(const Duration(seconds: 1)); // finish the transition
    expect(find.text('Welcome to Cullimingo'), findsNothing);
  });

  testWidgets('does not pop again once seen', (tester) async {
    final container = await pump(tester, seen: true);

    expect(find.text('Welcome to Cullimingo'), findsNothing);
    expect(container.read(shortcutsHintSeenProvider), isTrue);
  });
}
