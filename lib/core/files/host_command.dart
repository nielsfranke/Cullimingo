import 'dart:io';

/// Whether this process runs inside a Flatpak sandbox. Flatpak sets
/// `FLATPAK_ID` and mounts `/.flatpak-info` in every sandbox.
final bool runningInFlatpak =
    Platform.isLinux &&
    (Platform.environment.containsKey('FLATPAK_ID') ||
        File('/.flatpak-info').existsSync());

/// Rewrites an invocation of a *host* tool (`gio`, `lsblk`, `udisksctl`,
/// `ffmpeg`, a user-chosen editor, …) so it reaches the real system from inside
/// the Flatpak sandbox: `flatpak-spawn --host <exe> <args>`. Outside a sandbox
/// it is returned unchanged.
///
/// The sandbox has none of those binaries, its own private trash and no
/// udisks access, so running them in-sandbox silently does nothing useful.
/// Needs `--talk-name=org.freedesktop.Flatpak` in the manifest. Paths passed
/// as arguments must be the same on both sides — true for anything under the
/// shared home, `/media`, `/run/media` or the app's `~/.var/app` dirs, but not
/// for the sandbox's private `/tmp` (see [hostVisibleTempDir]).
(String, List<String>) hostCommand(
  String executable,
  List<String> arguments, {
  bool? sandboxed,
}) => (sandboxed ?? runningInFlatpak)
    ? ('flatpak-spawn', ['--host', executable, ...arguments])
    : (executable, arguments);

/// A temp directory a host tool started via [hostCommand] can write to. The
/// sandbox's `/tmp` is private, so under Flatpak this is the app's cache dir
/// (`~/.var/app/<id>/cache`, the same path on both sides); otherwise the
/// system temp dir.
Directory hostVisibleTempDir() {
  final cache = Platform.environment['XDG_CACHE_HOME'];
  if (runningInFlatpak && cache != null && cache.isNotEmpty) {
    return Directory(cache)..createSync(recursive: true);
  }
  return Directory.systemTemp;
}
