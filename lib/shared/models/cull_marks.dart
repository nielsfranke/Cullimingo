import 'package:cullimingo/app/theme/tokens.dart';
import 'package:flutter/material.dart';

/// Pick/reject flag (Photo Mechanic style). Stored as the enum index in drift.
///
/// ⚠️ This does NOT round-trip to Lightroom via XMP (no universal standard);
/// see `BUILD_PLAN.md` §6.3. We persist it under a private namespace later.
enum PickFlag {
  /// No flag set.
  none,

  /// Picked / keeper.
  pick,

  /// Rejected.
  reject,
}

/// Colour label. Stored as the enum index in drift; mapped to the palette in
/// [AppColors]. Indices align with the `6 7 8 9 0` keyboard map (§7).
enum ColorLabel {
  /// No colour label.
  none,

  /// Red.
  red,

  /// Yellow.
  yellow,

  /// Green.
  green,

  /// Blue.
  blue,

  /// Purple.
  purple,
}

/// UI helpers for [ColorLabel].
extension ColorLabelX on ColorLabel {
  /// The swatch colour for this label, or `null` for [ColorLabel.none].
  Color? get color => switch (this) {
    ColorLabel.none => null,
    ColorLabel.red => AppColors.labelRed,
    ColorLabel.yellow => AppColors.labelYellow,
    ColorLabel.green => AppColors.labelGreen,
    ColorLabel.blue => AppColors.labelBlue,
    ColorLabel.purple => AppColors.labelPurple,
  };

  /// Capitalised display name (e.g. "Red") for tooltips and labels — so colour
  /// meaning is never conveyed by the swatch alone.
  String get displayName => switch (this) {
    ColorLabel.none => 'None',
    ColorLabel.red => 'Red',
    ColorLabel.yellow => 'Yellow',
    ColorLabel.green => 'Green',
    ColorLabel.blue => 'Blue',
    ColorLabel.purple => 'Purple',
  };
}
