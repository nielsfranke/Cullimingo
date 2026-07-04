import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/filter/domain/photo_filter.dart';
import 'package:cullimingo/features/filter/domain/photo_sort.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose);

  Workspace notifier() => container.read(workspaceProvider.notifier);
  WorkspaceState state() => container.read(workspaceProvider);

  void open(int id) =>
      notifier().openImport(importId: id, sourcePath: '/f$id', label: 'f$id');

  test('openImport appends tabs and activates the new one', () {
    open(10);
    open(20);
    expect(state().tabs.map((t) => t.importId), [10, 20]);
    expect(state().activeIndex, 1);
    expect(state().active!.importId, 20);
  });

  test('re-opening an import activates the existing tab (no duplicate)', () {
    open(10);
    open(20);
    open(10);
    expect(state().tabs.map((t) => t.importId), [10, 20]);
    expect(state().activeIndex, 0);
  });

  test('saveActive stores view state into the active tab', () {
    open(10);
    notifier().saveActive(
      selection: const CullSelection(focusedId: 7, selectedIds: {7, 8}),
      filter: const PhotoFilter(minRating: 3),
      sort: const PhotoSort(key: PhotoSortKey.rating, ascending: false),
      scrollOffset: 1200,
    );
    expect(state().active!.selection.selectedIds, {7, 8});
    expect(state().active!.filter.minRating, 3);
    expect(state().active!.sort.key, PhotoSortKey.rating);
    expect(state().active!.sort.ascending, isFalse);
    expect(state().active!.scrollOffset, 1200);
  });

  test('close keeps a sensible neighbour active', () {
    open(10);
    open(20);
    open(30); // active = index 2 (id 30)

    notifier().close(2); // close the active last tab
    expect(state().tabs.map((t) => t.importId), [10, 20]);
    expect(state().active!.importId, 20);

    notifier().close(0); // close a tab before the active one
    expect(state().tabs.map((t) => t.importId), [20]);
    expect(state().active!.importId, 20); // still on 20

    notifier().close(0); // last one
    expect(state().tabs, isEmpty);
    expect(state().active, isNull);
  });
}
