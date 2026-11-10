import 'dart:math' as math;
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

    test('HiDPI: 100% is one image pixel per physical pixel', () {
      // 4000×2000 into 1000×1000 logical on a 2× screen: Fit shows it at
      // 2000 physical pixels wide, so 1:1 is 2× Fit, not 4×.
      const z = LoupeZoom(
        intrinsic: Size(4000, 2000),
        viewport: Size(1000, 1000),
        devicePixelRatio: 2,
      );
      expect(z.hundredScale, 2.0);
      expect(z.modeForScale(2), LoupeZoomMode.hundred);
      // Fractional scaling (150%) lands between.
      const f = LoupeZoom(
        intrinsic: Size(4000, 2000),
        viewport: Size(1000, 1000),
        devicePixelRatio: 1.5,
      );
      expect(f.hundredScale, closeTo(4000 / 1500, 1e-9));
    });

    test('pixel-exact (unfiltered) from 100% upwards only', () {
      const z = LoupeZoom(
        intrinsic: Size(4000, 2000),
        viewport: Size(1000, 1000),
        devicePixelRatio: 2,
      );
      expect(z.isPixelExact(1), isFalse); // Fit downscales: keep smoothing
      expect(z.isPixelExact(1.9), isFalse);
      expect(z.isPixelExact(2), isTrue);
      expect(z.isPixelExact(3), isTrue);
      const unknown = LoupeZoom(intrinsic: null, viewport: Size(1000, 1000));
      expect(unknown.isPixelExact(4), isFalse);
      // A small image Fit already upscales: Fit stays smooth, 1:1 doesn't.
      const small = LoupeZoom(
        intrinsic: Size(800, 400),
        viewport: Size(1000, 1000),
        devicePixelRatio: 2,
      );
      expect(small.hundredScale, 0.4);
      expect(small.isPixelExact(1), isFalse);
      expect(small.isPixelExact(0.4), isTrue);
      expect(small.isPixelExact(2), isTrue);
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

  group('eased zoom', () {
    const z = LoupeZoom(
      intrinsic: Size(4000, 2000),
      viewport: Size(1000, 800),
    );

    ({double scale, Offset translation}) step(
      double progress, {
      double from = 1,
      Offset translation = Offset.zero,
      double target = 4,
      Offset focal = const Offset(200, 300),
    }) => z.zoomStep(
      scale: from,
      translation: translation,
      target: target,
      focal: focal,
      progress: progress,
    );

    test('the ends are the plain zoom — no drift from the snapping path', () {
      final start = step(0);
      expect(start.scale, 1);
      expect(start.translation, Offset.zero);

      final end = step(1);
      final snapped = z.translationForZoom(
        scale: 1,
        translation: Offset.zero,
        target: 4,
        focal: const Offset(200, 300),
      );
      expect(end.scale, closeTo(4, 1e-12));
      expect(end.translation.dx, closeTo(snapped.dx, 1e-12));
      expect(end.translation.dy, closeTo(snapped.dy, 1e-12));
    });

    test('the scale moves by ratio, not by amount', () {
      // Halfway in progress is the geometric mean, not the arithmetic one:
      // 1× → 4× passes 2×, and equal steps are equal multiples.
      expect(step(0.5).scale, closeTo(2, 1e-12));
      expect(step(0.25).scale, closeTo(math.sqrt(2), 1e-12));
      expect(step(0.75).scale, closeTo(2 * math.sqrt(2), 1e-12));
      expect(
        step(0.4).scale / step(0.2).scale,
        closeTo(step(0.6).scale / step(0.4).scale, 1e-12),
      );
    });

    test('the focal point holds still on every step', () {
      const focal = Offset(200, 300);
      for (final progress in [0.1, 0.25, 0.5, 0.75, 0.9]) {
        final s = step(progress);
        final scene = (focal - s.translation) / s.scale;
        expect(scene.dx, closeTo(focal.dx, 1e-9), reason: 'at $progress');
        expect(scene.dy, closeTo(focal.dy, 1e-9), reason: 'at $progress');
      }
    });

    test('every step stays clamped to the image, not just the ends', () {
      // Zooming out of a corner-panned view: no mid-trip frame may open a gap
      // past the image edge (the content must still cover the viewport).
      for (final progress in [0.1, 0.3, 0.5, 0.7, 0.9]) {
        final s = step(
          progress,
          from: 4,
          translation: const Offset(-1000, -800),
          target: 1,
          focal: const Offset(500, 400),
        );
        // Above Fit the content spans `1000 * scale`: the left/top edge may
        // run from `1000 * (1 - scale)` (fully panned) to 0 (flush).
        final slack = Offset(1000 * (1 - s.scale), 800 * (1 - s.scale));
        expect(
          s.translation.dx,
          inInclusiveRange(slack.dx, 0),
          reason: 'x at $progress',
        );
        expect(
          s.translation.dy,
          inInclusiveRange(slack.dy, 0),
          reason: 'y at $progress',
        );
      }
    });

    test('zooming out eases back to Fit at the origin', () {
      final s = step(
        1,
        from: 4,
        translation: const Offset(-1500, -900),
        target: 1,
        focal: const Offset(250, 600),
      );
      expect(s.scale, closeTo(1, 1e-12));
      expect(s.translation, Offset.zero);
    });
  });
}
