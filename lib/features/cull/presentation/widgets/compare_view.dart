import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/widgets/cull_toolbar.dart';
import 'package:cullimingo/features/metadata/presentation/keyword_dialog.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:cullimingo/shared/widgets/color_dot.dart';
import 'package:cullimingo/shared/widgets/flag_badge.dart';
import 'package:cullimingo/shared/widgets/rating_stars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// Fullscreen **compare view** (`BUILD_PLAN.md` §8): the selected photos shown
/// large, tiled side-by-side (2-up / n-up), so you can pick the keeper from a
/// burst of similar frames. Each tile carries its own cull controls (rate /
/// pick / reject / colour / keywords) and a button to drop it from the compare.
///
/// Keyboard-driven like the rest of the app: one tile is *focused* (accent
/// ring); the page routes the cull keys to it and the arrows move the focus.
/// Click a tile to focus it. `Esc`/`C`/`B` close it from the page.
class CompareView extends ConsumerWidget {
  /// Creates the compare overlay for [photoIds] (in display order).
  const CompareView({
    required this.photoIds,
    required this.focusedId,
    required this.onFocus,
    required this.onRemove,
    required this.onClose,
    super.key,
  });

  /// The photos to compare, in order.
  final List<int> photoIds;

  /// The currently focused tile (cull keys act on it); null = none.
  final int? focusedId;

  /// Focuses a tile (on click).
  final ValueChanged<int> onFocus;

  /// Drops one photo from the comparison.
  final ValueChanged<int> onRemove;

  /// Closes the compare view.
  final VoidCallback onClose;

  /// Columns for [n] tiles: roughly square (2→2, 4→2, 5→3, 9→3).
  static int columnsFor(int n) => n <= 1 ? 1 : math.sqrt(n).ceil();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(photosProvider).value ?? const <Photo>[];
    final byId = {for (final photo in all) photo.id: photo};
    final photos = [
      for (final id in photoIds)
        if (byId[id] != null) byId[id]!,
    ];
    if (photos.isEmpty) return const SizedBox.shrink();

    final cols = columnsFor(photos.length);
    return ExcludeFocus(
      child: ColoredBox(
        color: Colors.black,
        child: Column(
          children: [
            _TopBar(count: photos.length, onClose: onClose),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  final rows = (photos.length / cols).ceil();
                  final cellW = c.maxWidth / cols;
                  final cellH = c.maxHeight / rows;
                  return Wrap(
                    children: [
                      for (final photo in photos)
                        SizedBox(
                          width: cellW,
                          height: cellH,
                          child: _CompareCell(
                            photo: photo,
                            focused: photo.id == focusedId,
                            onFocus: () => onFocus(photo.id),
                            onRemove: () => onRemove(photo.id),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.count, required this.onClose});

  final int count;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    decoration: const BoxDecoration(
      color: AppColors.surface,
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        const Icon(Icons.compare, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.sm),
        Text(
          'Compare $count photos',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        const Text(
          'Arrows focus · 1-5 / P / X / colours mark · ✕ drops · Esc closes',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(width: AppSpacing.sm),
        IconButton(
          onPressed: onClose,
          tooltip: 'Close compare (Esc)',
          icon: const Icon(Icons.close_rounded, size: 18),
          color: AppColors.textPrimary,
        ),
      ],
    ),
  );
}

class _CompareCell extends ConsumerWidget {
  const _CompareCell({
    required this.photo,
    required this.focused,
    required this.onFocus,
    required this.onRemove,
  });

  final Photo photo;
  final bool focused;
  final VoidCallback onFocus;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loupe = ref.watch(loupePreviewProvider(photo.path)).value;
    final thumb = ref.watch(thumbnailProvider(photo.path)).value;
    final bytes = loupe ?? thumb;
    final controller = ref.read(cullControllerProvider.notifier);

    return GestureDetector(
      onTap: onFocus,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: focused ? AppColors.accent : AppColors.border,
            width: focused ? 2 : 1,
          ),
          color: Colors.black,
        ),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _image(bytes)),
                  // Marks overlay (top-left).
                  Positioned(
                    top: AppSpacing.sm,
                    left: AppSpacing.sm,
                    child: Row(
                      children: [
                        FlagBadge(flag: photo.flag, size: 16),
                        if (photo.flag != PickFlag.none)
                          const SizedBox(width: AppSpacing.xs),
                        RatingStars(rating: photo.rating, size: 14),
                        if (photo.colorLabel != ColorLabel.none) ...[
                          const SizedBox(width: AppSpacing.xs),
                          ColorDot(label: photo.colorLabel, size: 12),
                        ],
                      ],
                    ),
                  ),
                  // Drop-from-compare (top-right).
                  Positioned(
                    top: AppSpacing.xs,
                    right: AppSpacing.xs,
                    child: IconButton(
                      onPressed: onRemove,
                      tooltip: 'Remove from compare',
                      iconSize: 18,
                      icon: const Icon(Icons.close_rounded),
                      color: AppColors.textPrimary,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    p.basename(photo.path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    child: CullToolbar(
                      photo: photo,
                      onRating: (r) => controller.setRating(photo.id, r),
                      onFlag: (f) => controller.setFlag(photo.id, f),
                      onColor: (c) => controller.setColor(photo.id, c),
                      onKeywords: () {
                        // Keyword editor targets the focused photo, so point
                        // it at this tile first.
                        controller.selectOnly(photo.id);
                        unawaited(showKeywordEditor(context, ref));
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _image(Uint8List? bytes) {
    if (bytes == null) {
      return Center(
        child: Icon(
          photo.isRaw ? Icons.raw_on_rounded : Icons.image_outlined,
          color: AppColors.textSecondary,
          size: 48,
        ),
      );
    }
    return RotatedBox(
      quarterTurns: photo.userRotation,
      child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
    );
  }
}
