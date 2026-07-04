import 'package:cullimingo/shared/models/cull_marks.dart';

/// One undoable cull-mark change: the per-photo values as they were *before*
/// the change plus the value that was applied, so it can be reverted and
/// re-applied. Batch operations are a single entry — one ⌘Z takes back a whole
/// "rate 5 on 300 photos".
sealed class CullUndoEntry {
  const CullUndoEntry();

  /// How many photos this entry touches.
  int get photoCount;

  /// Short lower-case name of what changed ("rating", "flag", …).
  String get noun;

  /// Human-readable summary for the notice bar ("rating (3 photos)").
  String describe() => photoCount == 1 ? noun : '$noun ($photoCount photos)';
}

/// A star-rating change.
class RatingUndoEntry extends CullUndoEntry {
  /// Captures [before] (photo id → previous rating) and the applied [after].
  const RatingUndoEntry({required this.before, required this.after});

  /// Photo id → rating before the change.
  final Map<int, int> before;

  /// The rating that was applied to every photo in [before].
  final int after;

  @override
  int get photoCount => before.length;

  @override
  String get noun => 'rating';
}

/// A pick/reject flag change.
class FlagUndoEntry extends CullUndoEntry {
  /// Captures [before] (photo id → previous flag) and the applied [after].
  const FlagUndoEntry({required this.before, required this.after});

  /// Photo id → flag before the change.
  final Map<int, PickFlag> before;

  /// The flag that was applied to every photo in [before].
  final PickFlag after;

  @override
  int get photoCount => before.length;

  @override
  String get noun => 'flag';
}

/// A colour-label change.
class ColorUndoEntry extends CullUndoEntry {
  /// Captures [before] (photo id → previous label) and the applied [after].
  const ColorUndoEntry({required this.before, required this.after});

  /// Photo id → colour label before the change.
  final Map<int, ColorLabel> before;

  /// The label that was applied to every photo in [before].
  final ColorLabel after;

  @override
  int get photoCount => before.length;

  @override
  String get noun => 'colour label';
}

/// A rotation. Stored as the applied delta, not a snapshot: undo applies the
/// inverse turn through the normal rotate path, which handles both the
/// JPEG EXIF-commit branch and the RAW widget-delta branch losslessly.
class RotationUndoEntry extends CullUndoEntry {
  /// Captures the rotated [photoIds] and the applied [quarterTurnsCW].
  const RotationUndoEntry({
    required this.photoIds,
    required this.quarterTurnsCW,
  });

  /// The photos that were rotated.
  final List<int> photoIds;

  /// The applied clockwise quarter-turns (negative = counter-clockwise).
  final int quarterTurnsCW;

  @override
  int get photoCount => photoIds.length;

  @override
  String get noun => 'rotation';
}

/// A bounded undo/redo stack for cull-mark changes. Pure bookkeeping — the
/// caller applies/reverts entries; this only orders them. A new [push] clears
/// the redo side (standard editor semantics); the undo side is capped at
/// [maxEntries], dropping the oldest.
class UndoHistory {
  /// Creates a history holding at most [maxEntries] undo steps.
  UndoHistory({this.maxEntries = 200});

  /// Cap on stored undo steps.
  final int maxEntries;

  final List<CullUndoEntry> _undo = [];
  final List<CullUndoEntry> _redo = [];

  /// Whether there is anything to undo.
  bool get canUndo => _undo.isNotEmpty;

  /// Whether there is anything to redo.
  bool get canRedo => _redo.isNotEmpty;

  /// Records a fresh change (clears the redo side).
  void push(CullUndoEntry entry) {
    _undo.add(entry);
    if (_undo.length > maxEntries) _undo.removeAt(0);
    _redo.clear();
  }

  /// Pops the newest undo step and moves it to the redo side, or `null` when
  /// there is nothing to undo. The caller reverts the returned entry.
  CullUndoEntry? takeUndo() {
    if (_undo.isEmpty) return null;
    final entry = _undo.removeLast();
    _redo.add(entry);
    return entry;
  }

  /// Pops the newest redo step and moves it back to the undo side, or `null`
  /// when there is nothing to redo. The caller re-applies the returned entry.
  CullUndoEntry? takeRedo() {
    if (_redo.isEmpty) return null;
    final entry = _redo.removeLast();
    _undo.add(entry);
    return entry;
  }

  /// Forgets everything (e.g. when the photos themselves are deleted).
  void clear() {
    _undo.clear();
    _redo.clear();
  }
}
