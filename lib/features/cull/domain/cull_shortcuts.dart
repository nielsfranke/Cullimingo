import 'package:flutter/services.dart';

/// A rebindable cull/view action (`BUILD_PLAN.md` §7/§8 — configurable keymap).
/// Navigation (arrows), overlay keys (Esc, Enter, `[`/`]`) and the ⌘/Ctrl
/// app combos are intentionally NOT here — they stay fixed.
enum CullAction {
  /// Flag as pick.
  pick('Pick', LogicalKeyboardKey.keyP),

  /// Flag as reject.
  reject('Reject', LogicalKeyboardKey.keyX),

  /// Clear the rating. `0` matches the de-facto culling standard (Photo
  /// Mechanic, Lightroom, Capture One all clear/zero a rating with `0`); Delete
  /// stays a fixed secondary.
  clearRating('Clear rating', LogicalKeyboardKey.digit0),

  /// Rate 1 star.
  rate1('Rate 1', LogicalKeyboardKey.digit1),

  /// Rate 2 stars.
  rate2('Rate 2', LogicalKeyboardKey.digit2),

  /// Rate 3 stars.
  rate3('Rate 3', LogicalKeyboardKey.digit3),

  /// Rate 4 stars.
  rate4('Rate 4', LogicalKeyboardKey.digit4),

  /// Rate 5 stars.
  rate5('Rate 5', LogicalKeyboardKey.digit5),

  /// Colour label red.
  colorRed('Colour: red', LogicalKeyboardKey.digit6),

  /// Colour label yellow.
  colorYellow('Colour: yellow', LogicalKeyboardKey.digit7),

  /// Colour label green.
  colorGreen('Colour: green', LogicalKeyboardKey.digit8),

  /// Colour label blue.
  colorBlue('Colour: blue', LogicalKeyboardKey.digit9),

  /// Colour label purple. Purple is the odd colour out across cullers (none
  /// give it a number key), so it parks on Backspace, freed by clear-rating
  /// moving to `0`.
  colorPurple('Colour: purple', LogicalKeyboardKey.backspace),

  /// Toggle the photo in the selection.
  select('Select', LogicalKeyboardKey.space),

  /// Open / close the loupe.
  loupe('Loupe', LogicalKeyboardKey.keyF),

  /// Compare the selection.
  compare('Compare selected', LogicalKeyboardKey.keyC),

  /// Compare the focused photo's group.
  compareBurst("Compare focused photo's group", LogicalKeyboardKey.keyB),

  /// Toggle the info inspector.
  inspector('Info inspector', LogicalKeyboardKey.keyI),

  /// Edit keywords.
  keywords('Edit keywords', LogicalKeyboardKey.keyK),

  /// Edit IPTC metadata (caption, creator, credit, location…).
  metadata('Edit metadata', LogicalKeyboardKey.keyM),

  /// Stamp the saved metadata template onto the selection/focused photo. `T`
  /// for template — plain T is free (⌘/Ctrl+T is new-tab, checked before the
  /// cull keys).
  applyTemplate('Apply metadata template', LogicalKeyboardKey.keyT),

  /// Rename the selection in place. `R` for rename — plain R is free
  /// (⌘/Ctrl+R is refresh-folder, checked before the cull keys). Photo
  /// Mechanic uses M, but M is already Edit-metadata here; rebindable anyway.
  rename('Rename…', LogicalKeyboardKey.keyR),

  /// Rotate the selection 90° clockwise. `.` (period) — the `[`/`]` keys that
  /// Lightroom uses are reserved here for loupe zoom, so rotate parks on the
  /// adjacent `,`/`.` pair. Rebindable.
  rotateRight('Rotate right', LogicalKeyboardKey.period),

  /// Rotate the selection 90° counter-clockwise. `,` (comma) — see
  /// [rotateRight].
  rotateLeft('Rotate left', LogicalKeyboardKey.comma);

  const CullAction(this.label, this.defaultKey);

  /// Human-readable action name.
  final String label;

  /// The default key for this action.
  final LogicalKeyboardKey defaultKey;
}

/// Human-readable label for a key (`P`, `Space`, `Backspace`, `6`, …) for the
/// shortcuts UI.
String keyDisplayLabel(LogicalKeyboardKey key) {
  final named = _namedKeys[key];
  if (named != null) return named;
  final label = key.keyLabel;
  return label.isNotEmpty ? label.toUpperCase() : (key.debugName ?? 'Key');
}

final Map<LogicalKeyboardKey, String> _namedKeys = {
  LogicalKeyboardKey.space: 'Space',
  LogicalKeyboardKey.backspace: 'Backspace',
  LogicalKeyboardKey.delete: 'Delete',
  LogicalKeyboardKey.enter: 'Enter',
  LogicalKeyboardKey.tab: 'Tab',
  LogicalKeyboardKey.arrowLeft: '←',
  LogicalKeyboardKey.arrowRight: '→',
  LogicalKeyboardKey.arrowUp: '↑',
  LogicalKeyboardKey.arrowDown: '↓',
  LogicalKeyboardKey.bracketLeft: '[',
  LogicalKeyboardKey.bracketRight: ']',
};

/// The resolved cull keymap: every [CullAction] mapped to a key, defaults
/// overlaid with the user's rebindings. Pure and immutable.
class CullShortcuts {
  /// Wraps a complete action→key map.
  const CullShortcuts(this._bindings);

  /// The default keymap.
  factory CullShortcuts.defaults() => CullShortcuts({
    for (final a in CullAction.values) a: a.defaultKey,
  });

  /// Builds from persisted [overrides] (action name → key id), falling back to
  /// defaults for anything unset or unknown.
  factory CullShortcuts.fromOverrides(Map<String, int> overrides) {
    final map = {for (final a in CullAction.values) a: a.defaultKey};
    final byName = {for (final a in CullAction.values) a.name: a};
    overrides.forEach((name, keyId) {
      final action = byName[name];
      if (action != null) map[action] = LogicalKeyboardKey(keyId);
    });
    return CullShortcuts(map);
  }

  final Map<CullAction, LogicalKeyboardKey> _bindings;

  /// Keys that may NOT be assigned to an action (they drive fixed navigation /
  /// overlay behaviour).
  static final Set<LogicalKeyboardKey> reservedKeys = {
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.tab,
    LogicalKeyboardKey.bracketLeft,
    LogicalKeyboardKey.bracketRight,
  };

  /// Whether [key] can be bound to an action.
  static bool isAssignable(LogicalKeyboardKey key) =>
      !reservedKeys.contains(key);

  /// The key bound to [action].
  LogicalKeyboardKey keyFor(CullAction action) => _bindings[action]!;

  /// The action bound to [key], or null if none.
  CullAction? actionFor(LogicalKeyboardKey key) {
    for (final entry in _bindings.entries) {
      if (entry.value == key) return entry.key;
    }
    return null;
  }

  /// The *other* action already bound to [key] (a conflict if [action] were
  /// rebound to it), or null if [key] is free.
  CullAction? conflictFor(CullAction action, LogicalKeyboardKey key) {
    for (final entry in _bindings.entries) {
      if (entry.key != action && entry.value == key) return entry.key;
    }
    return null;
  }

  /// Returns a copy with [action] rebound to [key].
  CullShortcuts withBinding(CullAction action, LogicalKeyboardKey key) =>
      CullShortcuts({..._bindings, action: key});

  /// The non-default bindings, as `actionName → keyId`, for persistence.
  Map<String, int> toOverrides() => {
    for (final entry in _bindings.entries)
      if (entry.value != entry.key.defaultKey)
        entry.key.name: entry.value.keyId,
  };
}
