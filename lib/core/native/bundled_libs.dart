import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves a native library that ships *inside* the packaged app, by filename
/// [prefix] (e.g. `libvips.`, `libraw.`, `libglib-2.0`). Returns null when not
/// running from a bundled app (dev / `flutter test`), so callers fall back to
/// the Homebrew/system search paths.
///
/// Packaged apps carry their native libs alongside the executable:
/// - **macOS**: `Cullimingo.app/Contents/libs`, produced by
///   `tool/bundle_macos.sh`. Relinked to `@executable_path/../libs`, so opening
///   the absolute path resolves the whole dependency tree from the bundle.
/// - **Linux**: `<bundle>/lib`, produced by `tool/bundle_linux.sh`. The libs
///   are patched to `RUNPATH=$ORIGIN`, so the loader resolves the rest of the
///   dependency tree from the same directory. This is also where Flutter drops
///   the engine + plugin `.so`s, so we match by [prefix]/extension.
///
/// See `BUILD_PLAN.md` §6.1.
String? bundledNativeLib(String prefix) {
  final dir = _bundledLibsDir;
  if (dir == null) return null;
  for (final entry in dir.listSync()) {
    if (entry is File && nativeLibMatches(p.basename(entry.path), prefix)) {
      return entry.path;
    }
  }
  return null;
}

/// Whether [name] is the native library file for [prefix] on the current
/// platform: a `.dylib` on macOS, or a `.so` / versioned `.so.N` on Linux.
/// Pass [linux] to override the platform (tests).
bool nativeLibMatches(String name, String prefix, {bool? linux}) {
  if (!name.startsWith(prefix)) return false;
  if (linux ?? Platform.isLinux) {
    return name.endsWith('.so') || name.contains('.so.');
  }
  return name.endsWith('.dylib');
}

Directory? _cached;
bool _resolved = false;

/// The bundled native-libs directory, or null when not packaged. Resolved once.
Directory? get _bundledLibsDir {
  if (_resolved) return _cached;
  _resolved = true;
  final exeDir = p.dirname(Platform.resolvedExecutable);
  final String libsPath;
  if (Platform.isMacOS) {
    libsPath = p.normalize(p.join(exeDir, '..', 'libs'));
  } else if (Platform.isLinux) {
    libsPath = p.join(exeDir, 'lib');
  } else {
    return _cached = null;
  }
  final dir = Directory(libsPath);
  return _cached = dir.existsSync() ? dir : null;
}
