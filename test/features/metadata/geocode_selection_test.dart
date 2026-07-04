import 'package:cullimingo/core/cache/preview_cache.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/features/cull/presentation/cull_page.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/metadata/data/metadata_repository.dart';
import 'package:cullimingo/features/metadata/domain/reverse_geocoder.dart';
import 'package:cullimingo/features/metadata/presentation/geocoding_providers.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Northern hemisphere resolves to a fixed place; the south finds nothing
/// (the "open ocean" case) — enough to exercise every outcome bucket.
class _FakeGeocoder implements ReverseGeocoder {
  @override
  Future<GeoPlace?> lookup(double latitude, double longitude) async =>
      latitude > 0
      ? const GeoPlace(
          city: 'Berlin',
          state: 'Berlin',
          country: 'Germany',
          countryCode: 'DE',
        )
      : null;
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
  late AppDatabase db;
  late ProviderContainer container;
  late int importId;

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
        reverseGeocoderProvider.overrideWith((ref) async => _FakeGeocoder()),
      ],
    );
    addTearDown(container.dispose);

    importId = await db.createImport(sourcePath: '/shoot');
    await db.insertPhotos([
      // Geocodes to Berlin.
      PhotosCompanion.insert(
        importId: Value(importId),
        path: '/shoot/DSC_0001.jpg',
        mtime: DateTime(2026, 6, 1, 10, 1),
        capturedAt: Value(DateTime(2026, 6, 1, 10, 1)),
        latitude: const Value(52.52),
        longitude: const Value(13.405),
      ),
      // Has a position, but nothing is near it.
      PhotosCompanion.insert(
        importId: Value(importId),
        path: '/shoot/DSC_0002.jpg',
        mtime: DateTime(2026, 6, 1, 10, 2),
        capturedAt: Value(DateTime(2026, 6, 1, 10, 2)),
        latitude: const Value(-40),
        longitude: const Value(-140),
      ),
      // No GPS at all.
      PhotosCompanion.insert(
        importId: Value(importId),
        path: '/shoot/DSC_0003.jpg',
        mtime: DateTime(2026, 6, 1, 10, 3),
        capturedAt: Value(DateTime(2026, 6, 1, 10, 3)),
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

  testWidgets('⋮ → Fill location from GPS stamps the selection and reports '
      'the skips', (tester) async {
    await pumpPage(tester);

    // Select all three photos, then run the menu action.
    final rows = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    container.read(cullControllerProvider.notifier).setSelection({
      for (final r in rows!) r.id,
    });
    await tester.pump();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fill location from GPS'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Filled location on 1 photo(s) · 1 without GPS · '
        '1 with no place nearby',
      ),
      findsOneWidget,
    );

    final after = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    final berlin = after!.singleWhere((r) => r.path.endsWith('DSC_0001.jpg'));
    expect(berlin.iptc.city, 'Berlin');
    expect(berlin.iptc.state, 'Berlin');
    expect(berlin.iptc.country, 'Germany');
    expect(berlin.iptc.countryCode, 'DE');
    // The skipped photos keep their (empty) location.
    final ocean = after.singleWhere((r) => r.path.endsWith('DSC_0002.jpg'));
    expect(ocean.iptc.city, isEmpty);
  });

  testWidgets('with nothing geocodable the notice explains why', (
    tester,
  ) async {
    await pumpPage(tester);

    // Select only the photo without GPS.
    final rows = await tester.runAsync(
      () => db.watchPhotosForImport(importId).first,
    );
    final noGps = rows!.singleWhere((r) => r.path.endsWith('DSC_0003.jpg'));
    container.read(cullControllerProvider.notifier).setSelection({noGps.id});
    await tester.pump();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fill location from GPS'));
    await tester.pumpAndSettle();

    expect(
      find.text('No location filled — 1 without GPS'),
      findsOneWidget,
    );
  });
}
