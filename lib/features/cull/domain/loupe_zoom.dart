import 'dart:math' as math;
import 'dart:ui';

/// Which zoom the loupe is showing. Persisted across close/reopen so the user's
/// choice of Fit vs 100% sticks even though the absolute scale that means
/// "100%" differs per photo and viewport.
enum LoupeZoomMode {
  /// Whole frame fits the viewport (scale 1.0 relative to Fit).
  fit,

  /// One image-pixel per logical pixel (`hundredScale`).
  hundred,

  /// A specific scale the user dialled in with the slider / pinch.
  custom,
}

/// Pure zoom math for the loupe (`BUILD_PLAN.md` §7), kept out of the widget so
/// the Fit / 100% behaviour can be unit-tested in isolation.
///
/// Scale is expressed relative to **Fit**: `1.0` contains the whole frame in
/// the viewport; [hundredScale] renders one image pixel per logical pixel (the
/// focus-check view). The image's native size is unknown until it decodes, so
/// every getter copes with a `null` [intrinsic].
class LoupeZoom {
  /// Creates zoom math for an image of [intrinsic] native pixels shown in a
  /// [viewport] of logical pixels.
  const LoupeZoom({required this.intrinsic, required this.viewport});

  /// Native pixel size of the decoded preview, or `null` before it resolves.
  final Size? intrinsic;

  /// The loupe image-area size in logical pixels.
  final Size viewport;

  /// Hard ceiling on magnification beyond Fit, so the slider always has room
  /// even for tiny images.
  static const double zoomCeiling = 4;

  /// The image's fitted (Fit, `BoxFit.contain`) size in logical pixels.
  Size? get fitted {
    final i = intrinsic;
    if (i == null || i.isEmpty || viewport == Size.zero) return null;
    final s = math.min(viewport.width / i.width, viewport.height / i.height);
    return Size(i.width * s, i.height * s);
  }

  /// Scale (relative to Fit) that renders 1 image-pixel per logical pixel, or
  /// `null` until the native size is known. Below `1.0` when Fit upscales past
  /// native (a big window on a small image); above when Fit downscales.
  double? get hundredScale {
    final f = fitted;
    final i = intrinsic;
    if (f == null || i == null || f.width == 0) return null;
    return i.width / f.width;
  }

  /// Smallest scale the slider allows: Fit, unless 100% is *below* Fit (Fit was
  /// upscaling), in which case allow shrinking down to native so 100% is real.
  double get minScale {
    final h = hundredScale;
    return (h != null && h < 1) ? h : 1.0;
  }

  /// Largest scale the slider allows: at least [zoomCeiling], extended so 100%
  /// is always reachable even for images larger than the ceiling implies.
  double get maxScale => math.max(zoomCeiling, hundredScale ?? 1.0);

  static const double _epsilon = 0.01;

  /// Classifies an absolute [scale] (relative to Fit) into a [LoupeZoomMode] so
  /// the persisted choice records intent (Fit / 100%) rather than a raw number.
  LoupeZoomMode modeForScale(double scale) {
    if ((scale - 1).abs() < _epsilon) return LoupeZoomMode.fit;
    final h = hundredScale;
    if (h != null && (scale - h).abs() < _epsilon) return LoupeZoomMode.hundred;
    return LoupeZoomMode.custom;
  }

  /// The target scale for [mode] given the current image, or `null` when it
  /// can't be computed yet ([LoupeZoomMode.hundred] before the native size is
  /// known). [custom] is used for [LoupeZoomMode.custom].
  double? scaleForMode(LoupeZoomMode mode, {double custom = 1}) =>
      switch (mode) {
        LoupeZoomMode.fit => 1,
        LoupeZoomMode.hundred => hundredScale,
        LoupeZoomMode.custom => custom,
      };
}
