/// The decode resolution for a grid thumbnail, in physical pixels.
///
/// A cell's [displayWidth] changes continuously while the window is resized
/// (the fixed-column grid recomputes cell width every frame). Feeding that raw
/// value into `Image.memory`'s `cacheWidth` would key a fresh decode on every
/// intermediate width, so a single resize drag re-decodes every visible
/// thumbnail dozens of times — visible jank.
///
/// Quantising the target to [bucket]-pixel steps collapses those hundreds of
/// widths into a handful of stable cache keys, so a cell keeps the same decode
/// across most of a resize. Decoding up to one bucket larger than needed is
/// invisible (the widget scales to the real box) and costs a little extra
/// memory, never sharpness. Capped at [maxWidth] so oversized cells don't
/// decode past the cached source resolution.
int thumbnailDecodeWidth({
  required double displayWidth,
  required double devicePixelRatio,
  int bucket = 64,
  int maxWidth = 1024,
}) {
  final target = displayWidth * devicePixelRatio;
  if (target <= 0) return 1;
  final bucketed = (target / bucket).ceil() * bucket;
  return bucketed.clamp(1, maxWidth);
}
