import 'package:cullimingo/features/cull/domain/cull_key_mappings.dart';
import 'package:cullimingo/features/cull/domain/cull_shortcuts.dart';
import 'package:cullimingo/features/cull/domain/grid_navigation.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('loupeStepFor', () {
    test('left/up and [ page backwards', () {
      expect(loupeStepFor(LogicalKeyboardKey.arrowLeft), -1);
      expect(loupeStepFor(LogicalKeyboardKey.arrowUp), -1);
      expect(loupeStepFor(LogicalKeyboardKey.bracketLeft), -1);
    });
    test('right/down and ] page forwards', () {
      expect(loupeStepFor(LogicalKeyboardKey.arrowRight), 1);
      expect(loupeStepFor(LogicalKeyboardKey.arrowDown), 1);
      expect(loupeStepFor(LogicalKeyboardKey.bracketRight), 1);
    });
    test('other keys are null', () {
      expect(loupeStepFor(LogicalKeyboardKey.space), isNull);
    });
  });

  group('gridDirectionFor', () {
    test('maps arrows to directions', () {
      expect(
        gridDirectionFor(LogicalKeyboardKey.arrowLeft),
        GridDirection.left,
      );
      expect(
        gridDirectionFor(LogicalKeyboardKey.arrowRight),
        GridDirection.right,
      );
      expect(gridDirectionFor(LogicalKeyboardKey.arrowUp), GridDirection.up);
      expect(
        gridDirectionFor(LogicalKeyboardKey.arrowDown),
        GridDirection.down,
      );
    });
    test('non-arrow keys are null', () {
      expect(gridDirectionFor(LogicalKeyboardKey.keyP), isNull);
    });
  });

  group('ratingForAction', () {
    test('maps rate actions to stars', () {
      expect(ratingForAction(CullAction.rate1), 1);
      expect(ratingForAction(CullAction.rate5), 5);
    });
    test('non-rate actions and null are null', () {
      expect(ratingForAction(CullAction.pick), isNull);
      expect(ratingForAction(null), isNull);
    });
  });

  group('numpadRatingFor', () {
    test('maps numpad 1-5 to stars', () {
      expect(numpadRatingFor(LogicalKeyboardKey.numpad1), 1);
      expect(numpadRatingFor(LogicalKeyboardKey.numpad5), 5);
    });
    test('non-numpad keys are null', () {
      expect(numpadRatingFor(LogicalKeyboardKey.digit1), isNull);
    });
  });

  group('colorForAction', () {
    test('maps colour actions to labels', () {
      expect(colorForAction(CullAction.colorRed), ColorLabel.red);
      expect(colorForAction(CullAction.colorPurple), ColorLabel.purple);
    });
    test('non-colour actions and null are null', () {
      expect(colorForAction(CullAction.rate1), isNull);
      expect(colorForAction(null), isNull);
    });
  });
}
