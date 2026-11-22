import 'package:cullimingo/core/format/shortcut_labels.dart';
import 'package:cullimingo/features/handoff/domain/external_editor.dart';
import 'package:cullimingo/features/handoff/presentation/send_to_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Toolbar "Send to" button (GitHub #30): hands the selection to the first
/// configured editor, the same as ⌘E. With more than one editor, an arrow
/// next to it opens a menu of all of them. It shows the editor's own app icon
/// on macOS and a generic glyph elsewhere. The button is hidden until an
/// editor is set up in Settings.
class SendToButton extends ConsumerWidget {
  /// Creates the button.
  const SendToButton({required this.onSendTo, this.trailing, super.key});

  /// Hands the selection to the given editor.
  final ValueChanged<ExternalEditor> onSendTo;

  /// Shown after the button (a toolbar group divider), and hidden with it.
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editors =
        ref.watch(sendToEditorsProvider).value ?? const <ExternalEditor>[];
    if (editors.isEmpty) return const SizedBox.shrink();
    final primary = editors.first;
    final shortcut = modShortcut('E');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Send the selection to ${primary.label} ($shortcut)',
          child: TextButton.icon(
            onPressed: () => onSendTo(primary),
            icon: EditorIcon(editor: primary),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                'Send to ${primary.label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        if (editors.length > 1)
          MenuAnchor(
            menuChildren: [
              for (final (i, editor) in editors.indexed)
                MenuItemButton(
                  leadingIcon: EditorIcon(editor: editor),
                  trailingIcon: i == 0 ? Text(shortcut) : null,
                  onPressed: () => onSendTo(editor),
                  child: Text('Send to ${editor.label}'),
                ),
            ],
            builder: (context, controller, child) => IconButton(
              tooltip: 'Send to another editor',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_drop_down, size: 18),
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            ),
          ),
        ?trailing,
      ],
    );
  }
}

/// The app icon of [editor] at [size] logical pixels, or a generic "open in"
/// glyph while it loads, on Linux, or when the lookup fails.
class EditorIcon extends ConsumerWidget {
  /// Creates the icon.
  const EditorIcon({required this.editor, this.size = 18, super.key});

  /// The editor whose icon to show.
  final ExternalEditor editor;

  /// Edge length in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final png = ref.watch(editorIconProvider(editor.path)).value;
    if (png == null) return Icon(Icons.open_in_new, size: size);
    return Image.memory(
      png,
      width: size,
      height: size,
      gaplessPlayback: true,
    );
  }
}
