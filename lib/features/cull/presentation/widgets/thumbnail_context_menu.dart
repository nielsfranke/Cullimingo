import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/files/open_external.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/handoff/data/transfer_service.dart';
import 'package:cullimingo/features/handoff/domain/external_editor.dart';
import 'package:cullimingo/features/handoff/presentation/send_to_providers.dart';
import 'package:cullimingo/features/metadata/presentation/keyword_dialog.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A context-menu entry's deferred action, run after the menu closes.
typedef _MenuAction = Future<void> Function();

/// Right-click menu for a grid thumbnail. Acts on the current selection when
/// [photo] is part of it, otherwise on [photo] alone — the caller arranges the
/// selection (via selectOnly / focus) before opening so the controller's
/// batch helpers ([CullController.applyRating] etc.) target the right photos.
///
/// Each entry's value is the action to run; rating / flag / colour are compact
/// palette rows so a mark is one click away (Photo Mechanic style).
Future<void> showThumbnailContextMenu({
  required BuildContext context,
  required WidgetRef ref,
  required Photo photo,
  required Offset globalPosition,
  required ValueChanged<TransferMode> onTransfer,
  required ValueChanged<ExternalEditor> onSendTo,
  VoidCallback? onEditMetadata,
  VoidCallback? onRename,
  VoidCallback? onApplyTemplate,
  VoidCallback? onGeocode,
  VoidCallback? onExport,
  VoidCallback? onExpandBrackets,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final position = RelativeRect.fromRect(
    Rect.fromPoints(globalPosition, globalPosition),
    Offset.zero & overlay.size,
  );
  final controller = ref.read(cullControllerProvider.notifier);
  final count = ref.read(cullControllerProvider).markTargets.length;
  // Configured "Send to" editors (empty when none set / not yet loaded); the
  // menu adds an "Open in <editor>" row per entry. Read synchronously — the
  // page keeps this provider warm — so opening the menu stays instant.
  final editors =
      ref.read(sendToEditorsProvider).value ?? const <ExternalEditor>[];

  final action = await showMenu<_MenuAction>(
    context: context,
    position: position,
    color: AppColors.surfaceElevated,
    popUpAnimationStyle: kMenuAnimationStyle,
    items: [
      if (count > 1)
        PopupMenuItem<_MenuAction>(
          enabled: false,
          height: 32,
          child: Text(
            '$count photos',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      PopupMenuItem<_MenuAction>(
        enabled: false,
        padding: EdgeInsets.zero,
        child: _RatingRow(photo: photo, controller: controller),
      ),
      PopupMenuItem<_MenuAction>(
        enabled: false,
        padding: EdgeInsets.zero,
        child: _FlagRow(photo: photo, controller: controller),
      ),
      PopupMenuItem<_MenuAction>(
        enabled: false,
        padding: EdgeInsets.zero,
        child: _ColorRow(photo: photo, controller: controller),
      ),
      const PopupMenuDivider(),
      PopupMenuItem<_MenuAction>(
        value: () => controller.applyRotation(-1),
        child: const _MenuRow('Rotate left', ','),
      ),
      PopupMenuItem<_MenuAction>(
        value: () => controller.applyRotation(1),
        child: const _MenuRow('Rotate right', '.'),
      ),
      const PopupMenuDivider(),
      if (onEditMetadata != null)
        PopupMenuItem<_MenuAction>(
          value: () async => onEditMetadata(),
          child: const _MenuRow('Edit metadata…', 'M'),
        ),
      PopupMenuItem<_MenuAction>(
        value: () => showKeywordEditor(context, ref),
        child: const _MenuRow('Edit keywords…', 'K'),
      ),
      if (onApplyTemplate != null)
        PopupMenuItem<_MenuAction>(
          value: () async => onApplyTemplate(),
          child: const _MenuRow('Apply metadata template', 'T'),
        ),
      if (onGeocode != null)
        PopupMenuItem<_MenuAction>(
          value: () async => onGeocode(),
          child: const Text('Fill location from GPS'),
        ),
      const PopupMenuDivider(),
      if (onExpandBrackets != null)
        PopupMenuItem<_MenuAction>(
          value: () async => onExpandBrackets(),
          child: const _MenuRow('Expand selection to bracket', 'G'),
        ),
      if (onRename != null)
        PopupMenuItem<_MenuAction>(
          value: () async => onRename(),
          child: const _MenuRow('Rename…', 'R'),
        ),
      PopupMenuItem<_MenuAction>(
        value: () async => onTransfer(TransferMode.copy),
        child: const Text('Copy to folder…'),
      ),
      PopupMenuItem<_MenuAction>(
        value: () async => onTransfer(TransferMode.move),
        child: const Text('Move to folder…'),
      ),
      if (onExport != null)
        PopupMenuItem<_MenuAction>(
          value: () async => onExport(),
          child: const _MenuRow('Export…', 'S'),
        ),
      const PopupMenuDivider(),
      PopupMenuItem<_MenuAction>(
        value: () => openExternally(photo.path),
        child: const Text('Open in default app'),
      ),
      PopupMenuItem<_MenuAction>(
        value: () => revealInFileManager(photo.path),
        child: Text(revealInFileManagerLabel),
      ),
      if (editors.isNotEmpty) ...[
        const PopupMenuDivider(),
        for (final editor in editors)
          PopupMenuItem<_MenuAction>(
            value: () async => onSendTo(editor),
            child: Text('Open in ${editor.label}'),
          ),
      ],
    ],
  );
  await action?.call();
}

/// A menu label with a right-aligned, muted shortcut hint (Photo-Mechanic
/// style, e.g. `Apply metadata template … T`).
class _MenuRow extends StatelessWidget {
  const _MenuRow(this.label, this.shortcut);

  final String label;
  final String shortcut;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label)),
      const SizedBox(width: AppSpacing.lg),
      Text(
        shortcut,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
        ),
      ),
    ],
  );
}

/// Five stars that set the rating (clicking the current one clears it).
class _RatingRow extends StatelessWidget {
  const _RatingRow({required this.photo, required this.controller});

  final Photo photo;
  final CullController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            tooltip: 'Rate $i',
            icon: Icon(
              i <= photo.rating
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              color: i <= photo.rating
                  ? AppColors.ratingGold
                  : AppColors.textSecondary,
            ),
            onPressed: () => Navigator.pop(
              context,
              () => controller.applyRating(photo.rating == i ? 0 : i),
            ),
          ),
      ],
    );
  }
}

/// Pick / Reject / clear flag.
class _FlagRow extends StatelessWidget {
  const _FlagRow({required this.photo, required this.controller});

  final Photo photo;
  final CullController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          tooltip: 'Pick',
          icon: Icon(
            Icons.check_rounded,
            color: photo.flag == PickFlag.pick
                ? AppColors.selection
                : AppColors.textSecondary,
          ),
          onPressed: () => Navigator.pop(
            context,
            () => controller.applyFlag(
              photo.flag == PickFlag.pick ? PickFlag.none : PickFlag.pick,
            ),
          ),
        ),
        IconButton(
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          tooltip: 'Reject',
          icon: Icon(
            Icons.close_rounded,
            color: photo.flag == PickFlag.reject
                ? AppColors.labelRed
                : AppColors.textSecondary,
          ),
          onPressed: () => Navigator.pop(
            context,
            () => controller.applyFlag(
              photo.flag == PickFlag.reject ? PickFlag.none : PickFlag.reject,
            ),
          ),
        ),
      ],
    );
  }
}

/// Colour-label swatches plus a "none" chip.
class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.photo, required this.controller});

  final Photo photo;
  final CullController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final label in ColorLabel.values)
            if (label != ColorLabel.none)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: GestureDetector(
                  onTap: () => Navigator.pop(
                    context,
                    () => controller.applyColor(
                      photo.colorLabel == label ? ColorLabel.none : label,
                    ),
                  ),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: label.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: photo.colorLabel == label
                            ? Colors.white
                            : Colors.black.withValues(alpha: 0.4),
                        width: photo.colorLabel == label ? 2 : 1,
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
