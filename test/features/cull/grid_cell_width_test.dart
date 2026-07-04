import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seeds the grid cell width from the persisted value', () {
    final container = ProviderContainer(
      overrides: [gridCellWidthSeedProvider.overrideWithValue(360)],
    );
    addTearDown(container.dispose);

    expect(container.read(gridCellWidthProvider), 360);
  });

  test('falls back to the default when nothing is seeded', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(gridCellWidthProvider), GridCellWidth.fallback);
  });

  test('a seeded value out of range is clamped', () {
    final container = ProviderContainer(
      overrides: [gridCellWidthSeedProvider.overrideWithValue(9999)],
    );
    addTearDown(container.dispose);

    expect(container.read(gridCellWidthProvider), GridCellWidth.max);
  });

  test('set clamps the new width', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(gridCellWidthProvider.notifier).set(50);
    expect(container.read(gridCellWidthProvider), GridCellWidth.min);
  });
}
