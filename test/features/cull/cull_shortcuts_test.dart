import 'package:cullimingo/features/cull/domain/cull_shortcuts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults map every action and resolve back', () {
    final s = CullShortcuts.defaults();
    for (final a in CullAction.values) {
      expect(s.keyFor(a), a.defaultKey);
      expect(s.actionFor(a.defaultKey), a);
    }
    expect(s.actionFor(LogicalKeyboardKey.keyP), CullAction.pick);
    expect(s.actionFor(LogicalKeyboardKey.keyT), CullAction.applyTemplate);
    expect(s.toOverrides(), isEmpty);
  });

  test('defaults follow the de-facto culling standard', () {
    final s = CullShortcuts.defaults();
    // 0 clears the rating — the Photo Mechanic / Lightroom / Capture One
    // convention, so incoming photographers keep their muscle memory.
    expect(s.keyFor(CullAction.clearRating), LogicalKeyboardKey.digit0);
    expect(s.actionFor(LogicalKeyboardKey.digit0), CullAction.clearRating);
    // Colours red/yellow/green/blue on 6–9; purple is the odd one out.
    expect(s.keyFor(CullAction.colorRed), LogicalKeyboardKey.digit6);
    expect(s.keyFor(CullAction.colorBlue), LogicalKeyboardKey.digit9);
    expect(s.keyFor(CullAction.colorPurple), LogicalKeyboardKey.backspace);
    // Pick / reject on P / X.
    expect(s.keyFor(CullAction.pick), LogicalKeyboardKey.keyP);
    expect(s.keyFor(CullAction.reject), LogicalKeyboardKey.keyX);
    // No two actions share a key.
    final keys = [for (final a in CullAction.values) s.keyFor(a)];
    expect(keys.toSet().length, keys.length);
  });

  test('rebinding moves the action and records an override', () {
    final s = CullShortcuts.defaults().withBinding(
      CullAction.pick,
      LogicalKeyboardKey.keyG,
    );
    expect(s.keyFor(CullAction.pick), LogicalKeyboardKey.keyG);
    expect(s.actionFor(LogicalKeyboardKey.keyG), CullAction.pick);
    expect(s.toOverrides(), {'pick': LogicalKeyboardKey.keyG.keyId});
  });

  test('conflictFor reports a key already used by another action', () {
    final s = CullShortcuts.defaults();
    // X is reject; binding pick to X conflicts with reject.
    expect(
      s.conflictFor(CullAction.pick, LogicalKeyboardKey.keyX),
      CullAction.reject,
    );
    // A free key has no conflict.
    expect(s.conflictFor(CullAction.pick, LogicalKeyboardKey.keyG), isNull);
    // The action's own current key is not a conflict.
    expect(s.conflictFor(CullAction.pick, LogicalKeyboardKey.keyP), isNull);
  });

  test('reserved navigation/overlay keys are not assignable', () {
    expect(CullShortcuts.isAssignable(LogicalKeyboardKey.arrowLeft), isFalse);
    expect(CullShortcuts.isAssignable(LogicalKeyboardKey.escape), isFalse);
    expect(CullShortcuts.isAssignable(LogicalKeyboardKey.enter), isFalse);
    expect(CullShortcuts.isAssignable(LogicalKeyboardKey.bracketLeft), isFalse);
    expect(CullShortcuts.isAssignable(LogicalKeyboardKey.keyG), isTrue);
  });

  test('fromOverrides applies stored bindings and ignores unknowns', () {
    final s = CullShortcuts.fromOverrides({
      'pick': LogicalKeyboardKey.keyG.keyId,
      'bogus': LogicalKeyboardKey.keyZ.keyId,
    });
    expect(s.keyFor(CullAction.pick), LogicalKeyboardKey.keyG);
    expect(s.keyFor(CullAction.reject), CullAction.reject.defaultKey);
  });
}
