import 'package:flutter/foundation.dart';

/// A user-configured external editor to hand photos to — the "Send to" menu and
/// the ⌘E "open in primary editor" shortcut (`BUILD_PLAN.md` §7, the generic
/// "open with" path; app-specific scripting is deliberately out of scope).
@immutable
class ExternalEditor {
  /// Creates an editor entry.
  const ExternalEditor({required this.label, required this.path});

  /// Display name shown in the menu (e.g. "Capture One").
  final String label;

  /// Launch target: an `.app` bundle on macOS (opened via `open -a`), an
  /// executable elsewhere (invoked with the file paths as arguments).
  final String path;

  /// Parses a persisted map, or null when it's missing fields / malformed (so a
  /// hand-edited settings file can't crash the list).
  static ExternalEditor? fromJson(Map<String, dynamic> json) {
    final label = json['label'];
    final path = json['path'];
    if (label is! String || path is! String || label.isEmpty || path.isEmpty) {
      return null;
    }
    return ExternalEditor(label: label, path: path);
  }

  /// The persisted form.
  Map<String, dynamic> toJson() => {'label': label, 'path': path};

  @override
  bool operator ==(Object other) =>
      other is ExternalEditor && other.label == label && other.path == path;

  @override
  int get hashCode => Object.hash(label, path);
}
