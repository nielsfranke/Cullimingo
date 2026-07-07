import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/filter/domain/filter_preset.dart';
import 'package:cullimingo/features/filter/domain/photo_filter.dart';
import 'package:cullimingo/features/filter/presentation/filter_bar.dart';
import 'package:cullimingo/features/filter/presentation/filter_providers.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Photo _photo(int id) => Photo(
  id: id,
  importId: 1,
  path: '/x/$id.jpg',
  mtime: DateTime(2026),
  orientation: 1,
  userRotation: 0,
  hasCrop: false,
  rating: id, // ids 1..3 double as ratings for the filter test
  flag: PickFlag.none,
  colorLabel: ColorLabel.none,
  keywords: const [],
  iptc: const IptcCore(),
  hasXmp: false,
  xmpConflict: false,
  previewCached: false,
  isRaw: false,
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  List<FilterPreset> seed = const [],
}) async {
  tester.view.physicalSize = const Size(1600, 400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      photosProvider.overrideWith(
        (ref) => Stream.value([for (var i = 1; i <= 3; i++) _photo(i)]),
      ),
      filterPresetsSeedProvider.overrideWithValue(seed),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: FilterBar())),
    ),
  );
  await tester.pump(); // photos stream emits
  return container;
}

void main() {
  testWidgets('saving the active filter through the menu persists a preset', (
    tester,
  ) async {
    final container = await _pump(tester);

    // Activate a filter so "Save current filter…" is enabled.
    container.read(photoFilterControllerProvider.notifier).toggleMinRating(3);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.filter_alt_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save current filter…'));
    await tester.pumpAndSettle();

    // Scope to the dialog's field — the filter bar now also has a search box.
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Keepers',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final presets = container.read(filterPresetsProvider);
    expect(presets, hasLength(1));
    expect(presets.single.name, 'Keepers');
    expect(presets.single.filter.minRating, 3);
  });

  testWidgets('choosing a saved preset applies its filter', (tester) async {
    final container = await _pump(
      tester,
      seed: const [
        FilterPreset(name: 'Keepers', filter: PhotoFilter(minRating: 3)),
      ],
    );

    // No filter active yet → the whole grid shows.
    expect(container.read(filteredPhotosProvider), hasLength(3));

    // A preset exists → the badged (filled) icon is shown.
    await tester.tap(find.byIcon(Icons.filter_alt));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keepers'));
    await tester.pumpAndSettle();

    expect(container.read(photoFilterControllerProvider).minRating, 3);
    // Only rating ≥ 3 (the photo with id/rating 3) survives.
    expect(container.read(filteredPhotosProvider).map((p) => p.id), [3]);
  });
}
