import 'dart:ui';

/// The pixel long edge to cache loupe previews at, derived from the hardware.
///
/// Returns the largest physical long edge across [displaySizes] (device
/// pixels), so a full-screen loupe stays pixel-sharp on whichever monitor the
/// window is dragged to — a fixed 2048px looked soft on 4K/5K/Retina panels.
/// Clamped to [[floor], [ceil]]: the floor keeps us no worse than the old fixed
/// size (and covers a bit of zoom on ≤1080p displays), the ceil bounds decode
/// cost + cache size on an enormous canvas. Falls back to [floor] when no
/// display is reported (headless / tests).
///
/// [Display.size] is already in physical pixels, so no devicePixelRatio math is
/// needed — the loupe rasterises to that many device pixels at fit-to-screen.
int loupeLongEdgeForDisplays(
  Iterable<Size> displaySizes, {
  int floor = 2048,
  int ceil = 6016,
}) {
  var longest = 0.0;
  for (final size in displaySizes) {
    if (size.longestSide > longest) longest = size.longestSide;
  }
  if (longest <= 0) return floor;
  return longest.round().clamp(floor, ceil);
}
