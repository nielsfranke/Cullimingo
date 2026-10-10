import 'package:cullimingo/core/format/shortcut_labels.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('macOS uses the Mac glyphs', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(modShortcut('R'), '⌘R');
    expect(modShortcut('Z', shift: true), '⌘⇧Z');
    expect(modShortcut('Backspace'), '⌘⌫');
    expect(modKeyName, '⌘');
  });

  test('Linux spells the modifiers out (#15)', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(modShortcut('R'), 'Ctrl+R');
    expect(modShortcut('Z', shift: true), 'Ctrl+Shift+Z');
    expect(modShortcut('Backspace'), 'Ctrl+Backspace');
    expect(modKeyName, 'Ctrl');
  });
}
