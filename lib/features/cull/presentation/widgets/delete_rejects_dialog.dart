import 'package:cullimingo/app/theme/tokens.dart';
import 'package:flutter/material.dart';

/// Confirms moving the folder's [count] rejected photos to the OS trash.
/// Resolves to `true` on confirm, `false`/`null` on cancel.
Future<bool?> showDeleteRejectsDialog(
  BuildContext context, {
  required int count,
}) {
  final noun = count == 1 ? 'photo' : 'photos';
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete rejected photos'),
      content: Text(
        'Move $count rejected $noun to the Trash?\n\n'
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
