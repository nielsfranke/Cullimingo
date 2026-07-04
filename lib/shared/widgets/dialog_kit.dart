import 'package:cullimingo/app/theme/tokens.dart';
import 'package:flutter/material.dart';

/// Shared form vocabulary for the app's dialogs (Import, Export, …) so they all
/// read the same: uppercase section headers, elevated boxed controls, a uniform
/// text-field decoration, leading checkboxes, and a path-with-Choose row. Use
/// these instead of hand-rolling per-dialog styling.

/// An uppercase, letter-spaced section header (e.g. `SOURCE`, `NAMING`).
class DialogSection extends StatelessWidget {
  /// Creates a section header showing [title] (upper-cased).
  const DialogSection(this.title, {super.key});

  /// The section name; rendered upper-cased.
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    ),
  );
}

/// Groups a set of related controls into a titled box so a dense dialog reads
/// as a few labelled panels (Photo-Mechanic style) instead of one long list.
/// Kept deliberately quiet: a hairline [AppColors.border] frame with no fill,
/// so the grouping stays subtle and the elevated controls inside (dropdowns,
/// fields) are what draw the eye. Lay several out in a `Row` of `Expanded`s to
/// get columns.
class DialogCard extends StatelessWidget {
  /// Creates a titled card wrapping [children].
  const DialogCard({required this.title, required this.children, super.key});

  /// The section header (upper-cased by [DialogSection]).
  final String title;

  /// The controls stacked inside the card.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DialogSection(title),
        const SizedBox(height: AppSpacing.xs),
        ...children,
      ],
    ),
  );
}

/// One selectable row in a dialog's left nav-rail (an icon + label). Selected
/// rows get the elevated fill and a bolder label; the rest stay quiet. Shared
/// so the metadata-template editor and the IPTC (M) editor read identically.
class DialogNavItem extends StatelessWidget {
  /// Creates a nav-rail row for [label] with a leading [icon].
  const DialogNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  /// The leading section icon.
  final IconData icon;

  /// The section name.
  final String label;

  /// Whether this row is the current section.
  final bool selected;

  /// Called when the row is tapped.
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.textPrimary : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: selected ? AppColors.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          onTap: onSelected,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps a control (dropdown, slider row, …) in an elevated, bordered box so it
/// reads as a control rather than flat text on the panel.
Widget dialogBox(Widget child) => Container(
  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
  decoration: BoxDecoration(
    color: AppColors.surfaceElevated,
    borderRadius: BorderRadius.circular(AppRadius.sm),
    border: Border.all(color: AppColors.border),
  ),
  child: child,
);

/// The standard text-field decoration for dialogs (fill/border come from the
/// global `inputDecorationTheme`).
InputDecoration dialogInputDecoration(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
);

/// A boxed dropdown with no underline and an elevated menu.
class DialogDropdown<T> extends StatelessWidget {
  /// Creates a boxed dropdown.
  const DialogDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
    super.key,
  });

  /// Current value.
  final T? value;

  /// Menu items.
  final List<DropdownMenuItem<T>> items;

  /// Selection callback.
  final ValueChanged<T?> onChanged;

  /// Optional hint shown when [value] is null.
  final String? hint;

  @override
  Widget build(BuildContext context) => dialogBox(
    DropdownButton<T>(
      value: value,
      isExpanded: true,
      underline: const SizedBox.shrink(),
      dropdownColor: AppColors.surfaceElevated,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      hint: hint == null ? null : Text(hint!),
      items: items,
      onChanged: onChanged,
    ),
  );
}

/// A leading-checkbox row with a secondary-coloured label and one fixed gap
/// between the box and the text (so every checkbox in a dialog lines up). An
/// optional [trailing] widget sits after the label (e.g. a "… N MB" field).
class DialogCheckbox extends StatelessWidget {
  /// Creates a dialog checkbox row.
  const DialogCheckbox({
    required this.value,
    required this.onChanged,
    required this.label,
    this.trailing,
    super.key,
  });

  /// Whether the box is ticked.
  final bool value;

  /// Toggle callback.
  final ValueChanged<bool?> onChanged;

  /// Label shown to the right of the box.
  final String label;

  /// Optional widget after the label (kept compact; the label hugs it).
  final Widget? trailing;

  static const TextStyle _labelStyle = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 13,
  );

  @override
  Widget build(BuildContext context) {
    final text = GestureDetector(
      onTap: () => onChanged(!value),
      child: Text(label, style: _labelStyle),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: Checkbox(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          if (trailing == null)
            Expanded(child: text)
          else ...[
            // Flexible so a long label wraps instead of overflowing when the
            // row sits in a narrow column (e.g. the export dialog's cards).
            Flexible(child: text),
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// A fixed-width [label] on the left with [child] filling the rest — keeps
/// inline-labelled controls (size, quality, …) aligned down the dialog.
class DialogField extends StatelessWidget {
  /// Creates a labelled field row.
  const DialogField({required this.label, required this.child, super.key});

  /// Left-hand label.
  final String label;

  /// The control.
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

/// A read-only path with a trailing "Choose…" button. [path] shows [hint] when
/// null.
class DialogPathRow extends StatelessWidget {
  /// Creates a path row.
  const DialogPathRow({
    required this.path,
    required this.onPick,
    required this.hint,
    super.key,
  });

  /// Current path, or null.
  final String? path;

  /// Picker callback.
  final VoidCallback onPick;

  /// Placeholder when [path] is null.
  final String hint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xs),
    child: Row(
      children: [
        Expanded(
          child: Text(
            path ?? hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: path == null
                  ? AppColors.textSecondary
                  : AppColors.textPrimary,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        OutlinedButton(onPressed: onPick, child: const Text('Choose…')),
      ],
    ),
  );
}

/// Prompts for a short name (template snapshots, …) in a small text-field
/// dialog. Returns the trimmed input, or null when cancelled — the caller
/// decides what an empty or clashing name means.
Future<String?> promptForName(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = 'Customer / assignment name',
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _NamePrompt(title: title, initial: initial, hint: hint),
  );
  return name?.trim();
}

class _NamePrompt extends StatefulWidget {
  const _NamePrompt({
    required this.title,
    required this.initial,
    required this.hint,
  });

  final String title;
  final String initial;
  final String hint;

  @override
  State<_NamePrompt> createState() => _NamePromptState();
}

class _NamePromptState extends State<_NamePrompt> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 320,
      child: TextField(
        controller: _name,
        autofocus: true,
        decoration: dialogInputDecoration(widget.hint),
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_name.text),
        child: const Text('OK'),
      ),
    ],
  );
}

/// A small OK-only notice for a failed dialog action (unreadable file, …).
Future<void> showErrorNotice(
  BuildContext context, {
  required String title,
  required String message,
}) => showDialog(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: SizedBox(
      width: 420,
      child: Text(message, style: const TextStyle(fontSize: 13)),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('OK'),
      ),
    ],
  ),
);

/// A muted text button for a dialog's secondary utility actions (Clear,
/// Load…, Copy…), so the Cancel/confirm pair keeps the visual weight in the
/// actions row. Disabled when [onPressed] is null.
class DialogUtilityButton extends StatelessWidget {
  /// Creates the button.
  const DialogUtilityButton({
    required this.label,
    required this.onPressed,
    this.tooltip,
    super.key,
  });

  /// The button text.
  final String label;

  /// Tap handler; null renders it disabled.
  final VoidCallback? onPressed;

  /// Optional hover explanation.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
      child: Text(label),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip, child: button);
  }
}

/// A thin vertical rule separating utility groups in a dialog's actions row.
class DialogActionsRule extends StatelessWidget {
  /// Creates the rule.
  const DialogActionsRule({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 20,
    margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    color: AppColors.border,
  );
}
