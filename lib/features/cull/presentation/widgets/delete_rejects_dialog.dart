import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/core/files/trash_fallback.dart';
import 'package:cullimingo/features/cull/data/reject_deleter.dart';
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

/// Asks what to do with [count] photos the OS refused to move to the Trash —
/// typically because they live on a network share, which has no trash
/// (GitHub #14). [reason] is a run-level trash error (e.g. `gio` missing), if
/// any. Offers the restorable [TrashFallback.rejectedFolder] first;
/// [TrashFallback.deletePermanently] needs a second confirmation. Resolves to
/// null on cancel.
Future<TrashFallback?> showTrashUnavailableDialog(
  BuildContext context, {
  required int count,
  String? reason,
}) async {
  final noun = count == 1 ? 'photo' : 'photos';
  final choice = await showDialog<TrashFallback>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Trash not available'),
      content: SizedBox(
        width: 420,
        child: Text(
          '${reason ?? "$count $noun couldn't be moved to the Trash — "
                  'network shares and some drives have none.'}\n\n'
          'Move ${count == 1 ? 'it' : 'them'} into a "$kRejectedFolderName" '
          'folder next to the ${count == 1 ? 'photo' : 'photos'} instead? '
          'Nothing is deleted: Cullimingo skips that folder, and you can '
          'empty it or move photos back whenever you like.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.labelRed),
          onPressed: () =>
              Navigator.of(context).pop(TrashFallback.deletePermanently),
          child: const Text('Delete permanently…'),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () =>
              Navigator.of(context).pop(TrashFallback.rejectedFolder),
          child: const Text('Move to $kRejectedFolderName'),
        ),
      ],
    ),
  );
  if (choice != TrashFallback.deletePermanently) return choice;
  // Never delete for good without the second confirmation.
  if (!context.mounted) return null;
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete $count $noun permanently?'),
      content: Text(
        count == 1
            ? 'The photo and its .xmp sidecar are deleted right away. This '
                  'cannot be undone.'
            : 'The photos and their .xmp sidecars are deleted right away. '
                  'This cannot be undone.',
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.labelRed),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete permanently'),
        ),
      ],
    ),
  );
  return sure ?? false ? TrashFallback.deletePermanently : null;
}
