import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/cull/domain/loupe_zoom.dart';
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
///
/// The mouse wheel / pinch zooms and a drag pans — in *every* tile at once
/// (the link button in the top bar frees them individually), so the same spot
/// of each frame stays side by side (eyes, feathers, focus). `Z` toggles Fit ↔
/// 100% on the focused tile; past a modest zoom the tiles swap their
/// screen-res preview for the full-resolution source.
class CompareView extends ConsumerStatefulWidget {
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
  ConsumerState<CompareView> createState() => _CompareViewState();
}

class _CompareViewState extends ConsumerState<CompareView> {
  /// Pan/zoom shared by every tile while linked; identity == Fit.
  final _tc = TransformationController();

  /// Per-tile pan/zoom while unlinked (created lazily from the shared one).
  final _own = <int, TransformationController>{};

  /// Each tile's native pixel size and image-area size, reported by the cells
  /// so `Z` can work out what true 100% means.
  final _intrinsic = <int, Size>{};
  final _viewport = <int, Size>{};

  bool _linked = true;

  /// Set by `Z` so every tile fetches its full-resolution source (needed to
  /// know what true 100% is), and kept until the zoom is reset.
  bool _forceFull = false;

  /// The focused tile's scale while `Z`'s 100% is being held: when the
  /// full-res source lands and the native size changes, re-snap to its 1:1.
  /// Null once the user zooms away.
  double? _heldScale;
  int? _heldId;

  /// Biggest magnification beyond Fit.
  static const _maxScale = 16.0;

  @override
  void dispose() {
    _tc.dispose();
    for (final c in _own.values) {
      c.dispose();
    }
    super.dispose();
  }

  TransformationController _controllerFor(int id) => _linked
      ? _tc
      : _own.putIfAbsent(id, () => TransformationController(_tc.value));

  void _toggleLink() {
    final focusedId = widget.focusedId;
    setState(() {
      if (_linked) {
        _linked = false;
      } else {
        // Relinking: everyone follows the focused tile.
        final from = focusedId == null ? null : _own[focusedId];
        if (from != null) _tc.value = from.value.clone();
        _linked = true;
        final stale = _own.values.toList();
        _own.clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final c in stale) {
            c.dispose();
          }
        });
      }
    });
  }

  void _resetZoom() {
    if (_forceFull || _heldScale != null) {
      setState(() {
        _forceFull = false;
        _heldScale = null;
      });
    }
    _tc.value = Matrix4.identity();
    for (final c in _own.values) {
      c.value = Matrix4.identity();
    }
  }

  // `Z`: Fit ↔ 100% on the focused tile (or 2× when the native size is
  // unknown / smaller than the tile), zooming about the tile's centre.
  void _toggleZoom() {
    final id = widget.focusedId;
    if (id == null) return;
    final c = _controllerFor(id);
    if (c.value.getMaxScaleOnAxis() > 1.01) {
      if (_linked) {
        _resetZoom();
      } else {
        c.value = Matrix4.identity();
      }
      _heldScale = null;
      return;
    }
    setState(() => _forceFull = true);
    _zoomToHundred(id);
  }

  // Zooms (about the tile's centre) to what the best-known native size says is
  // 1:1, or 2× when unknown / smaller than the tile; holds it so the swap to
  // the full-res source re-snaps.
  void _zoomToHundred(int id) {
    final c = _controllerFor(id);
    final photo = (ref.read(photosProvider).value ?? const <Photo>[])
        .where((p) => p.id == id)
        .firstOrNull;
    final viewport = _viewport[id];
    var target = 2.0;
    if (photo != null && viewport != null) {
      final hundred = LoupeZoom(
        intrinsic: _intrinsic[id],
        viewport: viewport,
        quarterTurns: photo.userRotation,
      ).hundredScale;
      if (hundred != null && hundred > 1) target = hundred;
    }
    target = target.clamp(1, _maxScale);
    final center = viewport == null
        ? Offset.zero
        : Offset(viewport.width / 2, viewport.height / 2);
    c.value = Matrix4.identity()
      ..translateByDouble(
        center.dx * (1 - target),
        center.dy * (1 - target),
        0,
        1,
      )
      ..scaleByDouble(target, target, target, 1);
    _heldScale = target;
    _heldId = id;
  }

  // A tile resolved a (new) native size: if 100% is still held, re-snap.
  void _onIntrinsic(int id, Size size) {
    _intrinsic[id] = size;
    final held = _heldScale;
    if (held == null || id != widget.focusedId || id != _heldId) return;
    final c = _controllerFor(id);
    if ((c.value.getMaxScaleOnAxis() - held).abs() > 0.01) {
      _heldScale = null; // the user zoomed away
      return;
    }
    // Re-snap from Fit so the maths starts from a known matrix.
    _zoomToHundred(id);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(loupeZoomToggleProvider, (_, _) => _toggleZoom());
    final photoIds = widget.photoIds;
    final all = ref.watch(photosProvider).value ?? const <Photo>[];
    final byId = {for (final photo in all) photo.id: photo};
    final photos = [
      for (final id in photoIds)
        if (byId[id] != null) byId[id]!,
    ];
    if (photos.isEmpty) return const SizedBox.shrink();

    final cols = CompareView.columnsFor(photos.length);
    return ExcludeFocus(
      child: ColoredBox(
        color: Colors.black,
        child: Column(
          children: [
            _TopBar(
              count: photos.length,
              onClose: widget.onClose,
              zoom: Listenable.merge([_tc, ..._own.values]),
              zoomed: () =>
                  _tc.value.getMaxScaleOnAxis() > 1.01 ||
                  _own.values.any((c) => c.value.getMaxScaleOnAxis() > 1.01),
              linked: _linked,
              onToggleLink: _toggleLink,
              onReset: _resetZoom,
            ),
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
                            focused: photo.id == widget.focusedId,
                            zoom: _controllerFor(photo.id),
                            maxScale: _maxScale,
                            forceFull: _forceFull,
                            onViewport: (v) => _viewport[photo.id] = v,
                            onIntrinsic: (size) => _onIntrinsic(photo.id, size),
                            onFocus: () => widget.onFocus(photo.id),
                            onRemove: () => widget.onRemove(photo.id),
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
  const _TopBar({
    required this.count,
    required this.onClose,
    required this.zoom,
    required this.zoomed,
    required this.linked,
    required this.onToggleLink,
    required this.onReset,
  });

  final int count;
  final VoidCallback onClose;

  /// Fires whenever any tile's pan/zoom changes.
  final Listenable zoom;

  /// Whether any tile is currently zoomed in.
  final bool Function() zoomed;
  final bool linked;
  final VoidCallback onToggleLink;
  final VoidCallback onReset;

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
        const SizedBox(width: AppSpacing.md),
        IconButton(
          onPressed: onToggleLink,
          tooltip: linked
              ? 'Zoom linked across tiles — click to zoom tiles separately'
              : 'Zoom separate per tile — click to link',
          iconSize: 18,
          icon: Icon(linked ? Icons.link_rounded : Icons.link_off_rounded),
          color: linked ? AppColors.accent : AppColors.textSecondary,
        ),
        ListenableBuilder(
          listenable: zoom,
          builder: (context, _) => zoomed()
              ? TextButton(onPressed: onReset, child: const Text('Fit'))
              : const SizedBox.shrink(),
        ),
        const Spacer(),
        const Flexible(
          child: Text(
            'Wheel zooms · Z fit/100% · drag pans · arrows focus · Esc closes',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
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

class _CompareCell extends ConsumerStatefulWidget {
  const _CompareCell({
    required this.photo,
    required this.focused,
    required this.zoom,
    required this.maxScale,
    required this.forceFull,
    required this.onViewport,
    required this.onIntrinsic,
    required this.onFocus,
    required this.onRemove,
  });

  final Photo photo;
  final bool focused;
  final TransformationController zoom;
  final double maxScale;

  /// Fetch the full-resolution source regardless of the zoom.
  final bool forceFull;

  /// Reports the image-area size.
  final ValueChanged<Size> onViewport;

  /// Reports the decoded image's native size once it resolves.
  final ValueChanged<Size> onIntrinsic;
  final VoidCallback onFocus;
  final VoidCallback onRemove;

  @override
  ConsumerState<_CompareCell> createState() => _CompareCellState();
}

class _CompareCellState extends ConsumerState<_CompareCell> {
  /// Zoom (relative to Fit) past which the full-resolution source is fetched.
  static const _fullZoomTrigger = 1.5;

  bool _wantFull = false;
  Size? _intrinsic;
  Uint8List? _resolvedBytes;
  Size _viewport = Size.zero;

  @override
  void initState() {
    super.initState();
    widget.zoom.addListener(_onZoom);
  }

  @override
  void didUpdateWidget(_CompareCell old) {
    super.didUpdateWidget(old);
    if (old.zoom != widget.zoom) {
      old.zoom.removeListener(_onZoom);
      widget.zoom.addListener(_onZoom);
      _onZoom();
    }
    if (old.photo.path != widget.photo.path) {
      _wantFull = false;
      _intrinsic = null;
      _resolvedBytes = null;
    }
  }

  @override
  void dispose() {
    widget.zoom.removeListener(_onZoom);
    super.dispose();
  }

  // Latches the full-res fetch on once zoomed in; drops it again at Fit so
  // the big bitmap doesn't linger in memory.
  void _onZoom() {
    final scale = widget.zoom.value.getMaxScaleOnAxis();
    final want = scale > _fullZoomTrigger || (scale >= 1.01 && _wantFull);
    if (want != _wantFull) setState(() => _wantFull = want);
  }

  void _resolveIntrinsic(Uint8List bytes) {
    _resolvedBytes = bytes;
    final stream = MemoryImage(bytes).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        final size = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
        if (!mounted || _intrinsic == size) return;
        _intrinsic = size;
        // A cached image resolves synchronously, i.e. mid-build; the parent
        // may move the shared zoom, so wait for the frame to finish.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onIntrinsic(size);
        });
      },
      onError: (_, _) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photo;
    final focused = widget.focused;
    final onFocus = widget.onFocus;
    final onRemove = widget.onRemove;
    final loupe = ref.watch(loupePreviewProvider(photo.path)).value;
    final thumb = ref.watch(thumbnailProvider(photo.path)).value;
    final full = (_wantFull || widget.forceFull)
        ? ref.watch(loupeFullPreviewProvider(photo.path)).value
        : null;
    final bytes = full ?? loupe ?? thumb;
    final source = full ?? loupe;
    if (source != null && !identical(source, _resolvedBytes)) {
      _resolveIntrinsic(source);
    }
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
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        _viewport = c.biggest;
                        widget.onViewport(_viewport);
                        return _image(photo, bytes);
                      },
                    ),
                  ),
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

  Widget _image(Photo photo, Uint8List? bytes) {
    if (bytes == null) {
      return Center(
        child: Icon(
          photo.isRaw ? Icons.raw_on_rounded : Icons.image_outlined,
          color: AppColors.textSecondary,
          size: 48,
        ),
      );
    }
    return InteractiveViewer(
      transformationController: widget.zoom,
      maxScale: widget.maxScale,
      child: RotatedBox(
        quarterTurns: photo.userRotation,
        child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
      ),
    );
  }
}
