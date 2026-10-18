import 'dart:async';

import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/settings/filmstrip_position.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/filter/presentation/filter_providers.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:cullimingo/shared/widgets/flag_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A Lightroom-style thumbnail strip docked along the loupe's bottom edge, or
/// beside the photo ([FilmstripPosition], GitHub #19): every photo in the
/// filtered set, the focused one highlighted, click to blit to it.
/// Auto-scrolls to keep the focused frame in view as `[`/`]` moves.
class LoupeFilmstrip extends ConsumerStatefulWidget {
  /// Creates the filmstrip; [position] picks the edge it docks to.
  const LoupeFilmstrip({this.position = FilmstripPosition.bottom, super.key});

  /// The edge the strip docks to; left/right run it vertically.
  final FilmstripPosition position;

  /// Overall strip height when docked at the bottom (thumbnail + padding).
  static const double height = 76;

  /// Overall strip width when docked at a side.
  static const double width = 100;

  static const double _thumbHeight = 60;
  static const double _itemWidth = 84;

  // Vertical cells: as tall as a horizontal cell is wide would waste height on
  // landscape frames, so they're a little shorter than they are wide.
  static const double _verticalThumbHeight = 66;
  static const double _itemHeight = 72;

  @override
  ConsumerState<LoupeFilmstrip> createState() => _LoupeFilmstripState();
}

class _LoupeFilmstripState extends ConsumerState<LoupeFilmstrip> {
  final _scroll = ScrollController();
  int? _lastCentered;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // Bring [index] into view, centred where possible, after the strip lays out.
  void _centerOn(int index) {
    if (_lastCentered == index) return;
    _lastCentered = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final viewport = _scroll.position.viewportDimension;
      final extent = widget.position.isVertical
          ? LoupeFilmstrip._itemHeight
          : LoupeFilmstrip._itemWidth;
      final target = (index + 0.5) * extent - viewport / 2;
      final max = _scroll.position.maxScrollExtent;
      unawaited(
        _scroll.animateTo(
          target.clamp(0.0, max),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(filteredPhotosProvider);
    final focusedId = ref.watch(
      cullControllerProvider.select((s) => s.focusedId),
    );
    if (photos.isEmpty) return const SizedBox.shrink();

    final activeIndex = photos.indexWhere((p) => p.id == focusedId);
    if (activeIndex >= 0) _centerOn(activeIndex);

    const edge = BorderSide(color: AppColors.border);
    final vertical = widget.position.isVertical;
    return Container(
      height: vertical ? null : LoupeFilmstrip.height,
      width: vertical ? LoupeFilmstrip.width : null,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: switch (widget.position) {
          FilmstripPosition.bottom => const Border(top: edge),
          FilmstripPosition.left => const Border(right: edge),
          FilmstripPosition.right => const Border(left: edge),
        },
      ),
      child: ListView.builder(
        controller: _scroll,
        scrollDirection: vertical ? Axis.vertical : Axis.horizontal,
        padding: vertical
            ? const EdgeInsets.symmetric(vertical: AppSpacing.xs)
            : const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        itemCount: photos.length,
        itemExtent: vertical
            ? LoupeFilmstrip._itemHeight
            : LoupeFilmstrip._itemWidth,
        itemBuilder: (context, i) => _FilmstripCell(
          photo: photos[i],
          active: i == activeIndex,
          vertical: vertical,
          onTap: () =>
              ref.read(cullControllerProvider.notifier).focus(photos[i].id),
        ),
      ),
    );
  }
}

class _FilmstripCell extends ConsumerWidget {
  const _FilmstripCell({
    required this.photo,
    required this.active,
    required this.vertical,
    required this.onTap,
  });

  final Photo photo;
  final bool active;
  final bool vertical;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumb = ref.watch(thumbnailProvider(photo.path)).value;
    final rejected = photo.flag == PickFlag.reject;
    final swatch = photo.colorLabel.color;

    // The current photo pops: full brightness, a bright accent frame + glow.
    // Every other frame is dimmed and recessed so the eye lands on the active
    // one at a glance (rejects dim further still).
    final imageOpacity = active
        ? 1.0
        : rejected
        ? 0.4
        : 0.72;

    final thumbHeight = vertical
        ? LoupeFilmstrip._verticalThumbHeight
        : LoupeFilmstrip._thumbHeight;

    return Padding(
      // The wide gap runs across the strip, the narrow one between frames.
      padding: vertical
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 3)
          : const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: active ? AppColors.accent : AppColors.border,
              width: active ? 2.5 : 1,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.55),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm - 1),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: Colors.black,
                  child: thumb == null
                      ? const SizedBox.shrink()
                      : Opacity(
                          opacity: imageOpacity,
                          child: Image.memory(
                            thumb,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            height: thumbHeight,
                            // Decode at cell size: the source is the ~1024px
                            // grid thumbnail, so a full decode per strip cell
                            // costs 2–4 MB of ImageCache and visible jank.
                            cacheHeight:
                                (thumbHeight *
                                        MediaQuery.devicePixelRatioOf(context))
                                    .round(),
                          ),
                        ),
                ),
                // A slim colour-label bar along the bottom, when one is set.
                if (swatch != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(height: 3, color: swatch),
                  ),
                // Pick and reject alike, with the grid's badge (GitHub #18):
                // the strip used to mark only rejects.
                if (photo.flag != PickFlag.none)
                  Positioned(
                    top: 3,
                    left: 3,
                    child: FlagBadge(flag: photo.flag, size: 13),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
