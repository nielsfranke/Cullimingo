import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/core/settings/performance_preset.dart';
import 'package:flutter/material.dart';

/// Radio list of the [PerformancePreset]s (Lean / Balanced / Max) showing each
/// one's resolved thumbnail px + RAM budget and a "Recommended" badge. It is
/// *controlled*: the parent owns the RAM-dependent [available]/[recommended]
/// sets and the [selected] preset. Extracted so the Settings dialog can host
/// it (`BUILD_PLAN.md` §2, §8).
class PerformancePresetSelector extends StatelessWidget {
  /// Creates the preset selector.
  const PerformancePresetSelector({
    required this.available,
    required this.recommended,
    required this.selected,
    required this.totalRamBytes,
    required this.onSelect,
    super.key,
  });

  /// Presets offered for this machine (Max is hidden on low RAM).
  final List<PerformancePreset> available;

  /// The RAM-derived recommended preset (badged).
  final PerformancePreset recommended;

  /// The currently chosen preset, or null while loading.
  final PerformancePreset? selected;

  /// Total physical RAM, used to resolve each preset's budget for the blurb.
  final int? totalRamBytes;

  /// Called when a preset row is tapped.
  final ValueChanged<PerformancePreset> onSelect;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final preset in available)
        _PresetRow(
          preset: preset,
          settings: resolvePerformance(preset, totalBytes: totalRamBytes),
          selected: selected == preset,
          recommended: preset == recommended,
          onTap: () => onSelect(preset),
        ),
    ],
  );
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({
    required this.preset,
    required this.settings,
    required this.selected,
    required this.recommended,
    required this.onTap,
  });

  final PerformancePreset preset;
  final PerformanceSettings settings;
  final bool selected;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mb = settings.ramBudgetBytes ~/ (1024 * 1024);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: selected ? AppColors.accent : AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          preset.label,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (recommended) ...[
                          const SizedBox(width: AppSpacing.sm),
                          const _RecommendedBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${preset.blurb}  ·  ${settings.thumbLongEdge}px · '
                      '${mb}MB',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecommendedBadge extends StatelessWidget {
  const _RecommendedBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: AppColors.accent.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(4),
    ),
    child: const Text(
      'Recommended',
      style: TextStyle(color: AppColors.accent, fontSize: 10),
    ),
  );
}
