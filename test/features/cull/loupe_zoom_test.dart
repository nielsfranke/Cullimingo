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

  group('rotation', () {
    test('a quarter-turn fits the image on its side', () {
      // 3000×1000 turned 90° lays out as 1000×3000: contained in 1000×1000 at
      // 333×1000, so 100% is 3× of the on-screen width (1000 px) — not the 1×
      // the unturned fit would give.
      const z = LoupeZoom(
        intrinsic: Size(3000, 1000),
        viewport: Size(1000, 1000),
        quarterTurns: 1,
      );
      expect(z.fitted, const Size(1000 / 3, 1000));
      expect(z.hundredScale, closeTo(3, 1e-9)); // 1000 / (1000 / 3)
    });

    test('a half-turn changes nothing', () {
      const z = LoupeZoom(
        intrinsic: Size(3000, 1000),
        viewport: Size(1000, 1000),
        quarterTurns: 2,
      );
      expect(z.fitted, const Size(1000, 1000 / 3));
      expect(z.hundredScale, 3);
    });
  });

  group('pan and focal zoom', () {
    const z = LoupeZoom(
      intrinsic: Size(4000, 2000),
      viewport: Size(1000, 800),
    );

    test('clampTranslation keeps a magnified view on the content', () {
      // At 2× the content is 2000×1600: translation may run 0 … -1000/-800.
      expect(z.clampTranslation(const Offset(50, 50), 2), Offset.zero);
      expect(
        z.clampTranslation(const Offset(-5000, -5000), 2),
        const Offset(-1000, -800),
      );
      expect(
        z.clampTranslation(const Offset(-300, -200), 2),
        const Offset(-300, -200),
      );
    });

    test('clampTranslation pins Fit to the origin', () {
      expect(z.clampTranslation(const Offset(-40, 30), 1), Offset.zero);
    });

    test('clampTranslation keeps a shrunk view inside the viewport', () {
      // At 0.5× the content is 500×400: it may sit anywhere 0 … 500/400.
      expect(
        z.clampTranslation(const Offset(-10, 900), 0.5),
        const Offset(0, 400),
      );
    });

    test('zooming keeps the content under the focal point in place', () {
      // From Fit, zoom 4× about (200, 300): that scene point stays put.
      final t = z.translationForZoom(
        scale: 1,
        translation: Offset.zero,
        target: 4,
        focal: const Offset(200, 300),
      );
      expect(t, const Offset(200 - 200 * 4, 300 - 300 * 4));
    });

    test('zooming about a panned view keeps its focal point too', () {
      // At 2× panned to (-400, -300), viewport (500, 400) shows scene
      // (450, 350). Zooming to 4× about it keeps it there.
      final t = z.translationForZoom(
        scale: 2,
        translation: const Offset(-400, -300),
        target: 4,
        focal: const Offset(500, 400),
      );
      expect(t, const Offset(500 - 450 * 4, 400 - 350 * 4));
    });

    test('zooming in at an edge stays on the content', () {
      // A focal point at the very corner would leave nothing to pull from;
      // the clamp keeps the view on the image.
      final t = z.translationForZoom(
        scale: 1,
        translation: Offset.zero,
        target: 4,
        focal: const Offset(1000, 800),
      );
      expect(t, const Offset(-3000, -2400));
      // Zooming back to Fit always lands at the origin.
      expect(
        z.translationForZoom(
          scale: 4,
          translation: t,
          target: 1,
          focal: const Offset(123, 456),
        ),
        Offset.zero,
      );
    });
  });
}
