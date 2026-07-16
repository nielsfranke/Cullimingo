import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/filter/presentation/filter_providers.dart';
import 'package:cullimingo/features/metadata/domain/keyword_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the keyword editor for the current cull target (`dc:subject`, §4):
/// the Space-selection if any, else the focused photo. The text is prefilled
/// from the focused photo and, on save, replaces the keyword list on every
/// target (mirrored to each XMP sidecar). A dialog — not an inline field — so
/// its [TextField] gets keyboard focus without fighting the grid's cull keys.
Future<void> showKeywordEditor(BuildContext context, WidgetRef ref) async {
  final photos = ref.read(filteredPhotosProvider);
  if (photos.isEmpty) return;
  final selection = ref.read(cullControllerProvider);
  final targetIds = selection.markTargets.toList();
  if (targetIds.isEmpty) return;

  // Prefill from the actual target photo, resolved against the *unfiltered*
  // set: the focused/selected photo may be hidden by the active filter, and
  // the old filtered-only double firstWhere threw a StateError then — the K
  // key looked dead.
  final all = ref.read(photosProvider).value ?? const [];
  final focused =
      all
          .where((p) => p.id == (selection.focusedId ?? targetIds.first))
          .firstOrNull ??
      all.where((p) => p.id == targetIds.first).firstOrNull ??
      photos.first;

  final result = await showDialog<List<String>>(
    context: context,
    // A form — an outside click must not discard the keywords being typed.
    barrierDismissible: false,
    builder: (_) =>
        _KeywordDialog(initial: focused.keywords, count: targetIds.length),
  );
  if (result == null) return;

  final controller = ref.read(cullControllerProvider.notifier);
  for (final id in targetIds) {
    await controller.setKeywords(id, result);
  }
}

class _KeywordDialog extends StatefulWidget {
  const _KeywordDialog({required this.initial, required this.count});

  final List<String> initial;
  final int count;

  @override
  State<_KeywordDialog> createState() => _KeywordDialogState();
}

class _KeywordDialogState extends State<_KeywordDialog> {
  late final TextEditingController _text = TextEditingController(
    text: formatKeywords(widget.initial),
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(parseKeywords(_text.text));

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.count > 1
        ? 'Applies to ${widget.count} photos (replaces their keywords)'
        : 'Comma-separated';
    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      title: const Text('Keywords'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _text,
              autofocus: true,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                hintText: 'sunset, beach, portrait',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
