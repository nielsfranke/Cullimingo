import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('cullimingo/dialogs');

/// Picks a directory. On macOS this uses a native `NSOpenPanel` that allows
/// **creating new folders** and opens at [initialDirectory] (file_selector's
/// directory picker disables folder creation). Falls back to file_selector on
/// other platforms or if the native call isn't available.
Future<String?> pickDirectory({String? initialDirectory}) async {
  if (Platform.isMacOS) {
    try {
      return await _channel.invokeMethod<String>('pickDirectory', {
        'initialDirectory': initialDirectory,
      });
    } on Object {
      // Fall through to the plugin implementation.
    }
  }
  return getDirectoryPath(initialDirectory: initialDirectory);
}

/// Restricts the macOS app picker to application bundles.
const XTypeGroup macApplicationTypeGroup = XTypeGroup(
  label: 'Applications',
  uniformTypeIdentifiers: ['com.apple.application-bundle'],
);

/// Picks an application to hand photos to ("Send to" editors). On macOS an app
/// is an `.app` bundle. It is a directory on disk, but `NSOpenPanel` treats
/// bundles as packages, i.e. as *files*. A folder-only panel greys every app
/// out (#29), so this uses a file panel filtered to application bundles,
/// opened at `/Applications`. On Windows the panel is filtered to `.exe` and
/// opens in Program Files (Store apps can't be picked there — see
/// `windowsAppAliases`); on Linux an app is a plain executable, picked as a
/// file.
Future<String?> pickApplication() async {
  final file = Platform.isMacOS
      ? await openFile(
          acceptedTypeGroups: const [macApplicationTypeGroup],
          initialDirectory: '/Applications',
          confirmButtonText: 'Add',
        )
      : Platform.isWindows
      ? await openFile(
          acceptedTypeGroups: const [
            XTypeGroup(label: 'Programs', extensions: ['exe']),
          ],
          initialDirectory: Platform.environment['ProgramFiles'],
          confirmButtonText: 'Add',
        )
      : await openFile();
  return file?.path;
}

/// The Store apps that can be launched with files, as their app execution
/// aliases (`%LOCALAPPDATA%\Microsoft\WindowsApps\mspaint.exe`, …), sorted by
/// name. Windows' file dialog refuses these alias files ("The file cannot be
/// accessed by the system"), yet starting one with the photos as arguments
/// works like any `.exe` — so the settings offer them from this list instead.
/// Empty off Windows or without the folder. [dir] overrides it (tests).
List<String> windowsAppAliases({String? dir}) {
  final root =
      dir ??
      (Platform.isWindows && Platform.environment['LOCALAPPDATA'] != null
          ? '${Platform.environment['LOCALAPPDATA']}\\Microsoft\\WindowsApps'
          : null);
  if (root == null) return const [];
  try {
    return [
      for (final e in Directory(root).listSync(followLinks: false))
        if (e.path.toLowerCase().endsWith('.exe')) e.path,
    ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  } on FileSystemException {
    return const [];
  }
}

/// A readable name for a Store app alias: the app's name where it's known
/// (`mspaint.exe` → "Paint"), else the alias itself.
String windowsAppAliasLabel(String aliasPath) {
  final name = aliasPath.split(RegExp(r'[\\/]')).last;
  final stem = name.toLowerCase().endsWith('.exe')
      ? name.substring(0, name.length - 4)
      : name;
  return const {
        'mspaint': 'Paint',
        'wt': 'Windows Terminal',
        'notepad': 'Notepad',
        'mediaplayer': 'Media Player',
      }[stem.toLowerCase()] ??
      stem;
}
