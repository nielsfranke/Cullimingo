/// A grid item to hold steady across a zoom (thumbnail-size) change: the item
/// `index` plus the y-offset (`screenY`) its row had relative to the viewport
/// top.
typedef ZoomAnchor = ({int index, double screenY});

/// Picks the grid item to keep under the eye when thumbnails resize, using the
/// *outgoing* layout. Prefers [focusedIndex] when its row is on screen (so the
/// user's active photo stays put); otherwise anchors the item nearest the
/// viewport centre. Returns `null` when the grid is empty or unmeasured.
///
/// [rowHeight] is the cell main-axis extent plus the inter-row spacing. Pass
/// `focusedIndex: -1` when nothing is focused.
ZoomAnchor? zoomAnchor({
  required double offset,
  required double viewportHeight,
  required int columns,
  required double rowHeight,
  required int count,
  required int focusedIndex,
}) {
  if (columns < 1 || count <= 0 || rowHeight <= 0) return null;

  final firstVisibleRow = (offset / rowHeight).floor();
  final lastVisibleRow = ((offset + viewportHeight) / rowHeight).ceil();

  final int index;
  if (focusedIndex >= 0 &&
      focusedIndex ~/ columns >= firstVisibleRow &&
      focusedIndex ~/ columns < lastVisibleRow) {
    index = focusedIndex;
  } else {
    final centreRow = ((offset + viewportHeight / 2) / rowHeight).floor();
    index = (centreRow * columns).clamp(0, count - 1);
  }

  final rowTop = (index ~/ columns) * rowHeight;
  return (index: index, screenY: rowTop - offset);
}

/// The scroll offset that places [anchor]'s row at the same on-screen y it had
/// before the zoom, under the *incoming* layout ([columns]/[rowHeight]).
/// [maxScrollExtent] clamps the result so it never overscrolls.
double zoomReanchorOffset({
  required ZoomAnchor anchor,
  required int columns,
  required double rowHeight,
  required double maxScrollExtent,
}) {
  if (columns < 1) return 0;
  final rowTop = (anchor.index ~/ columns) * rowHeight;
  return (rowTop - anchor.screenY).clamp(0.0, maxScrollExtent);
}
