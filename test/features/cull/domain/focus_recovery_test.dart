import 'package:cullimingo/features/cull/domain/focus_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('focusAfterDrop', () {
    test('moves to the photo that slid into the vacated slot', () {
      expect(
        focusAfterDrop(
          focusedId: 2,
          previous: [1, 2, 3, 4],
          visible: {1, 3, 4},
        ),
        3,
      );
    });

    test('skips forward past photos that vanished with it', () {
      expect(
        focusAfterDrop(
          focusedId: 2,
          previous: [1, 2, 3, 4],
          visible: {1, 4},
        ),
        4,
      );
    });

    test('falls back to the previous photo when the last one goes', () {
      expect(
        focusAfterDrop(focusedId: 4, previous: [1, 2, 3, 4], visible: {1, 2}),
        2,
      );
    });

    test('returns null when nothing from the old order survived', () {
      expect(
        focusAfterDrop(focusedId: 2, previous: [1, 2, 3], visible: {7, 8}),
        isNull,
      );
    });

    test('returns null when the photo was not visible to begin with', () {
      expect(
        focusAfterDrop(focusedId: 9, previous: [1, 2], visible: {1}),
        null,
      );
    });
  });
}
