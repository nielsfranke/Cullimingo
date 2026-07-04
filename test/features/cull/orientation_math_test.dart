import 'package:cullimingo/features/cull/domain/orientation_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('rotateOrientation', () {
    test('cycles the pure-rotation states clockwise', () {
      // 1 (normal) → 6 (90 CW) → 3 (180) → 8 (90 CCW) → back to 1.
      expect(rotateOrientation(1, 1), 6);
      expect(rotateOrientation(6, 1), 3);
      expect(rotateOrientation(3, 1), 8);
      expect(rotateOrientation(8, 1), 1);
    });

    test('a full turn is a no-op', () {
      for (var o = 1; o <= 8; o++) {
        expect(rotateOrientation(o, 4), o, reason: 'orientation $o');
      }
    });

    test('counter-clockwise (negative) is the inverse of clockwise', () {
      expect(rotateOrientation(1, -1), 8); // one CCW from normal
      expect(rotateOrientation(1, -1), rotateOrientation(1, 3));
    });

    test('composes multiple turns', () {
      expect(rotateOrientation(1, 2), 3); // 180°
      expect(rotateOrientation(6, 2), 8); // 90CW + 180 = 90CCW
    });

    test('cycles the mirrored states without leaving the mirror family', () {
      // 2,7,4,5 are the mirrored quartet; four CW turns return to start and no
      // turn ever lands on a non-mirrored state.
      const mirrored = {2, 4, 5, 7};
      var o = 2;
      for (var i = 0; i < 4; i++) {
        o = rotateOrientation(o, 1);
        expect(mirrored.contains(o), isTrue, reason: 'step $i landed on $o');
      }
      expect(o, 2);
    });

    test('treats an out-of-range orientation as normal', () {
      expect(rotateOrientation(0, 1), 6);
      expect(rotateOrientation(99, 0), 1);
    });
  });

  group('normalizeQuarterTurns', () {
    test('wraps into 0–3', () {
      expect(normalizeQuarterTurns(0), 0);
      expect(normalizeQuarterTurns(4), 0);
      expect(normalizeQuarterTurns(5), 1);
      expect(normalizeQuarterTurns(-1), 3);
      expect(normalizeQuarterTurns(-4), 0);
    });
  });
}
