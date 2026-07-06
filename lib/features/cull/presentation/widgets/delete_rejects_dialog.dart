import 'package:cullimingo/app/theme/tokens.dart';
import 'package:flutter/material.dart';

/// Confirms moving the folder's [count] rejected photos to the OS trash.
/// Resolves to `true` on confirm, `false`/`null` on cancel.
Future<bool?> showDeleteRejectsDialog(
  BuildContext context, {
  required int count,
}) => _showTrashConfirmDialog(
  context,
  title: 'Delete rejected photos',
  count: count,
  descriptor: count == 1 ? 'rejected photo' : 'rejected photos',
);

/// Confirms moving [count] selected photos to the OS trash (the right-click
/// context menu's "Delete…" entry). Resolves to `true` on confirm,
/// `false`/`null` on cancel.
Future<bool?> showDeleteSelectedPhotosDialog(
  BuildContext context, {
  required int count,
}) => _showTrashConfirmDialog(
  context,
  title: count == 1 ? 'Delete photo' : 'Delete $count photos',
  count: count,
  descriptor: count == 1 ? 'photo' : 'photos',
);

Future<bool?> _showTrashConfirmDialog(
  BuildContext context, {
  required String title,
  required int count,
  required String descriptor,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(
        'Move $count $descriptor to the Trash?\n\n'
        'The originals and their .xmp sidecars leave this folder. Nothing is '
        'permanently deleted — you can restore them from the Trash.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.labelRed),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Move to Trash'),
        ),
      ],
    ),
  );
}
