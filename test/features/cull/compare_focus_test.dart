import 'package:cullimingo/features/cull/domain/compare_focus.dart';
import 'package:cullimingo/features/cull/domain/grid_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compareFocusAfterMove', () {
    const ids = [10, 20, 30, 40, 50]; // 3 columns (columnsFor(5))

    test('left/right step within the list', () {
      expect(
        compareFocusAfterMove(
          ids: ids,
          focusedId: 20,
          columns: 3,
          direction: GridDirection.right,
        ),
        30,
      );
      expect(
        compareFocusAfterMove(
          ids: ids,
          focusedId: 20,
          columns: 3,
          direction: GridDirection.left,
        ),
        10,
      );
    });

    test('does not step past the ends', () {
      expect(
        compareFocusAfterMove(
          ids: ids,
          focusedId: 10,
          columns: 3,
          direction: GridDirection.left,
        ),
        10,
      );
      expect(
        compareFocusAfterMove(
          ids: ids,
          focusedId: 50,
          columns: 3,
          direction: GridDirection.right,
        ),
        50,
      );
    });

    test('up/down move by a row of columns', () {
      // index 3 (40) up one row of 3 → index 0 (10).
      expect(
        compareFocusAfterMove(
          ids: ids,
          focusedId: 40,
          columns: 3,
          direction: GridDirection.up,
        ),
        10,
      );
      // index 1 (20) down one row → index 4 (50).
      expect(
        compareFocusAfterMove(
          ids: ids,
          focusedId: 20,
          columns: 3,
          direction: GridDirection.down,
        ),
        50,
      );
    });

    test('unknown focused id is returned unchanged', () {
      expect(
        compareFocusAfterMove(
          ids: ids,
          focusedId: 999,
          columns: 3,
          direction: GridDirection.right,
        ),
        999,
      );
    });
  });

  group('compareFocusAfterRemove', () {
    test('keeps the slot position when the focused tile is dropped', () {
      // Drop the focused 30 (index 2) → 40 slides into slot 2.
      expect(
        compareFocusAfterRemove(
          ids: const [10, 20, 30, 40],
          removedId: 30,
          focusedId: 30,
        ),
        40,
      );
    });

    test('clamps to the last tile when the focused last one is dropped', () {
      expect(
        compareFocusAfterRemove(
          ids: const [10, 20, 30],
          removedId: 30,
          focusedId: 30,
        ),
        20,
      );
    });

    test('leaves focus alone when a non-focused tile is dropped', () {
      expect(
        compareFocusAfterRemove(
          ids: const [10, 20, 30],
          removedId: 10,
          focusedId: 30,
        ),
        30,
      );
    });

    test('returns null when the last tile is removed', () {
      expect(
        compareFocusAfterRemove(
          ids: const [10],
          removedId: 10,
          focusedId: 10,
        ),
        isNull,
      );
    });
  });
}
