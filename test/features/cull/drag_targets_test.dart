import 'package:cullimingo/features/cull/domain/drag_targets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dragTargets', () {
    test('dragging a photo in the selection drags the whole selection', () {
      expect(dragTargets(2, {1, 2, 3}), {1, 2, 3});
    });

    test('dragging a photo outside the selection drags only it', () {
      expect(dragTargets(9, {1, 2, 3}), {9});
    });

    test('no selection drags only the dragged photo', () {
      expect(dragTargets(5, const {}), {5});
    });

    test('single-selected dragged photo drags just itself', () {
      expect(dragTargets(7, {7}), {7});
    });
  });
}
