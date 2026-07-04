import 'package:cullimingo/features/cull/domain/grid_navigation.dart';

/// Pure focus logic for the compare overlay's keyboard culling (§8): which tile
/// the arrow keys land on, and where focus goes after a tile is dropped. Kept
/// pure so the keyboard feel can't silently regress.

/// The id to focus after moving [direction] from [focusedId] across [ids] laid
/// out in [columns] columns. Mirrors the grid's [moveFocus]; returns
/// [focusedId] unchanged when it isn't in [ids].
int compareFocusAfterMove({
  required List<int> ids,
  required int focusedId,
  required int columns,
  required GridDirection direction,
}) {
  final index = ids.indexOf(focusedId);
  if (index < 0) return focusedId;
  final next = moveFocus(
    current: index,
    count: ids.length,
    columns: columns,
    direction: direction,
  );
  return ids[next];
}

/// The id to focus after dropping [removedId] from [ids] (the pre-removal list)
/// while [focusedId] was focused. Keeps the same slot position so focus doesn't
/// jump to the far end; returns null when nothing remains, or the unchanged
/// [focusedId] when a non-focused tile was dropped.
int? compareFocusAfterRemove({
  required List<int> ids,
  required int removedId,
  required int? focusedId,
}) {
  final remaining = [
    for (final id in ids)
      if (id != removedId) id,
  ];
  if (remaining.isEmpty) return null;
  if (focusedId != removedId) return focusedId;
  final idx = ids.indexOf(removedId);
  return remaining[idx.clamp(0, remaining.length - 1)];
}
