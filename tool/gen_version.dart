// Regenerates `lib/core/version/app_version.g.dart` from `pubspec.yaml`'s
// `version:` field, so the app's version string has a single source of truth
// (the pubspec) instead of a hand-copied constant that drifts.
//
// Run manually with `dart run tool/gen_version.dart`; it also runs from the
// lefthook pre-commit hook whenever `pubspec.yaml` is staged.
import 'dart:io';

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final match = RegExp(r'^version:\s*(.+)$', multiLine: true).firstMatch(
    pubspec,
  );
  if (match == null) {
    stderr.writeln('gen_version: no `version:` line found in pubspec.yaml');
    exit(1);
  }
  // Drop the `+build` metadata — the About dialog and update check compare the
  // marketing version only (e.g. `1.0.0`, not `1.0.0+1`).
  final version = match.group(1)!.trim().split('+').first;

  final out = File('lib/core/version/app_version.g.dart');
  out.parent.createSync(recursive: true);
  out.writeAsStringSync('''
// GENERATED CODE — do not modify by hand.
// Regenerate with `dart run tool/gen_version.dart` (also runs from the lefthook
// pre-commit hook when pubspec.yaml changes).
//
// The app's marketing version, mirrored from pubspec.yaml's `version:` field
// (build metadata after `+` dropped). Used by the About dialog and the startup
// update check.
library;

/// The running app's marketing version (e.g. `1.0.0`), from pubspec.yaml.
const String kAppVersion = '$version';
''');
  stdout.writeln('gen_version: wrote kAppVersion = $version');
}
