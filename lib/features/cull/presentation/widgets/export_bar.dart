import 'package:cullimingo/app/theme/tokens.dart';
import 'package:flutter/material.dart';

/// Compact non-modal progress card for a background job (export or upload) —
/// floats over the grid so culling continues while it runs (§6/§7b).
class ExportProgressCard extends StatelessWidget {
  /// Creates the progress card.
  const ExportProgressCard({
    required this.done,
    required this.total,
    required this.onCancel,
    this.verb = 'Exporting',
    super.key,
  });

  /// Items completed so far.
  final int done;

  /// Total items in the job.
  final int total;

  /// Called to cancel the job.
  final VoidCallback onCancel;

  /// The present-participle verb shown in the label ("Exporting", "Sending").
  final String verb;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: AppColors.scrim,
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$verb $done of $total…',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Cancel'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total == 0 ? null : done / total,
                backgroundColor: AppColors.border,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
