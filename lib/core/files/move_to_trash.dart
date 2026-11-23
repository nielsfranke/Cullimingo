import 'dart:convert';
import 'dart:io';

import 'package:cullimingo/core/files/host_command.dart';

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
/// per-volume trash dirs on removable drives); Windows sends them to the
/// Recycle Bin through PowerShell and .NET's `FileSystem.DeleteFile(…,
/// SendToRecycleBin)` (the Explorer API, so Restore works). Missing files are
/// skipped and counted as done. Batched [chunkSize] paths per process; when a
/// chunk fails, each of its files is retried alone so one stubborn file
/// doesn't take the rest of the chunk down with it. [onProgress] ticks after
/// each chunk. [os] and [sandboxed] (Flatpak, see [hostCommand]) default to
/// the real environment; tests override them.
Future<TrashResult> moveToTrash(
  List<String> paths, {
  TrashRunner? runProcess,
  String? os,
  bool? sandboxed,
  void Function(int processed, int total)? onProgress,
  int chunkSize = 50,
}) async {
  final run = runProcess ?? Process.run;
  final platform = os ?? Platform.operatingSystem;
  if (platform != 'macos' && platform != 'linux' && platform != 'windows') {
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

  // Under Flatpak, `gio trash` must run on the host: the sandbox's
  // XDG_DATA_HOME is remapped, so an in-sandbox trash would be app-private.
  (String, List<String>) command(List<String> chunk) => switch (platform) {
    'linux' => hostCommand(
      'gio',
      ['trash', '--', ...chunk],
      sandboxed: sandboxed,
    ),
    'windows' => (
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-EncodedCommand',
        windowsRecycleCommand(chunk),
      ],
    ),
    _ => ('osascript', ['-e', _finderDeleteScript(chunk)]),
  };

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
      error = switch (platform) {
        'linux' =>
          '`gio` was not found — install glib2 (gvfs) to enable Move to '
              'Trash.',
        'windows' => 'Could not run PowerShell: ${e.message}',
        _ => 'Could not run osascript: ${e.message}',
      };
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

/// The PowerShell script that recycles [chunk], as `-EncodedCommand` wants it
/// (base64 of UTF-16LE) — so no path ever goes through command-line quoting.
/// Paths are single-quoted PowerShell literals (`'` doubled; Windows names
/// can't contain `"`). Exits 1 when any file was refused, like `gio trash`.
/// Exposed for tests.
String windowsRecycleCommand(List<String> chunk) {
  final items = chunk
      .map((path) => "'${path.replaceAll("'", "''")}'")
      .join(',');
  final script =
      'Add-Type -AssemblyName Microsoft.VisualBasic; '
      r'$failed = $false; '
      'foreach (\$p in @($items)) { '
      r'try { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p, '
      "'OnlyErrorDialogs', 'SendToRecycleBin') } "
      r'catch { $failed = $true } }; '
      r'if ($failed) { exit 1 }';
  final utf16 = <int>[
    for (final unit in script.codeUnits) ...[unit & 0xff, unit >> 8],
  ];
  return base64.encode(utf16);
}

/// Decodes a [windowsRecycleCommand] back to its script. Exposed for tests.
String decodeWindowsCommand(String encoded) {
  final bytes = base64.decode(encoded);
  return String.fromCharCodes([
    for (var i = 0; i + 1 < bytes.length; i += 2) bytes[i] | bytes[i + 1] << 8,
  ]);
}
