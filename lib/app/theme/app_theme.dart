import 'package:cullimingo/app/theme/tokens.dart';
import 'package:flutter/material.dart';

/// Builds the dark, dense, keyboard-driven Cullimingo theme from the design
/// tokens in [AppColors]. See `BUILD_PLAN.md` §7.
ThemeData buildDarkTheme() {
  const colorScheme = ColorScheme.dark(
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    primary: AppColors.accent,
    onPrimary: AppColors.textPrimary,
    secondary: AppColors.selection,
    onSecondary: AppColors.bgBase,
    outline: AppColors.border,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bgBase,
    // Dropdown popups / menus use canvasColor — elevated so they stand out
    // against the surface-coloured panels behind them.
    canvasColor: AppColors.surfaceElevated,
    dividerColor: AppColors.border,
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    ),
    // Visible track on the dark background (otherwise only the thumb + active
    // portion showed).
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.accent,
      inactiveTrackColor: AppColors.border,
      thumbColor: AppColors.accent,
      trackHeight: 4,
      overlayColor: AppColors.accent.withValues(alpha: 0.15),
    ),
    // Dropdown + popup menus: elevated surface, no M3 tint wash, hairline edge.
    dropdownMenuTheme: const DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(AppColors.surfaceElevated),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: AppColors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
    ),
    // Boxed inputs so fields read as fields, not flat text.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceElevated,
      isDense: true,
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AppColors.accent),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    ),
    // Dialogs: flat dark surface (no M3 tint wash), rounded, so every dialog —
    // Settings, Find similar, Export, About … — reads the same.
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      titleTextStyle: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 14,
      ),
    ),
    // Tooltips: elevated chip with a hairline, matching the menus.
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      textStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
    ),
    // Checkboxes (dialog_kit DialogCheckbox): accent when ticked.
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.accent
            : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(AppColors.textPrimary),
      side: const BorderSide(color: AppColors.textSecondary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    // Segmented buttons (ContactSheet Send/Pull): accent selection.
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.surfaceElevated,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.textPrimary
              : AppColors.textSecondary,
        ),
        side: const WidgetStatePropertyAll(
          BorderSide(color: AppColors.border),
        ),
      ),
    ),
    // Consistent button corners (match chips/inputs at AppRadius.sm).
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    ),
  );
}
