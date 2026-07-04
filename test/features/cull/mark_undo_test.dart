import 'package:cullimingo/features/cull/domain/mark_undo.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RatingUndoEntry rating(int id, {int from = 0, int to = 5}) =>
      RatingUndoEntry(before: {id: from}, after: to);

  test('takeUndo pops newest-first and moves entries to the redo side', () {
    final history = UndoHistory()
      ..push(rating(1))
      ..push(rating(2));

    expect(history.canUndo, isTrue);
    expect(history.canRedo, isFalse);

    expect((history.takeUndo()! as RatingUndoEntry).before.keys, [2]);
    expect((history.takeUndo()! as RatingUndoEntry).before.keys, [1]);
    expect(history.takeUndo(), isNull);
    expect(history.canRedo, isTrue);
  });

  test('takeRedo replays in reverse undo order and refills the undo side', () {
    final history = UndoHistory()
      ..push(rating(1))
      ..push(rating(2))
      ..takeUndo()
      ..takeUndo();

    expect((history.takeRedo()! as RatingUndoEntry).before.keys, [1]);
    expect((history.takeRedo()! as RatingUndoEntry).before.keys, [2]);
    expect(history.takeRedo(), isNull);
    expect(history.canUndo, isTrue);
  });

  test('a fresh push clears the redo side (standard editor semantics)', () {
    final history = UndoHistory()
      ..push(rating(1))
      ..takeUndo()
      ..push(rating(2));

    expect(history.canRedo, isFalse);
    expect((history.takeUndo()! as RatingUndoEntry).before.keys, [2]);
  });

  test('the undo side is capped at maxEntries, dropping the oldest', () {
    final history = UndoHistory(maxEntries: 2)
      ..push(rating(1))
      ..push(rating(2))
      ..push(rating(3));

    expect((history.takeUndo()! as RatingUndoEntry).before.keys, [3]);
    expect((history.takeUndo()! as RatingUndoEntry).before.keys, [2]);
    expect(history.takeUndo(), isNull); // entry 1 fell off
  });

  test('clear forgets both sides', () {
    final history = UndoHistory()
      ..push(rating(1))
      ..push(rating(2))
      ..takeUndo()
      ..clear();

    expect(history.canUndo, isFalse);
    expect(history.canRedo, isFalse);
  });

  test('describe names the mark and pluralizes the photo count', () {
    expect(rating(1).describe(), 'rating');
    expect(
      const RatingUndoEntry(before: {1: 0, 2: 3}, after: 5).describe(),
      'rating (2 photos)',
    );
    expect(
      const FlagUndoEntry(
        before: {1: PickFlag.none},
        after: PickFlag.reject,
      ).describe(),
      'flag',
    );
    expect(
      const ColorUndoEntry(
        before: {1: ColorLabel.none, 2: ColorLabel.red, 3: ColorLabel.none},
        after: ColorLabel.blue,
      ).describe(),
      'colour label (3 photos)',
    );
    expect(
      const RotationUndoEntry(photoIds: [1, 2], quarterTurnsCW: 1).describe(),
      'rotation (2 photos)',
    );
  });
}
