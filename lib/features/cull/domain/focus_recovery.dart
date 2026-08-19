/// Picks the photo the keyboard cursor should land on when the focused one
/// disappears from the visible (filtered) set — unpicking while the grid is
/// filtered on picks, say, or tightening the filter with the loupe open.
///
/// [previous] is the visible order from before the change, [visible] the ids
/// that are left. The successor in the old order wins (the photo that slid
/// into the vanished one's place, so culling carries on where it was); if the
/// vanished photo was last, the nearest surviving predecessor is used.
///
/// Returns null when nothing from the old order survived — a tab switch or a
/// fresh import, where the caller's own focus handling should take over rather
/// than have focus yanked to an unrelated photo.
int? focusAfterDrop({
  required int focusedId,
  required List<int> previous,
  required Set<int> visible,
}) {
  final at = previous.indexOf(focusedId);
  if (at < 0) return null;
  for (var i = at + 1; i < previous.length; i++) {
    if (visible.contains(previous[i])) return previous[i];
  }
  for (var i = at - 1; i >= 0; i--) {
    if (visible.contains(previous[i])) return previous[i];
  }
  return null;
}
