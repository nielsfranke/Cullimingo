/// Arrow-key directions within the cull grid.
enum GridDirection {
  /// Previous cell.
  left,

  /// Next cell.
  right,

  /// One row up.
  up,

  /// One row down.
  down,
}

/// Pure focus-movement logic for the grid. Given the [current] index, total
/// [count] and [columns] per row, returns the next index for [direction],
/// clamped to the grid and never wrapping rows. Tested in isolation so the
/// keyboard feel can't silently regress (Phase 1 DoD).
int moveFocus({
  required int current,
  required int count,
  required int columns,
  required GridDirection direction,
}) {
  if (count <= 0) return 0;
  final cols = columns < 1 ? 1 : columns;
  final clamped = current.clamp(0, count - 1);

  switch (direction) {
    case GridDirection.left:
      return (clamped - 1).clamp(0, count - 1);
    case GridDirection.right:
      return (clamped + 1).clamp(0, count - 1);
    case GridDirection.up:
      final up = clamped - cols;
      return up < 0 ? clamped : up;
    case GridDirection.down:
      final down = clamped + cols;
      return down >= count ? clamped : down;
  }
}
