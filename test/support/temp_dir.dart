import 'dart:io';

/// Deletes a test's temp [dir]. A widget test whose dialog saves settings in
/// the background (unawaited, as the app does) can still hold `settings.json`
/// open when tearDown runs; macOS and Linux delete an open file, Windows
/// refuses (errno 32). There it retries briefly and then leaves the temp
/// folder for the OS to clean, rather than failing an otherwise green test.
void deleteTempDir(Directory dir) {
  for (var attempt = 0; ; attempt++) {
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      if (!Platform.isWindows) rethrow;
      if (attempt == 9) return;
      sleep(const Duration(milliseconds: 50));
    }
  }
}
