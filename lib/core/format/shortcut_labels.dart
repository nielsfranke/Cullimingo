/// Display labels for the app-level ⌘/Ctrl shortcuts, in the platform's own
/// notation: Mac glyphs on macOS, spelled-out modifiers on Linux/Windows,
/// where ⌘ means nothing (GitHub #15).
library;

import 'package:flutter/foundation.dart';

/// [key] with the primary modifier (plus Shift when [shift] is set):
/// `⌘R` / `⌘⇧Z` / `⌘⌫` on macOS, `Ctrl+R` / `Ctrl+Shift+Z` /
/// `Ctrl+Backspace` elsewhere. Reads [defaultTargetPlatform], so widget tests
/// can switch platforms with `debugDefaultTargetPlatformOverride`.
String modShortcut(String key, {bool shift = false}) {
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    return '⌘${shift ? '⇧' : ''}${key == 'Backspace' ? '⌫' : key}';
  }
  return 'Ctrl+${shift ? 'Shift+' : ''}$key';
}

/// The primary modifier on its own, for prose ("the ⌘ combos"): `⌘` on
/// macOS, `Ctrl` elsewhere.
String get modKeyName =>
    defaultTargetPlatform == TargetPlatform.macOS ? '⌘' : 'Ctrl';
