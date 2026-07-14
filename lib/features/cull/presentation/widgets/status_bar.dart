import 'package:cullimingo/app/theme/tokens.dart';
import 'package:flutter/material.dart';

/// Slim bottom status bar (`BUILD_PLAN.md` §7): photo / selection counts on
/// the left, a compact export action on the right. Replaces the old
/// full-width "Export N Photos" bar — a permanent wizard-sized CTA cost a
/// whole thumbnail row for an action that lives in ⌘/Ctrl-S anyway.
class StatusBar extends StatelessWidget {
  /// Creates the status bar.
  const StatusBar({
    required this.total,
    required this.filteredCount,
    required this.selectedCount,
    this.onExport,
    super.key,
  });

  /// All photos in the open folder (unfiltered).
  final int total;

  /// Photos passing the active filter (what the grid shows).
  final int filteredCount;

  /// Photos currently selected.
  final int selectedCount;

  /// Starts an export of the selection (or the filtered set when nothing is
  /// selected), or null to disable the button.
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    // "165 photos · 2 selected", or "12 of 165 photos · 2 selected" when a
    // filter is narrowing the grid.
    final counts = StringBuffer()
      ..write(
        filteredCount == total
            ? '$total photo${total == 1 ? '' : 's'}'
            : '$filteredCount of $total photos',
      )
      ..write(' · $selectedCount selected');

    final n = selectedCount > 0 ? selectedCount : filteredCount;
    final label = selectedCount > 0
        ? 'Export $n selected'
        : 'Export $n photo${n == 1 ? '' : 's'}';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              counts.toString(),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Tooltip(
            message: 'Export (⌘/Ctrl S)',
            child: FilledButton.icon(
              onPressed: onExport,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              icon: const Icon(Icons.ios_share, size: 16),
              label: Text(label),
            ),
          ),
        ],
      ),
    );
  }
}
