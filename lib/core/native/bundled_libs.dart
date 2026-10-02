import 'dart:ffi';
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

/// Loads the *host-preferred* native libs — those under the bundle's
/// `lib/fallback/` (Linux, see `tool/bundle_linux.sh`) — preferring the host's
/// own copy and taking ours only when the host has none. Call before opening
/// libvips: once a library with a given soname is in the process, the dynamic
/// loader hands every later request for that soname the same copy, libvips'
/// `DT_NEEDED` included.
///
/// Why the host must win: these libs are part of the host's GTK desktop
/// stack too, and host *plugins* bind to them later — gdk-pixbuf's SVG loader
/// (Debian's, built against Debian's librsvg) is dlopen'd the first time GTK
/// draws an SVG icon, i.e. when the file chooser opens. With our older
/// bundled librsvg already loaded, that plugin resolved against it, hit a
/// symbol it lacks and GTK aborted the app (GitHub #2). The fallback dir sits
/// outside every RUNPATH, so nothing reaches it unless this function does.
///
/// Host-wins is safe the other way round too: the bundled libvips (Ubuntu
/// 24.04 build) uses nothing past librsvg 2.52, and every distro new enough
/// for this AppImage's glibc floor ships 2.57 or later. A host *older* than
/// that can't load the AppImage at all.
///
/// No-op when not packaged or on macOS (no `fallback/` dir: the .app carries
/// its own GTK-free dependency tree). Best effort: a lib that fails to open
/// both ways is left to libvips' own load, which reports the real error.
/// [open] is injectable for tests; it must throw on failure, like
/// `DynamicLibrary.open`.
void preloadHostPreferredLibs({
  Directory? fallbackDir,
  void Function(String nameOrPath) open = _dlopen,
}) {
  if (_preloaded) return;
  _preloaded = true;
  final dir =
      fallbackDir ??
      (_bundledLibsDir == null
          ? null
          : Directory(p.join(_bundledLibsDir!.path, 'fallback')));
  if (dir == null) return;
  final List<String> sonames;
  try {
    sonames = hostPreferredSonames(dir);
  } on FileSystemException {
    return; // no fallback dir, or unreadable: nothing to prefer
  }
  for (final soname in sonames) {
    try {
      open(soname); // the host's copy, via the normal search path
    } on Object {
      try {
        open(p.join(dir.path, soname)); // ours, by absolute path
      } on Object {
        // Leave it to libvips' load to report.
      }
    }
  }
}

bool _preloaded = false;

void _dlopen(String nameOrPath) => DynamicLibrary.open(nameOrPath);

/// The sonames shipped in [fallbackDir] — Linux `.so`s, as only the Linux
/// bundle has such a dir — sorted for a deterministic load order. Throws
/// [FileSystemException] when the dir can't be listed. Exposed for tests.
List<String> hostPreferredSonames(Directory fallbackDir) =>
    fallbackDir
        .listSync()
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .where((n) => nativeLibMatches(n, 'lib', linux: true))
        .toList()
      ..sort();

/// Test hook: resets [preloadHostPreferredLibs]' once-per-isolate guard.
void debugResetHostPreferredLibs() => _preloaded = false;

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
