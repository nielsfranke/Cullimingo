import 'dart:async';

import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/filter/presentation/filter_providers.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A Lightroom-style thumbnail strip docked along the loupe's bottom edge:
/// every photo in the filtered set, the focused one highlighted, click to blit
/// to it. Auto-scrolls to keep the focused frame in view as `[`/`]` moves.
class LoupeFilmstrip extends ConsumerStatefulWidget {
  /// Creates the filmstrip.
  const LoupeFilmstrip({super.key});

  /// Overall strip height (thumbnail + padding).
  static const double height = 76;
  static const double _thumbHeight = 60;
  static const double _itemWidth = 84;

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
      final target = (index + 0.5) * LoupeFilmstrip._itemWidth - viewport / 2;
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

    return Container(
      height: LoupeFilmstrip.height,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: ListView.builder(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        itemCount: photos.length,
        itemExtent: LoupeFilmstrip._itemWidth,
        itemBuilder: (context, i) => _FilmstripCell(
          photo: photos[i],
          active: i == activeIndex,
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
    required this.onTap,
  });

  final Photo photo;
  final bool active;
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
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
                            height: LoupeFilmstrip._thumbHeight,
                            // Decode at cell size: the source is the ~1024px
                            // grid thumbnail, so a full decode per strip cell
                            // costs 2–4 MB of ImageCache and visible jank.
                            cacheHeight:
                                (LoupeFilmstrip._thumbHeight *
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
                if (rejected)
                  const Positioned(
                    top: 2,
                    right: 2,
                    child: Icon(
                      Icons.block,
                      size: 12,
                      color: AppColors.labelRed,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
