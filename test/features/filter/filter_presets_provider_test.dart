import 'package:cullimingo/features/filter/domain/filter_preset.dart';
import 'package:cullimingo/features/filter/domain/photo_filter.dart';
import 'package:cullimingo/features/filter/presentation/filter_providers.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer makeContainer({List<FilterPreset> seed = const []}) {
    final container = ProviderContainer(
      overrides: [filterPresetsSeedProvider.overrideWithValue(seed)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('seeds from the persisted list', () {
    final container = makeContainer(
      seed: const [
        FilterPreset(name: 'Keepers', filter: PhotoFilter(minRating: 4)),
      ],
    );
    expect(container.read(filterPresetsProvider).map((p) => p.name), [
      'Keepers',
    ]);
  });

  test('save appends a new preset, stripping selectedOnly', () {
    final container = makeContainer();
    container
        .read(filterPresetsProvider.notifier)
        .save(
          'Picks',
          const PhotoFilter(flag: PickFlag.pick, selectedOnly: true),
        );

    final saved = container.read(filterPresetsProvider);
    expect(saved, hasLength(1));
    expect(saved.single.name, 'Picks');
    expect(saved.single.filter.flag, PickFlag.pick);
    expect(saved.single.filter.selectedOnly, isFalse);
  });

  test('save replaces a same-name preset case-insensitively', () {
    final container = makeContainer();
    container.read(filterPresetsProvider.notifier)
      ..save('Keepers', const PhotoFilter(minRating: 3))
      ..save('keepers', const PhotoFilter(minRating: 5));

    final saved = container.read(filterPresetsProvider);
    expect(saved, hasLength(1));
    expect(saved.single.name, 'keepers');
    expect(saved.single.filter.minRating, 5);
  });

  test('a blank name is ignored', () {
    final container = makeContainer();
    container
        .read(filterPresetsProvider.notifier)
        .save('   ', const PhotoFilter(minRating: 2));
    expect(container.read(filterPresetsProvider), isEmpty);
  });

  test('delete removes the named preset', () {
    final container = makeContainer(
      seed: const [
        FilterPreset(name: 'A', filter: PhotoFilter(minRating: 1)),
        FilterPreset(name: 'B', filter: PhotoFilter(minRating: 2)),
      ],
    );
    container.read(filterPresetsProvider.notifier).delete('a'); // case-insens.
    expect(container.read(filterPresetsProvider).map((p) => p.name), ['B']);
  });

  test('restoring a preset replaces the whole active filter', () {
    final container = makeContainer();
    container
        .read(photoFilterControllerProvider.notifier)
        .toggleFlag(PickFlag.reject);

    const preset = PhotoFilter(minRating: 4, flag: PickFlag.pick);
    container.read(photoFilterControllerProvider.notifier).restore(preset);

    final active = container.read(photoFilterControllerProvider);
    expect(active.minRating, 4);
    expect(active.flag, PickFlag.pick);
  });
}
