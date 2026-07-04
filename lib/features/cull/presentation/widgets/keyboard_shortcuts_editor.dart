import 'dart:async';

import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/features/cull/domain/cull_shortcuts.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/widgets/keyboard_shortcuts_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the editor to rebind cull/view shortcuts (with conflict checks).
void showShortcutEditor(BuildContext context) {
  unawaited(
    showDialog<void>(
      context: context,
      builder: (_) => const _ShortcutEditorDialog(),
    ),
  );
}

final Set<LogicalKeyboardKey> _modifiers = {
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
};

class _ShortcutEditorDialog extends ConsumerStatefulWidget {
  const _ShortcutEditorDialog();

  @override
  ConsumerState<_ShortcutEditorDialog> createState() => _ShortcutEditorState();
}

class _ShortcutEditorState extends ConsumerState<_ShortcutEditorDialog> {
  CullAction? _armed; // the action waiting for a key press
  String? _error;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final armed = _armed;
    if (armed == null || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (_modifiers.contains(key)) return KeyEventResult.handled; // keep waiting
    if (key == LogicalKeyboardKey.escape) {
      setState(() {
        _armed = null;
        _error = null;
      });
      return KeyEventResult.handled;
    }
    if (!CullShortcuts.isAssignable(key)) {
      setState(
        () => _error =
            '“${keyDisplayLabel(key)}” is reserved for '
            'navigation and can’t be assigned.',
      );
      return KeyEventResult.handled;
    }
    final shortcuts = ref.read(cullShortcutsControllerProvider);
    final clash = shortcuts.conflictFor(armed, key);
    if (clash != null) {
      setState(
        () => _error =
            '“${keyDisplayLabel(key)}” is already used by '
            '“${clash.label}”.',
      );
      return KeyEventResult.handled;
    }
    ref.read(cullShortcutsControllerProvider.notifier).rebind(armed, key);
    setState(() {
      _armed = null;
      _error = null;
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final shortcuts = ref.watch(cullShortcutsControllerProvider);
    return AlertDialog(
      title: const Text('Customize shortcuts'),
      content: SizedBox(
        width: 460,
        child: Focus(
          autofocus: true,
          onKeyEvent: _onKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _armed != null
                      ? 'Press a key for “${_armed!.label}” (Esc to cancel)'
                      : 'Click a key to rebind it. Arrows, Esc, Enter and the '
                            '⌘/Ctrl combos stay fixed.',
                  style: TextStyle(
                    color: _armed != null
                        ? AppColors.accent
                        : AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.labelRed,
                      fontSize: 12,
                    ),
                  ),
                ],
                for (final group in kShortcutActionGroups) ...[
                  _Header(group.title),
                  for (final action in group.actions)
                    _BindingRow(
                      label: action.label,
                      keyLabel: keyDisplayLabel(shortcuts.keyFor(action)),
                      armed: _armed == action,
                      onTap: () => setState(() {
                        _armed = action;
                        _error = null;
                      }),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            ref.read(cullShortcutsControllerProvider.notifier).resetDefaults();
            setState(() {
              _armed = null;
              _error = null;
            });
          },
          child: const Text('Reset to defaults'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
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

class _BindingRow extends StatelessWidget {
  const _BindingRow({
    required this.label,
    required this.keyLabel,
    required this.armed,
    required this.onTap,
  });

  final String label;
  final String keyLabel;
  final bool armed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(96, 32),
              side: BorderSide(
                color: armed ? AppColors.accent : AppColors.border,
                width: armed ? 2 : 1,
              ),
            ),
            child: Text(armed ? 'Press a key…' : keyLabel),
          ),
        ],
      ),
    );
  }
}
