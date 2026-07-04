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

/// Picks an application to hand photos to ("Send to" editors). On macOS an app
/// is an `.app` *bundle* (a directory), so the folder picker — opened at
/// `/Applications` — is the right tool. Elsewhere an app is a plain executable,
/// picked as a file.
Future<String?> pickApplication() async {
  if (Platform.isMacOS) {
    return pickDirectory(initialDirectory: '/Applications');
  }
  final file = await openFile();
  return file?.path;
}
