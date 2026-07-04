import 'dart:async';

import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/core/settings/app_settings.dart';
import 'package:cullimingo/features/cull/domain/similarity_sensitivity.dart';
import 'package:flutter/material.dart';

/// Asks how aggressively "Find similar photos" should group (`BUILD_PLAN.md`
/// §8) and returns the chosen [SimilaritySensitivity], or null on cancel. The
/// choice is persisted (background) so it pre-selects next time.
Future<SimilaritySensitivity?> showFindSimilarDialog(
  BuildContext context,
) async {
  // Load the remembered choice BEFORE building so a late async load can't reset
  // the user's pick mid-dialog (see the Settings dialog for the same fix).
  final settings = await AppSettings.load();
  final initial = SimilaritySensitivity.fromName(
    settings.similaritySensitivity,
  );
  if (!context.mounted) return null;
  return showDialog<SimilaritySensitivity>(
    context: context,
    builder: (_) => _FindSimilarDialog(initial: initial),
  );
}

class _FindSimilarDialog extends StatefulWidget {
  const _FindSimilarDialog({required this.initial});

  final SimilaritySensitivity initial;

  @override
  State<_FindSimilarDialog> createState() => _FindSimilarDialogState();
}

class _FindSimilarDialogState extends State<_FindSimilarDialog> {
  late SimilaritySensitivity _selected = widget.initial;

  void _run() {
    final chosen = _selected;
    unawaited(
      AppSettings.load().then((s) => s.setSimilaritySensitivity(chosen.name)),
    );
    Navigator.of(context).pop(chosen);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Find similar photos'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Sensitivity',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final s in SimilaritySensitivity.values)
              _SensitivityRow(
                sensitivity: s,
                selected: _selected == s,
                onTap: () => setState(() => _selected = s),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _run, child: const Text('Find similar')),
      ],
    );
  }
}

class _SensitivityRow extends StatelessWidget {
  const _SensitivityRow({
    required this.sensitivity,
    required this.selected,
    required this.onTap,
  });

  final SimilaritySensitivity sensitivity;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
                    Text(
                      sensitivity.label,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sensitivity.blurb,
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
