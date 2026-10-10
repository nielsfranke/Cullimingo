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
  const LoupeZoom({
    required this.intrinsic,
    required this.viewport,
    this.quarterTurns = 0,
  });

  /// Native pixel size of the decoded preview, or `null` before it resolves.
  final Size? intrinsic;

  /// The user's extra quarter-turns: an odd count lays the image on its side,
  /// so it fits the viewport with width and height swapped.
  final int quarterTurns;

  /// The loupe image-area size in logical pixels.
  final Size viewport;

  /// Hard ceiling on magnification beyond Fit, so the slider always has room
  /// even for tiny images.
  static const double zoomCeiling = 4;

  /// The image's fitted (Fit, `BoxFit.contain`) size in logical pixels.
  Size? get fitted {
    final i = _upright;
    if (i == null || i.isEmpty || viewport == Size.zero) return null;
    final s = math.min(viewport.width / i.width, viewport.height / i.height);
    return Size(i.width * s, i.height * s);
  }

  // [intrinsic] as laid out on screen, after the user's rotation.
  Size? get _upright {
    final i = intrinsic;
    return (i != null && quarterTurns.isOdd) ? i.flipped : i;
  }

  /// Scale (relative to Fit) that renders 1 image-pixel per logical pixel, or
  /// `null` until the native size is known. Below `1.0` when Fit upscales past
  /// native (a big window on a small image); above when Fit downscales.
  double? get hundredScale {
    final f = fitted;
    final i = _upright;
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

  /// The pan offset that keeps the content inside the viewport at [scale]:
  /// no black gap opens past the image area's edges while magnified, and a
  /// view shrunk below Fit stays within the viewport.
  ///
  /// The loupe transform is always a uniform scale plus a translation, so the
  /// content spans `translation` to `translation + viewport * scale`.
  Offset clampTranslation(Offset translation, double scale) {
    double clampAxis(double t, double extent) {
      final slack = extent - extent * scale;
      return t.clamp(math.min(0, slack), math.max(0, slack));
    }

    return Offset(
      clampAxis(translation.dx, viewport.width),
      clampAxis(translation.dy, viewport.height),
    );
  }

  /// The translation for zooming from [scale]/[translation] to [target] while
  /// the content under [focal] (a viewport position) stays put, as the mouse
  /// pointer does in Photo Mechanic's zoom. Clamped like [clampTranslation],
  /// so zooming near an edge pulls the view inside rather than off the image.
  Offset translationForZoom({
    required double scale,
    required Offset translation,
    required double target,
    required Offset focal,
  }) {
    final scene = (focal - translation) / scale;
    return clampTranslation(focal - scene * target, target);
  }
}
