import 'dart:io';

import 'package:cullimingo/core/files/host_command.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Opens [path] in the platform's default application — used for videos, which
/// Cullimingo doesn't play in-app (it hands off to the system player).
Future<void> openExternally(String path) async {
  if (Platform.isMacOS) {
    await Process.run('open', [path]);
  } else if (Platform.isLinux) {
    await Process.run('xdg-open', [path]);
  } else if (Platform.isWindows) {
    await Process.run('cmd', ['/c', 'start', '', path]);
  }
}

/// Opens [paths] in a specific application [appPath] — Photo-Mechanic-style
/// "Edit with" / the "Send to" menu. On macOS [appPath] is an `.app` bundle
/// launched via `open -a` (all files land in one instance); elsewhere it's an
/// executable invoked with the file paths as arguments, detached so it outlives
/// this process (via the host under Flatpak — the editor lives outside the
/// sandbox).
Future<void> openInApp(String appPath, List<String> paths) async {
  if (paths.isEmpty) return;
  if (Platform.isMacOS) {
    await Process.run('open', ['-a', appPath, ...paths]);
  } else {
    final (exe, args) = hostCommand(appPath, paths);
    await Process.start(exe, args, mode: ProcessStartMode.detached);
  }
}

/// The menu label for [revealInFileManager], named for the platform's own file
/// manager so it reads native — "Reveal in Finder" is macOS-only wording.
String get revealInFileManagerLabel {
  if (Platform.isMacOS) return 'Reveal in Finder';
  if (Platform.isWindows) return 'Show in Explorer';
  return 'Show in File Manager';
}

/// Reveals [path] in the platform's file manager with the file itself selected.
/// macOS uses Finder (`open -R`) and Windows uses Explorer (`/select,`). On
/// Linux we ask the freedesktop `org.freedesktop.FileManager1` D-Bus service to
/// `ShowItems` — Nautilus, Dolphin, Nemo, Thunar et al. implement it and it
/// selects the file — falling back to opening the parent folder (no selection)
/// when that service or `dbus-send` is unavailable.
Future<void> revealInFileManager(String path) async {
  if (Platform.isMacOS) {
    await Process.run('open', ['-R', path]);
  } else if (Platform.isWindows) {
    await Process.run('explorer', ['/select,', path]);
  } else if (Platform.isLinux) {
    final shown = await _linuxShowItem(path);
    if (!shown) await Process.run('xdg-open', [p.dirname(path)]);
  }
}

/// The `file://` URI for [path] as `dbus-send` must receive it inside an
/// `array:string:` argument. `dbus-send` splits array elements on every comma
/// and has no escape, and gvfs mounts SMB shares under names full of them
/// (`smb-share:server=nas.local,share=photos`): the one URI arrived as two
/// broken ones and the file manager fell back to the home folder (GitHub #14).
/// A percent-encoded comma means the same path to every URI parser.
@visibleForTesting
String showItemsUri(String path) =>
    Uri.file(path).toString().replaceAll(',', '%2C');

/// Asks the freedesktop FileManager1 service to reveal [path] with it selected.
/// Returns false (so the caller can fall back) when `dbus-send` is missing or
/// the service isn't running / errors.
Future<bool> _linuxShowItem(String path) async {
  final uri = showItemsUri(path);
  try {
    final (exe, args) = hostCommand('dbus-send', [
      '--session',
      '--dest=org.freedesktop.FileManager1',
      '--type=method_call',
      '/org/freedesktop/FileManager1',
      'org.freedesktop.FileManager1.ShowItems',
      'array:string:$uri',
      'string:',
    ]);
    final result = await Process.run(exe, args);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}
