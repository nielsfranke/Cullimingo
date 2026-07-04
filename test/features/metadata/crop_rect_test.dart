import 'package:cullimingo/features/metadata/domain/crop_rect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CropRect.corners', () {
    test('an un-rotated crop yields the plain axis-aligned corners', () {
      const crop = CropRect(left: 0.1, top: 0.2, right: 0.8, bottom: 0.9);
      final pts = crop.corners(offX: 0, offY: 0, w: 100, h: 100);
      expect(pts, [(10.0, 20.0), (80.0, 20.0), (80.0, 90.0), (10.0, 90.0)]);
    });

    test('honours the display box offset', () {
      const crop = CropRect(left: 0, top: 0, right: 1, bottom: 1);
      final pts = crop.corners(offX: 5, offY: 7, w: 10, h: 20);
      expect(pts, [(5.0, 7.0), (15.0, 7.0), (15.0, 27.0), (5.0, 27.0)]);
    });

    test('a positive angle tilts the box clockwise in screen space', () {
      // Centred square, rotated about its centre. Clockwise (x-right, y-down)
      // pushes the top edge down on the right and up on the left.
      const crop = CropRect(
        left: 0.25,
        top: 0.25,
        right: 0.75,
        bottom: 0.75,
        angle: 10,
      );
      final pts = crop.corners(offX: 0, offY: 0, w: 100, h: 100);
      final (tlx, tly) = pts[0];
      final (_, tryy) = pts[1];
      // Centre is (50,50); corners stay equidistant from it (rigid rotation).
      double dist(double x, double y) =>
          (x - 50) * (x - 50) + (y - 50) * (y - 50);
      expect(dist(tlx, tly), closeTo(dist(25, 25), 1e-6));
      // Clockwise: top-right corner moves *down* (larger y) vs the flat 25.
      expect(tryy, greaterThan(25));
      // ...and the top-left corner moves *up* (smaller y).
      expect(tly, lessThan(25));
    });

    test(
      'rotation is rigid — opposite corners stay symmetric about centre',
      () {
        const crop = CropRect(
          left: 0.1,
          top: 0.1,
          right: 0.9,
          bottom: 0.9,
          angle: 30,
        );
        final pts = crop.corners(offX: 0, offY: 0, w: 200, h: 200);
        final (tlx, tly) = pts[0];
        final (brx, bry) = pts[2];
        // Centre (100,100) is the midpoint of the two diagonal corners.
        expect((tlx + brx) / 2, closeTo(100, 1e-6));
        expect((tly + bry) / 2, closeTo(100, 1e-6));
      },
    );
  });
}
