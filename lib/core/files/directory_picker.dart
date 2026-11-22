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
/// opened at `/Applications`. Elsewhere an app is a plain executable, picked as
/// a file.
Future<String?> pickApplication() async {
  final file = Platform.isMacOS
      ? await openFile(
          acceptedTypeGroups: const [macApplicationTypeGroup],
          initialDirectory: '/Applications',
          confirmButtonText: 'Add',
        )
      : await openFile();
  return file?.path;
}
