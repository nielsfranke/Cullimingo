import 'dart:async';

import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/features/cull/domain/cull_shortcuts.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/widgets/keyboard_shortcuts_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The rebindable actions grouped for display in the cheat sheet / editor.
const List<({String title, List<CullAction> actions})> kShortcutActionGroups = [
  (
    title: 'Rate, flag & label',
    actions: [
      CullAction.rate1,
      CullAction.rate2,
      CullAction.rate3,
      CullAction.rate4,
      CullAction.rate5,
      CullAction.clearRating,
      CullAction.pick,
      CullAction.reject,
      CullAction.colorRed,
      CullAction.colorYellow,
      CullAction.colorGreen,
      CullAction.colorBlue,
      CullAction.colorPurple,
      CullAction.keywords,
      CullAction.metadata,
      CullAction.applyTemplate,
      CullAction.rename,
      CullAction.rotateLeft,
      CullAction.rotateRight,
    ],
  ),
  (
    title: 'View & select',
    actions: [
      CullAction.select,
      CullAction.loupe,
      CullAction.compare,
      CullAction.compareBurst,
      CullAction.inspector,
    ],
  ),
];

/// Fixed (non-rebindable) keys shown for reference.
const List<({String keys, String does})> kFixedShortcuts = [
  (keys: '← ↑ → ↓', does: 'Move focus'),
  (keys: 'Double-click', does: 'Open loupe / play video'),
  (keys: 'Enter', does: 'Loupe (also opens it)'),
  (keys: '[  ]', does: 'Previous / next photo in loupe'),
  (keys: 'Esc', does: 'Close loupe / compare'),
  (keys: '⌘/Ctrl + O', does: 'Open folder'),
  (keys: '⌘/Ctrl + T', does: 'New tab'),
  (keys: '⌘/Ctrl + W', does: 'Close tab'),
  (keys: '⌘/Ctrl + A', does: 'Select all (filtered)'),
  (keys: '⌘/Ctrl + R', does: 'Refresh folder'),
  (keys: '⌘/Ctrl + F', does: 'Find by filename'),
  (keys: '⌘/Ctrl + S', does: 'Export'),
  (keys: '⌘/Ctrl + Z', does: 'Undo mark change'),
  (keys: '⌘/Ctrl + Shift + Z', does: 'Redo mark change'),
  (keys: '⌘/Ctrl + Backspace', does: 'Delete rejected photos…'),
  (keys: '⌘/Ctrl + Enter', does: 'Metadata editor: save & next photo'),
  (keys: '⌘/Ctrl + Shift + Enter', does: 'Metadata editor: previous photo'),
  (keys: '?', does: 'Show this list'),
];

/// Shows the keyboard-shortcuts cheat sheet (live bindings). Pass [firstRun]
/// for the auto-shown welcome variant (intro line + a single "Got it" button).
void showKeyboardShortcuts(BuildContext context, {bool firstRun = false}) {
  unawaited(
    showDialog<void>(
      context: context,
      builder: (_) => _KeyboardShortcutsDialog(firstRun: firstRun),
    ),
  );
}

class _KeyboardShortcutsDialog extends ConsumerWidget {
  const _KeyboardShortcutsDialog({this.firstRun = false});

  /// Whether this is the auto-shown first-run welcome (vs the `?` cheat sheet).
  final bool firstRun;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shortcuts = ref.watch(cullShortcutsControllerProvider);
    return AlertDialog(
      title: Text(firstRun ? 'Welcome to Cullimingo' : 'Keyboard shortcuts'),
      // Two balanced columns so the list reads at a glance instead of scrolling
      // forever: rebindable cull keys on the left, view/select + fixed
      // navigation on the right.
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (firstRun) ...[
                const Text(
                  'Culling here is keyboard-first. These are the keys — press '
                  '? any time to see this list again, and rebind anything '
                  'under Settings.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: rebindable cull keys (short — a narrow key column).
                  Expanded(
                    child: _shortcutColumn(
                      shortcuts,
                      groups: kShortcutActionGroups,
                      keyWidth: 108,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xl),
                  // Right: fixed navigation/app keys (long ⌘/Ctrl combos).
                  Expanded(
                    child: _shortcutColumn(
                      shortcuts,
                      groups: const [],
                      includeFixed: true,
                      keyWidth: 188,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: firstRun
          ? [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ]
          : [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  showShortcutEditor(context);
                },
                child: const Text('Customize…'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
    );
  }

  // One column of the cheat sheet: each [groups] section (header + its
  // rebindable rows), optionally followed by the fixed navigation/app section.
  // [keyWidth] sizes the key-cap column so keys and descriptions align.
  Widget _shortcutColumn(
    CullShortcuts shortcuts, {
    required List<({String title, List<CullAction> actions})> groups,
    required double keyWidth,
    bool includeFixed = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in groups) ...[
          _Header(group.title),
          for (final a in group.actions)
            _Row(
              keys: keyDisplayLabel(shortcuts.keyFor(a)),
              does: a.label,
              keyWidth: keyWidth,
            ),
        ],
        if (includeFixed) ...[
          const _Header('Navigation & app'),
          for (final s in kFixedShortcuts)
            _Row(keys: s.keys, does: s.does, keyWidth: keyWidth),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: AppColors.accent,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        const Divider(height: 1, color: AppColors.border),
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.keys, required this.does, required this.keyWidth});

  final String keys;
  final String does;
  final double keyWidth;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: keyWidth,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _KeyCap(keys),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            does,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  );
}

/// A keyboard-key chip — the shortcut rendered as a little keycap so it reads
/// as a key, not prose.
class _KeyCap extends StatelessWidget {
  const _KeyCap(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      border: Border.all(color: AppColors.border),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.1,
      ),
    ),
  );
}
