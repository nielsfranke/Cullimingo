/// The photo ids a drag-out starting on [draggedId] should carry: the whole
/// [selectedIds] set when the dragged photo is part of it, otherwise just the
/// dragged photo. Mirrors marking (`CullSelection.markTargets`) so dragging a
/// selected photo drags the whole selection, while dragging an unselected one
/// drags only it.
Set<int> dragTargets(int draggedId, Set<int> selectedIds) =>
    selectedIds.contains(draggedId) ? selectedIds : {draggedId};
