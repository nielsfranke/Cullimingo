import 'dart:ui';

import 'package:cullimingo/features/cull/domain/loupe_zoom.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LoupeZoom', () {
    test('is inert until the native size is known', () {
      const z = LoupeZoom(intrinsic: null, viewport: Size(1000, 1000));
      expect(z.fitted, isNull);
      expect(z.hundredScale, isNull);
      expect(z.minScale, 1.0);
      expect(z.maxScale, LoupeZoom.zoomCeiling);
    });

    test('downscaled fit: 100% is above Fit, can shrink no further', () {
      // A 4000×2000 image fit into 1000×1000 → contained at 1000×500.
      const z = LoupeZoom(
        intrinsic: Size(4000, 2000),
        viewport: Size(1000, 1000),
      );
      expect(z.fitted, const Size(1000, 500));
      expect(z.hundredScale, 4.0); // 4000 / 1000
      expect(z.minScale, 1.0); // Fit is the floor
      expect(z.maxScale, 4.0); // ceiling already covers 100%
    });

    test('upscaled fit: 100% is below Fit, slider may shrink to native', () {
      // A 500×500 image in a 2000×2000 viewport → Fit upscales 4×.
      const z = LoupeZoom(
        intrinsic: Size(500, 500),
        viewport: Size(2000, 2000),
      );
      expect(z.fitted, const Size(2000, 2000));
      expect(z.hundredScale, 0.25); // 500 / 2000
      expect(z.minScale, 0.25); // can shrink to real pixels
      expect(z.maxScale, 4.0);
    });

    test('exact fit: 100% equals Fit', () {
      const z = LoupeZoom(
        intrinsic: Size(1000, 500),
        viewport: Size(1000, 1000),
      );
      expect(z.fitted, const Size(1000, 500));
      expect(z.hundredScale, 1.0);
      expect(z.minScale, 1.0);
      expect(z.maxScale, 4.0);
    });

    test('maxScale stretches past the ceiling for huge images', () {
      // 100% needs 6× here, beyond the 4× ceiling — slider must still reach it.
      const z = LoupeZoom(
        intrinsic: Size(6000, 3000),
        viewport: Size(1000, 1000),
      );
      expect(z.hundredScale, 6.0);
      expect(z.maxScale, 6.0);
    });
  });

  group('mode persistence', () {
    // 100% is 2× Fit here (2000px image fitted to 1000px viewport).
    const z = LoupeZoom(
      intrinsic: Size(2000, 1000),
      viewport: Size(1000, 1000),
    );

    test('modeForScale classifies Fit / 100% / custom', () {
      expect(z.modeForScale(1), LoupeZoomMode.fit);
      expect(z.modeForScale(2), LoupeZoomMode.hundred); // == hundredScale
      expect(z.modeForScale(1.5), LoupeZoomMode.custom);
    });

    test('scaleForMode is the inverse for the current image', () {
      expect(z.scaleForMode(LoupeZoomMode.fit), 1);
      expect(z.scaleForMode(LoupeZoomMode.hundred), 2);
      expect(z.scaleForMode(LoupeZoomMode.custom, custom: 1.5), 1.5);
    });

    test('100% restored on a differently-sized photo lands on real 100%', () {
      // The user picked 100% on the 2× image above. On a 4× image, restoring a
      // raw "2.0" would be wrong — scaleForMode recomputes to the new 100%.
      const bigger = LoupeZoom(
        intrinsic: Size(4000, 2000),
        viewport: Size(1000, 1000),
      );
      expect(bigger.scaleForMode(LoupeZoomMode.hundred), 4);
    });

    test('100% scale is null until the native size is known', () {
      const unknown = LoupeZoom(intrinsic: null, viewport: Size(1000, 1000));
      expect(unknown.scaleForMode(LoupeZoomMode.hundred), isNull);
      expect(unknown.modeForScale(1), LoupeZoomMode.fit);
    });
  });
}
