import 'package:flutter/material.dart';

/// Cullimingo design tokens — the Aftershoot-style dark palette defined in
/// `BUILD_PLAN.md` §7. Keep this as the single source of truth for colours,
/// spacing and radii so the UI stays consistent across macOS and Linux.
abstract final class AppColors {
  /// Base window/background colour.
  static const Color bgBase = Color(0xFF0E0E10);

  /// Default surface (panels, bars).
  static const Color surface = Color(0xFF1A1A1D);

  /// Elevated surface (cards, menus, hovered cells).
  static const Color surfaceElevated = Color(0xFF26262B);

  /// Hairline borders and dividers.
  static const Color border = Color(0xFF2E2E34);

  /// Primary text.
  static const Color textPrimary = Color(0xFFF5F5F7);

  /// Secondary/muted text.
  static const Color textSecondary = Color(0xFFA0A0A8);

  /// Brand rose — the Cullimingo flamingo mark. Used for branding surfaces
  /// (logo, About). A muted flamingo pink/rosé.
  static const Color brandCoral = Color(0xFFE56C90);

  /// Primary accent — buttons and focus ring. A deeper flamingo rosé matching
  /// the app icon, kept dark enough for light text on accent-filled surfaces.
  static const Color accent = Color(0xFFDD4469);

  /// Selected-cell border (the green frames).
  static const Color selection = Color(0xFF22C55E);

  /// Rating star fill.
  static const Color ratingGold = Color(0xFFFACC15);

  /// Colour label: red.
  static const Color labelRed = Color(0xFFEF4444);

  /// Colour label: yellow.
  static const Color labelYellow = Color(0xFFEAB308);

  /// Colour label: green.
  static const Color labelGreen = Color(0xFF22C55E);

  /// Colour label: blue.
  static const Color labelBlue = Color(0xFF3B82F6);

  /// Colour label: purple.
  static const Color labelPurple = Color(0xFFA855F7);

  /// Drop-shadow / scrim colour for elevated overlays (popovers, dialogs).
  static const Color scrim = Color(0x66000000);
}

/// Spacing scale (4 / 8 / 12 / 16 / 24) from `BUILD_PLAN.md` §7.
abstract final class AppSpacing {
  /// 4px.
  static const double xs = 4;

  /// 8px.
  static const double sm = 8;

  /// 12px.
  static const double md = 12;

  /// 16px.
  static const double lg = 16;

  /// 24px.
  static const double xl = 24;
}

/// Corner radii. Cells use 8–10; subtle, crisp under Impeller.
abstract final class AppRadius {
  /// Small radius (8px) for chips and buttons.
  static const double sm = 8;

  /// Thumbnail cell radius (10px).
  static const double cell = 10;

  /// Medium radius (12px) for larger surfaces like dialogs.
  static const double md = 12;
}

/// Pop-up menus (toolbar dropdowns, the right-click thumbnail menu) open with
/// **no** open/close animation, so they appear the instant you click — speed is
/// the product. Pass this to every `PopupMenuButton.popUpAnimationStyle` and
/// `showMenu(popUpAnimationStyle: …)` so the behaviour is uniform and tunable
/// in one place (swap for `AnimationStyle(duration: …)` to soften it later).
const AnimationStyle kMenuAnimationStyle = AnimationStyle.noAnimation;
