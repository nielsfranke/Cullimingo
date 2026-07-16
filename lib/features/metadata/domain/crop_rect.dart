import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;

/// A non-destructive crop read from a Lightroom / Camera-Raw develop record
/// (the XMP `crs:` namespace). Cullimingo only ever *displays* this — it is
/// never a crop editor (Hard Rule 7: not a RAW developer).
///
/// [left]/[top]/[right]/[bottom] are fractions of the full frame (0–1), as
/// Camera Raw stores them; [angle] is the straighten angle in degrees.
@immutable
class CropRect {
  /// Creates a crop rectangle.
  const CropRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.angle = 0,
  });

  /// Left edge as a fraction of the frame width (0–1).
  final double left;

  /// Top edge as a fraction of the frame height (0–1).
  final double top;

  /// Right edge as a fraction of the frame width (0–1).
  final double right;

  /// Bottom edge as a fraction of the frame height (0–1).
  final double bottom;

  /// Straighten angle in degrees (Camera Raw `crs:CropAngle`).
  final double angle;

  /// Crop width as a fraction of the frame (0–1).
  double get width => (right - left).clamp(0.0, 1.0);

  /// Crop height as a fraction of the frame (0–1).
  double get height => (bottom - top).clamp(0.0, 1.0);

  /// Whether this crop actually removes anything — a full-frame rectangle with
  /// no rotation is not worth flagging in the UI.
  bool get isMeaningful =>
      angle.abs() > 0.001 ||
      left > 0.001 ||
      top > 0.001 ||
      right < 0.999 ||
      bottom < 0.999;

  /// The kept rectangle's four corners — top-left, top-right, bottom-right,
  /// bottom-left — placed inside the display box `[offX, offY, w, h]` and each
  /// rotated about the rectangle centre by [angle].
  ///
  /// Camera Raw stores the crop axis-aligned in the *straightened* frame, so on
  /// the un-straightened original it appears tilted: a positive (clockwise)
  /// `CropAngle` tilts the box clockwise in screen space (x-right, y-down). The
  /// display box is a uniform scaling of the pixel rect, so rotating in these
  /// coordinates reproduces the true rigid rotation. Zero angle yields the
  /// plain axis-aligned corners.
  List<(double x, double y)> corners({
    required double offX,
    required double offY,
    required double w,
    required double h,
  }) {
    final l = offX + left * w;
    final r = offX + right * w;
    final t = offY + top * h;
    final b = offY + bottom * h;
    final cx = (l + r) / 2;
    final cy = (t + b) / 2;
    final theta = angle * math.pi / 180;
    final cos = math.cos(theta);
    final sin = math.sin(theta);
    (double, double) rotate(double x, double y) {
      final dx = x - cx;
      final dy = y - cy;
      return (cx + dx * cos - dy * sin, cy + dx * sin + dy * cos);
    }

    return [rotate(l, t), rotate(r, t), rotate(r, b), rotate(l, b)];
  }

  // Value equality: the loupe rebuilds derive a fresh CropRect from the photo
  // row each frame, and the crop-overlay painter's shouldRepaint compares
  // delegates — identity equality would repaint on every rebuild.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CropRect &&
          other.left == left &&
          other.top == top &&
          other.right == right &&
          other.bottom == bottom &&
          other.angle == angle;

  @override
  int get hashCode => Object.hash(left, top, right, bottom, angle);
}
