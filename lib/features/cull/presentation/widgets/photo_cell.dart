import 'dart:typed_data';

import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/files/supported_files.dart';
import 'package:cullimingo/features/cull/domain/thumbnail_decode.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:cullimingo/shared/widgets/color_dot.dart';
import 'package:cullimingo/shared/widgets/flag_badge.dart';
import 'package:cullimingo/shared/widgets/rating_stars.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// A single grid cell: image with rating/flag/colour overlays, filename, and a
/// focus/selection border — the Aftershoot cell anatomy in `BUILD_PLAN.md` §7.
///
/// Data-driven (no Riverpod) so it stays cheap to widget-test; the only local
/// state is mouse-hover, which reveals the quick-action bar (rotate / edit
/// metadata). The action callbacks are optional — omit them and no bar shows.
class PhotoCell extends StatefulWidget {
  /// Creates a grid cell for [photo].
  const PhotoCell({
    required this.photo,
    required this.thumbnail,
    required this.cellWidth,
    this.focused = false,
    this.selected = false,
    this.burstSize = 1,
    this.groupColor,
    this.paired = false,
    this.onRotateLeft,
    this.onRotateRight,
    this.onEditMetadata,
    super.key,
  });

  /// The photo row backing this cell.
  final Photo photo;

  /// Decoded preview bytes, or `null` for a placeholder.
  final Uint8List? thumbnail;

  /// The nominal (zoom-slider) cell width in logical pixels. Drives the decode
  /// resolution — deliberately *not* the live layout width, so a window resize
  /// never changes `cacheWidth` and thus never re-decodes or flickers (the
  /// Photo-Mechanic-style fixed decode; §7).
  final double cellWidth;

  /// Size of this photo's capture-time burst (§8); >1 shows a stack badge.
  final int burstSize;

  /// Colour identifying this photo's burst/similar group (§8) — tints the stack
  /// badge so neighbouring groups differ. Null = no group tint (badge stays
  /// neutral); set only while the Bursts/Similar filter is active.
  final Color? groupColor;

  /// Whether this photo is one side of a RAW+JPEG pair (§8) — shows a small
  /// "RAW+JPG" badge so the pairing is visible in the grid.
  final bool paired;

  /// Whether this cell has keyboard focus (accent border).
  final bool focused;

  /// Whether this cell is part of the current selection (green border).
  final bool selected;

  /// Rotates this photo 90° counter-clockwise (hover action). Null hides it.
  final VoidCallback? onRotateLeft;

  /// Rotates this photo 90° clockwise (hover action). Null hides it.
  final VoidCallback? onRotateRight;

  /// Opens the metadata editor for this photo (hover action). Null hides it.
  final VoidCallback? onEditMetadata;

  @override
  State<PhotoCell> createState() => _PhotoCellState();
}

class _PhotoCellState extends State<PhotoCell> {
  bool _hovering = false;

  bool get _hasActions =>
      widget.onRotateLeft != null ||
      widget.onRotateRight != null ||
      widget.onEditMetadata != null;

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.selected
        ? AppColors.selection
        : widget.focused
        ? AppColors.accent
        : AppColors.border;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.cell),
          border: Border.all(
            color: borderColor,
            width: widget.selected || widget.focused ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _imageWithOverlays(context)),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Text(
                p.basename(widget.photo.path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imageWithOverlays(BuildContext context) {
    final photo = widget.photo;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.thumbnail != null)
          // The preview is already upright per the file's EXIF orientation;
          // RotatedBox applies only the user's extra quarter-turns (§ rotate).
          // contain (not cover) so the real aspect ratio shows — portrait reads
          // as portrait, landscape as landscape, like Photo Mechanic (§7).
          // Decode at the (bucketed) nominal zoom width via the native codec —
          // not the live cell width — so a window resize keeps the exact same
          // `cacheWidth`. That means zero re-decodes (and zero flicker) while
          // dragging the window; only changing the zoom slider re-decodes, and
          // gaplessPlayback covers that swap. Capped at the 1024px cached
          // source so the largest zoom doesn't upscale.
          RotatedBox(
            quarterTurns: photo.userRotation,
            child: Image.memory(
              widget.thumbnail!,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              cacheWidth: thumbnailDecodeWidth(
                displayWidth: widget.cellWidth,
                devicePixelRatio: dpr,
              ),
              // A corrupt/truncated file whose bytes reach the decoder shows a
              // friendly broken-image tile, not the raw "Exception: Invalid
              // image data" string (the decode error is still logged via
              // FlutterError.onError → appTalker).
              errorBuilder: (_, _, _) => _brokenPlaceholder(),
            ),
          )
        else
          _placeholder(),
        // Play badge marks videos (whether or not a poster frame loaded).
        if (isVideoPath(photo.path))
          const Center(
            child: Icon(
              Icons.play_circle_fill_rounded,
              size: 40,
              color: Colors.white70,
            ),
          ),
        if (photo.flag != PickFlag.none)
          Positioned(
            top: AppSpacing.xs,
            left: AppSpacing.xs,
            child: FlagBadge(flag: photo.flag),
          ),
        // A sidecar edited outside Cullimingo clashed with a local change; the
        // newer side won (last-writer-wins) — flag it so the user can review.
        if (photo.xmpConflict)
          const Positioned(
            top: AppSpacing.xs,
            right: AppSpacing.xs,
            child: Tooltip(
              message:
                  'Sidecar changed outside Cullimingo (resolved newest-wins)',
              child: Icon(
                Icons.sync_problem_rounded,
                size: 18,
                color: AppColors.labelYellow,
              ),
            ),
          ),
        // Burst badge: this photo is one of N shot in rapid succession (§8).
        if (widget.burstSize > 1)
          Positioned(
            top: AppSpacing.xs,
            right: AppSpacing.xs,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color:
                    widget.groupColor?.withValues(alpha: 0.9) ??
                    Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.burst_mode_rounded,
                    size: 12,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${widget.burstSize}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        // RAW+JPEG pair badge (§8): top-left, pushed below the flag badge when
        // one is shown so they don't overlap.
        if (widget.paired)
          Positioned(
            top: photo.flag != PickFlag.none ? 26 : AppSpacing.xs,
            left: AppSpacing.xs,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.burst_mode_outlined,
                    size: 12,
                    color: Colors.white,
                  ),
                  SizedBox(width: 3),
                  Text(
                    'RAW+JPG',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Positioned(
          bottom: AppSpacing.xs,
          left: AppSpacing.sm,
          child: RatingStars(rating: photo.rating),
        ),
        if (photo.colorLabel != ColorLabel.none)
          Positioned(
            bottom: AppSpacing.sm,
            right: AppSpacing.sm,
            child: ColorDot(label: photo.colorLabel),
          ),
        // Caption badge (Phase 4b): this photo already carries an IPTC caption,
        // so a caption pass can skip it. Sits left of the colour dot; the
        // tooltip previews the text without opening the editor.
        if (photo.iptc.caption.trim().isNotEmpty)
          Positioned(
            bottom: AppSpacing.sm - 1,
            right: photo.colorLabel != ColorLabel.none ? 24 : AppSpacing.sm,
            child: Tooltip(
              message: photo.iptc.caption,
              child: const Icon(
                Icons.notes_rounded,
                size: 13,
                color: Colors.white70,
                shadows: [Shadow(color: Colors.black87, blurRadius: 3)],
              ),
            ),
          ),
        // Crop badge: the source carries a Lightroom/Camera-Raw crop we only
        // display (read-only). Sits left of the caption/colour cluster.
        if (photo.hasCrop)
          Positioned(
            bottom: AppSpacing.sm - 1,
            right: _cropBadgeRight,
            child: const Tooltip(
              message: 'Cropped in Lightroom / Camera Raw',
              child: Icon(
                Icons.crop_rounded,
                size: 13,
                color: Colors.white70,
                shadows: [Shadow(color: Colors.black87, blurRadius: 3)],
              ),
            ),
          ),
        // Quick-action bar, revealed on hover: rotate / edit metadata. Floats
        // top-centre over the badges (which it briefly covers while hovering).
        if (_hovering && _hasActions)
          Positioned(
            top: AppSpacing.xs,
            left: 0,
            right: 0,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.onRotateLeft != null)
                      _HoverAction(
                        icon: Icons.rotate_left_rounded,
                        tooltip: 'Rotate left',
                        onTap: widget.onRotateLeft!,
                      ),
                    if (widget.onRotateRight != null)
                      _HoverAction(
                        icon: Icons.rotate_right_rounded,
                        tooltip: 'Rotate right',
                        onTap: widget.onRotateRight!,
                      ),
                    if (widget.onEditMetadata != null)
                      _HoverAction(
                        icon: Icons.edit_note_rounded,
                        tooltip: 'Edit metadata',
                        onTap: widget.onEditMetadata!,
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // Horizontal offset for the crop badge so it clears the colour dot and the
  // caption badge when either is present.
  double get _cropBadgeRight {
    final photo = widget.photo;
    var right = photo.colorLabel != ColorLabel.none ? 24.0 : AppSpacing.sm;
    if (photo.iptc.caption.trim().isNotEmpty) right += 16;
    return right;
  }

  Widget _placeholder() {
    final photo = widget.photo;
    final IconData icon;
    if (isVideoPath(photo.path)) {
      icon = Icons.movie_outlined;
    } else if (photo.isRaw) {
      icon = Icons.raw_on_rounded;
    } else {
      icon = Icons.image_outlined;
    }
    return ColoredBox(
      color: AppColors.surfaceElevated,
      child: Center(
        child: Icon(icon, color: AppColors.textSecondary, size: 28),
      ),
    );
  }

  /// Shown when an image's bytes fail to decode (corrupt/truncated file) — a
  /// quiet broken-image tile in place of Flutter's default red error text.
  Widget _brokenPlaceholder() => const ColoredBox(
    color: AppColors.surfaceElevated,
    child: Center(
      child: Icon(
        Icons.broken_image_outlined,
        color: AppColors.textSecondary,
        size: 28,
      ),
    ),
  );
}

/// A compact icon button in the thumbnail's hover action bar.
class _HoverAction extends StatelessWidget {
  const _HoverAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    tooltip: tooltip,
    iconSize: 18,
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
    padding: EdgeInsets.zero,
    color: Colors.white,
    icon: Icon(icon),
  );
}

/// Distinct, dark-friendly hues cycled across burst/similar groups so adjacent
/// groups read as different (§8). Deliberately avoids green — that's the
/// selection colour ([AppColors.selection]) and must not be confused with it.
const List<Color> kBurstGroupColors = [
  Color(0xFF38BDF8), // sky
  Color(0xFFF59E0B), // amber
  Color(0xFFF472B6), // pink
  Color(0xFFA78BFA), // violet
  Color(0xFF22D3EE), // cyan
  Color(0xFFFB7185), // rose
  Color(0xFFFB923C), // orange
  Color(0xFFE879F9), // fuchsia
];

/// The colour for a group at [index] (cycling [kBurstGroupColors]), or null
/// when [index] is null (the photo stands alone).
Color? burstGroupColor(int? index) =>
    index == null ? null : kBurstGroupColors[index % kBurstGroupColors.length];
