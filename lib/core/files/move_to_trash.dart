import 'dart:io';

/// Runs an external process — injectable so tests fake the OS trash tools.
typedef TrashRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Outcome of a [moveToTrash] run.
class TrashResult {
  /// Creates a result.
  const TrashResult({
    required this.trashed,
    required this.failed,
    this.error,
  });

  /// Paths now gone from their folder — freshly trashed, or already missing
  /// (nothing left to trash counts as done).
  final int trashed;

  /// Paths that still exist because the OS refused to trash them.
  final List<String> failed;

  /// A run-level problem (unsupported platform, `gio` missing, …), or null.
  final String? error;
}

/// Moves [paths] to the OS trash — never a hard delete, so the user can always
/// put files back. macOS goes through Finder (`osascript`), which records the
/// origin for Put Back; Linux uses `gio trash` (freedesktop spec, handles
/// per-volume trash dirs on removable drives). Missing files are skipped and
/// counted as done. Batched [chunkSize] paths per process; when a chunk fails,
/// each of its files is retried alone so one stubborn file doesn't take the
/// rest of the chunk down with it. [onProgress] ticks after each chunk.
Future<TrashResult> moveToTrash(
  List<String> paths, {
  TrashRunner? runProcess,
  String? os,
  void Function(int processed, int total)? onProgress,
  int chunkSize = 50,
}) async {
  final run = runProcess ?? Process.run;
  final platform = os ?? Platform.operatingSystem;
  if (platform != 'macos' && platform != 'linux') {
    return TrashResult(
      trashed: 0,
      failed: List.of(paths),
      error: 'Move to Trash is not supported on $platform yet.',
    );
  }

  // Missing files are already gone — their goal state is met.
  final pending = <String>[];
  for (final path in paths) {
    // Async exists() so a check over a cloud-synced folder never stalls the UI
    // isolate (matches transfer_service.dart).
    // ignore: avoid_slow_async_io
    if (await File(path).exists()) pending.add(path);
  }

  (String, List<String>) command(List<String> chunk) => platform == 'linux'
      ? ('gio', ['trash', '--', ...chunk])
      : ('osascript', ['-e', _finderDeleteScript(chunk)]);

  final failed = <String>[];
  String? error;
  var processed = paths.length - pending.length;
  onProgress?.call(processed, paths.length);

  for (var i = 0; i < pending.length; i += chunkSize) {
    final chunk = pending.sublist(
      i,
      i + chunkSize > pending.length ? pending.length : i + chunkSize,
    );
    try {
      final (exe, args) = command(chunk);
      final result = await run(exe, args);
      if (result.exitCode != 0) {
        // The chunk had at least one refusal; retry one-by-one to attribute
        // the failures to the actual files. `gio trash` keeps going after a
        // refusal, so part of the chunk may already be in the trash — a
        // now-missing file is a success, not a "no such file" failure.
        for (final path in chunk) {
          // Async on purpose — this can run on the UI isolate (see above).
          // ignore: avoid_slow_async_io
          if (!await File(path).exists()) continue;
          final (exe1, args1) = command([path]);
          final single = await run(exe1, args1);
          if (single.exitCode != 0) failed.add(path);
        }
      }
    } on ProcessException catch (e) {
      // The tool itself is unavailable — no point trying further chunks.
      error = platform == 'linux'
          ? '`gio` was not found — install glib2 (gvfs) to enable Move to '
                'Trash.'
          : 'Could not run osascript: ${e.message}';
      failed.addAll(pending.sublist(i));
      break;
    }
    processed += chunk.length;
    onProgress?.call(processed, paths.length);
  }

  return TrashResult(
    trashed: paths.length - failed.length,
    failed: failed,
    error: error,
  );
}

/// One Finder `delete` for the whole [chunk] — a single Apple event, so a
/// batch doesn't open a Finder round-trip per file.
String _finderDeleteScript(List<String> chunk) {
  final items = chunk
      .map((path) => 'POSIX file "${_escapeAppleScript(path)}"')
      .join(', ');
  return 'tell application "Finder" to delete {$items}';
}

String _escapeAppleScript(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
