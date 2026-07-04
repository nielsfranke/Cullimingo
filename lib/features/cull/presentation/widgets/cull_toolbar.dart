import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter/material.dart';

/// Clickable rating stars · pick/reject · colour swatches · keywords for one
/// [photo]. Each control toggles (clicking the active value clears it), like
/// the keyboard shortcuts. Shared by the loupe and the compare view.
class CullToolbar extends StatelessWidget {
  /// Creates a cull toolbar for [photo].
  const CullToolbar({
    required this.photo,
    required this.onRating,
    required this.onFlag,
    required this.onColor,
    required this.onKeywords,
    this.onRotateLeft,
    this.onRotateRight,
    this.onEditMetadata,
    super.key,
  });

  /// The photo whose marks are shown/edited.
  final Photo photo;

  /// Called with the new rating (0 clears).
  final ValueChanged<int> onRating;

  /// Called with the new pick/reject flag.
  final ValueChanged<PickFlag> onFlag;

  /// Called with the new colour label.
  final ValueChanged<ColorLabel> onColor;

  /// Opens the keyword editor.
  final VoidCallback onKeywords;

  /// Rotates the photo 90° counter-clockwise. Null hides the rotate buttons.
  final VoidCallback? onRotateLeft;

  /// Rotates the photo 90° clockwise. Null hides the rotate buttons.
  final VoidCallback? onRotateRight;

  /// Opens the structured metadata editor. Null hides the metadata button.
  final VoidCallback? onEditMetadata;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 1; i <= 5; i++)
              _IconButton(
                icon: i <= photo.rating
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                color: i <= photo.rating
                    ? AppColors.ratingGold
                    : AppColors.textSecondary,
                tooltip: 'Rate $i',
                onTap: () => onRating(photo.rating == i ? 0 : i),
              ),
          ],
        ),
        const SizedBox(width: AppSpacing.md),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _IconButton(
              icon: Icons.check_rounded,
              color: photo.flag == PickFlag.pick
                  ? AppColors.selection
                  : AppColors.textSecondary,
              tooltip: 'Pick (P)',
              onTap: () => onFlag(
                photo.flag == PickFlag.pick ? PickFlag.none : PickFlag.pick,
              ),
            ),
            _IconButton(
              icon: Icons.close_rounded,
              color: photo.flag == PickFlag.reject
                  ? AppColors.labelRed
                  : AppColors.textSecondary,
              tooltip: 'Reject (X)',
              onTap: () => onFlag(
                photo.flag == PickFlag.reject ? PickFlag.none : PickFlag.reject,
              ),
            ),
          ],
        ),
        const SizedBox(width: AppSpacing.md),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final label in ColorLabel.values)
              if (label != ColorLabel.none)
                _ColorSwatch(
                  label: label,
                  selected: photo.colorLabel == label,
                  onTap: () => onColor(
                    photo.colorLabel == label ? ColorLabel.none : label,
                  ),
                ),
          ],
        ),
        const SizedBox(width: AppSpacing.md),
        _IconButton(
          icon: photo.keywords.isEmpty
              ? Icons.label_outline_rounded
              : Icons.label_rounded,
          color: photo.keywords.isEmpty
              ? AppColors.textSecondary
              : AppColors.accent,
          tooltip: photo.keywords.isEmpty
              ? 'Keywords (K)'
              : 'Keywords: ${photo.keywords.join(', ')}',
          onTap: onKeywords,
        ),
        if (onEditMetadata != null)
          _IconButton(
            icon: Icons.edit_note_rounded,
            color: AppColors.textSecondary,
            tooltip: 'Edit metadata (M)',
            onTap: onEditMetadata!,
          ),
        if (onRotateLeft != null || onRotateRight != null) ...[
          const SizedBox(width: AppSpacing.md),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onRotateLeft != null)
                _IconButton(
                  icon: Icons.rotate_left_rounded,
                  color: AppColors.textSecondary,
                  tooltip: 'Rotate left',
                  onTap: onRotateLeft!,
                ),
              if (onRotateRight != null)
                _IconButton(
                  icon: Icons.rotate_right_rounded,
                  color: AppColors.textSecondary,
                  tooltip: 'Rotate right',
                  onTap: onRotateRight!,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A compact icon button for the cull toolbar.
class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      iconSize: 22,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      icon: Icon(icon, color: color),
    );
  }
}

/// A tappable colour-label swatch; ringed white when it is the active label.
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final ColorLabel label;
  final bool selected;
  final VoidCallback onTap;

  // The number key that applies each colour (matches the grid keymap, §7).
  // Purple has no number key (it's the odd colour out across cullers), so its
  // swatch shows no shortcut hint.
  static const Map<ColorLabel, String> _keys = {
    ColorLabel.red: '6',
    ColorLabel.yellow: '7',
    ColorLabel.green: '8',
    ColorLabel.blue: '9',
  };

  @override
  Widget build(BuildContext context) {
    final key = _keys[label];
    return IconButton(
      onPressed: onTap,
      tooltip: key == null ? label.name : '${label.name} ($key)',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 32),
      padding: EdgeInsets.zero,
      icon: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: label.color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Colors.white
                : Colors.black.withValues(alpha: 0.4),
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}
