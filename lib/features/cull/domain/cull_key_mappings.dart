import 'package:cullimingo/features/cull/domain/cull_shortcuts.dart';
import 'package:cullimingo/features/cull/domain/grid_navigation.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter/services.dart';

/// Pure key/action → value mappings for the cull keyboard handler. Kept out of
/// the widget so they can be unit-tested and reused by both the grid and the
/// compare view (`BUILD_PLAN.md` §7).

/// Loupe blit step for [key]: prev (-1) / next (+1). `[`/`]` plus all four
/// arrows, so either hand can page through without a row/column to worry about.
int? loupeStepFor(LogicalKeyboardKey key) => switch (key) {
  LogicalKeyboardKey.bracketLeft ||
  LogicalKeyboardKey.arrowLeft ||
  LogicalKeyboardKey.arrowUp => -1,
  LogicalKeyboardKey.bracketRight ||
  LogicalKeyboardKey.arrowRight ||
  LogicalKeyboardKey.arrowDown => 1,
  _ => null,
};

/// The grid navigation direction for an arrow [key], or null.
GridDirection? gridDirectionFor(LogicalKeyboardKey key) => switch (key) {
  LogicalKeyboardKey.arrowLeft => GridDirection.left,
  LogicalKeyboardKey.arrowRight => GridDirection.right,
  LogicalKeyboardKey.arrowUp => GridDirection.up,
  LogicalKeyboardKey.arrowDown => GridDirection.down,
  _ => null,
};

/// The star rating for a rate [action] (null for anything else).
int? ratingForAction(CullAction? action) => switch (action) {
  CullAction.rate1 => 1,
  CullAction.rate2 => 2,
  CullAction.rate3 => 3,
  CullAction.rate4 => 4,
  CullAction.rate5 => 5,
  _ => null,
};

/// Numpad 1–5 stay fixed rating keys regardless of rebinding.
int? numpadRatingFor(LogicalKeyboardKey key) => switch (key) {
  LogicalKeyboardKey.numpad1 => 1,
  LogicalKeyboardKey.numpad2 => 2,
  LogicalKeyboardKey.numpad3 => 3,
  LogicalKeyboardKey.numpad4 => 4,
  LogicalKeyboardKey.numpad5 => 5,
  _ => null,
};

/// The colour label for a colour [action] (null for anything else).
ColorLabel? colorForAction(CullAction? action) => switch (action) {
  CullAction.colorRed => ColorLabel.red,
  CullAction.colorYellow => ColorLabel.yellow,
  CullAction.colorGreen => ColorLabel.green,
  CullAction.colorBlue => ColorLabel.blue,
  CullAction.colorPurple => ColorLabel.purple,
  _ => null,
};
