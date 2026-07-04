import 'package:cullimingo/features/cull/domain/grid_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('moveFocus', () {
    int move(
      int current,
      GridDirection dir, {
      int count = 10,
      int columns = 4,
    }) {
      return moveFocus(
        current: current,
        count: count,
        columns: columns,
        direction: dir,
      );
    }

    test('left/right move by one within bounds', () {
      expect(move(0, GridDirection.right), 1);
      expect(move(1, GridDirection.left), 0);
    });

    test('left/right clamp at the ends', () {
      expect(move(0, GridDirection.left), 0);
      expect(move(9, GridDirection.right), 9);
    });

    test('up/down move by a full row', () {
      expect(move(5, GridDirection.up), 1);
      expect(move(1, GridDirection.down), 5);
    });

    test('up on the top row stays put', () {
      expect(move(2, GridDirection.up), 2);
    });

    test('down does not wrap past the last partial row', () {
      // 10 items, 4 columns -> last row holds indices 8,9; down from 8 stays.
      expect(move(8, GridDirection.down), 8);
    });

    test('empty grid is a no-op', () {
      expect(move(0, GridDirection.right, count: 0), 0);
    });
  });
}
