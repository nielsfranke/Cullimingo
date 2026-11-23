import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:cullimingo/core/update/install_target.dart';
import 'package:cullimingo/core/update/update_manifest.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Why an update couldn't be downloaded or installed. The running app is
/// always left as it was.
enum UpdateFailure {
  /// No connection, a timeout or a server error.
  network('The update could not be downloaded — check the connection.'),

  /// The release has no usable `latest.json`.
  manifest('The release has no update information.'),

  /// The release has no package for this kind of installation.
  noPackage('The release has no update package for this installation.'),

  /// The download doesn't carry Cullimingo's signature (or doesn't match it).
  signature(
    'The downloaded update failed its signature check — not installed.',
  ),

  /// The disk is full or the download folder isn't writable.
  disk('The update could not be saved — is the disk full?'),

  /// Cullimingo may not replace itself where it is installed.
  permission('Cullimingo is not allowed to replace itself in its folder.');

  const UpdateFailure(this.message);

  /// A user-facing sentence.
  final String message;
}

/// An [UpdateFailure] as an exception.
class UpdateException implements Exception {
  /// Creates the exception.
  const UpdateException(this.failure, [this.detail]);

  /// What went wrong.
  final UpdateFailure failure;

  /// Technical detail for the log.
  final Object? detail;

  @override
  String toString() => 'UpdateException(${failure.name}: $detail)';
}

/// The folder updates are downloaded into (under the OS temp folder).
Future<Directory> updateWorkDir() async => Directory(
  p.join((await getTemporaryDirectory()).path, 'cullimingo-update'),
);

/// Removes a previous update's download — once installed (or abandoned) it
/// is dead weight. Call at startup; best effort, never throws.
Future<void> cleanUpUpdateDownloads() async {
  try {
    final dir = await updateWorkDir();
    // ignore: avoid_slow_async_io — once per start, off the hot path.
    if (await dir.exists()) await dir.delete(recursive: true);
  } on Object {
    // A setup still running from it on Windows: next start.
  }
}

/// The `latest.json` of release `v<version>`.
Uri updateManifestUrl(String version) => Uri.parse(
  'https://github.com/nielsfranke/Cullimingo/releases/download/'
  'v$version/latest.json',
);

/// A verified package on disk, ready for [installAndRelaunch].
class StagedUpdate {
  /// Creates a staged update.
  const StagedUpdate({
    required this.version,
    required this.file,
    required this.target,
  });

  /// The version it installs.
  final String version;

  /// The downloaded, verified package.
  final File file;

  /// What it replaces.
  final InstallTarget target;
}

/// Downloads release [version]'s package for [target] into [workDir] and
/// verifies it: the manifest must name exactly [version], and the file must
/// match the manifest's size and SHA-256 and carry a valid signature by
/// [publicKey]. [onProgress] reports bytes received of the total. Throws an
/// [UpdateException]; on success nothing is installed yet.
Future<StagedUpdate> downloadUpdate({
  required String version,
  required InstallTarget target,
  required Directory workDir,
  void Function(int received, int total)? onProgress,
  Uri? manifestUrl,
  String publicKey = kUpdatePublicKey,
  HttpClient? client,
  @visibleForTesting bool allowInsecureForTests = false,
}) async {
  final http = client ?? HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);
  try {
    final UpdateManifest manifest;
    try {
      final text = await _getText(
        http,
        manifestUrl ?? updateManifestUrl(version),
      );
      manifest = UpdateManifest.parse(
        text,
        allowHttp: allowInsecureForTests,
      );
    } on UpdateException {
      rethrow;
    } on FormatException catch (e) {
      throw UpdateException(UpdateFailure.manifest, e);
    }
    if (manifest.version != version) {
      throw UpdateException(
        UpdateFailure.manifest,
        'manifest is for ${manifest.version}, expected $version',
      );
    }
    final package = manifest.packages[target.manifestKey];
    if (package == null) {
      throw UpdateException(UpdateFailure.noPackage, target.manifestKey);
    }
    // Check the signature over the manifest's claims before downloading:
    // a forged entry is refused without fetching anything.
    if (!manifest.verifies(package, publicKey: publicKey)) {
      throw const UpdateException(UpdateFailure.signature, 'manifest entry');
    }

    final File file;
    try {
      if (workDir.existsSync()) workDir.deleteSync(recursive: true);
      workDir.createSync(recursive: true);
      file = File(p.join(workDir.path, p.basename(package.name)));
    } on FileSystemException catch (e) {
      throw UpdateException(UpdateFailure.disk, e);
    }
    await _download(http, package, file, onProgress);

    final digest = await Isolate.run(
      () async =>
          (await sha256.bind(File(file.path).openRead()).first).toString(),
    );
    if (file.lengthSync() != package.size || digest != package.sha256) {
      throw UpdateException(
        UpdateFailure.signature,
        'download is $digest (${file.lengthSync()} B), '
        'signed ${package.sha256} (${package.size} B)',
      );
    }
    return StagedUpdate(version: version, file: file, target: target);
  } finally {
    if (client == null) http.close(force: true);
  }
}

Future<String> _getText(HttpClient http, Uri url) async {
  try {
    final request = await http.getUrl(url);
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode == 404) {
      await response.drain<void>();
      throw UpdateException(UpdateFailure.manifest, '404 $url');
    }
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw UpdateException(
        UpdateFailure.network,
        '${response.statusCode} $url',
      );
    }
    return await response.transform(utf8.decoder).join();
  } on UpdateException {
    rethrow;
  } on Object catch (e) {
    throw UpdateException(UpdateFailure.network, e);
  }
}

Future<void> _download(
  HttpClient http,
  UpdatePackage package,
  File file,
  void Function(int received, int total)? onProgress,
) async {
  IOSink? sink;
  try {
    final request = await http.getUrl(package.url);
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw UpdateException(
        UpdateFailure.network,
        '${response.statusCode} ${package.url}',
      );
    }
    sink = file.openWrite();
    var received = 0;
    await for (final chunk in response.timeout(const Duration(seconds: 60))) {
      sink.add(chunk);
      received += chunk.length;
      if (received > package.size) {
        throw const UpdateException(
          UpdateFailure.signature,
          'download too large',
        );
      }
      onProgress?.call(received, package.size);
    }
    await sink.close();
    sink = null;
  } on UpdateException {
    rethrow;
  } on FileSystemException catch (e) {
    throw UpdateException(UpdateFailure.disk, e);
  } on Object catch (e) {
    throw UpdateException(UpdateFailure.network, e);
  } finally {
    await sink?.close();
  }
}

/// Whether this process may replace [target] — checked before downloading,
/// so the user isn't sent through a download that can't be installed. The
/// MSI asks Windows for administrator rights itself, so it always may.
bool canReplace(InstallTarget target) {
  final String dir;
  switch (target.method) {
    case InstallMethod.windowsMsi:
      return true;
    case InstallMethod.windowsNsis:
      dir = target.path;
    case InstallMethod.macApp:
    case InstallMethod.linuxAppImage:
      dir = p.dirname(target.path);
  }
  final probe = File(p.join(dir, '.cullimingo-update-probe-$pid'));
  try {
    probe
      ..writeAsStringSync('')
      ..deleteSync();
    return true;
  } on FileSystemException {
    return false;
  }
}

/// Starts the installation of [update] in a helper that outlives this
/// process: it waits for Cullimingo ([processId]) to exit, installs, and
/// starts the new version. The caller must quit the app right after.
/// Throws an [UpdateException] when the helper can't be started; then the
/// running app is untouched.
Future<void> installAndRelaunch(
  StagedUpdate update, {
  int? processId,
}) async {
  final me = processId ?? pid;
  final t = update.target;
  final pkg = update.file.path;
  try {
    switch (t.method) {
      case InstallMethod.windowsNsis:
      case InstallMethod.windowsMsi:
        // Not ProcessStartMode.detached: Dart starts that with
        // DETACHED_PROCESS, and a console-less powershell.exe then exits
        // with code 0 within ~300 ms without running its command (measured
        // on Windows 11, 3 of 3 updates lost). A normal child survives this
        // app's exit(0) all the same and shows no window; with stdin ignored
        // (-InputFormat None) the pipes closing with us don't matter.
        await Process.start('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-InputFormat',
          'None',
          '-WindowStyle',
          'Hidden',
          '-EncodedCommand',
          encodePowerShell(windowsInstallScript(update, processId: me)),
        ]);
      case InstallMethod.macApp:
        await Process.start(
          '/bin/sh',
          ['-c', kMacInstallScript, 'cullimingo-update', '$me', pkg, t.path],
          mode: ProcessStartMode.detached,
        );
      case InstallMethod.linuxAppImage:
        // Linux lets a running file be replaced: swap it in place now (same
        // folder, so the rename is atomic), then start the new one.
        final staged = File(
          p.join(p.dirname(t.path), '.Cullimingo.AppImage.new'),
        );
        await update.file.copy(staged.path);
        await Process.run('chmod', ['755', staged.path]);
        await staged.rename(t.path);
        // Start the new one once this one has gone (one catalog writer).
        await Process.start(
          '/bin/sh',
          [
            '-c',
            r'while kill -0 "$1" 2>/dev/null; do sleep 0.2; done; exec "$2"',
            'cullimingo-update',
            '$me',
            t.path,
          ],
          mode: ProcessStartMode.detached,
        );
    }
  } on Object catch (e) {
    throw UpdateException(UpdateFailure.permission, e);
  }
}

/// The PowerShell the Windows helper runs: wait for Cullimingo to exit, run
/// the setup silently (NSIS, per user) or msiexec /passive with one UAC
/// prompt (MSI), then start Cullimingo again — the new one, or the old one
/// if the user declined the prompt. Single-quoted literals, `'` doubled.
/// Exposed for tests.
String windowsInstallScript(StagedUpdate update, {required int processId}) {
  String q(String s) => "'${s.replaceAll("'", "''")}'";
  final dir = update.target.path;
  final exe = '$dir\\cullimingo.exe';
  final install = update.target.method == InstallMethod.windowsNsis
      // NSIS wants /D last and unquoted, spaces included.
      ? 'Start-Process -FilePath ${q(update.file.path)} '
            "-ArgumentList '/S', ${q('/D=$dir')} -Wait"
      : 'Start-Process -FilePath msiexec.exe -ArgumentList '
            "'/i', ${q('"${update.file.path}"')}, '/passive', '/norestart' "
            '-Verb RunAs -Wait';
  return 'Wait-Process -Id $processId -ErrorAction SilentlyContinue; '
      'try { $install } catch { }; '
      'Start-Process -FilePath ${q(exe)}';
}

/// [script] as `-EncodedCommand` wants it: base64 of UTF-16LE.
String encodePowerShell(String script) => base64.encode([
  for (final unit in script.codeUnits) ...[unit & 0xff, unit >> 8],
]);

/// The macOS helper (`sh -c`, args: pid, dmg, app): wait for Cullimingo to
/// exit, mount the DMG, copy the new bundle beside the old one, swap them
/// (the old one comes back if the swap fails), unmount, start the app.
/// Downloads made by the app itself carry no quarantine flag, and the
/// bundle inside the DMG is signed and notarized.
const String kMacInstallScript = r'''
pid="$1"; dmg="$2"; app="$3"
while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
mnt="$(mktemp -d /tmp/cullimingo-update.XXXXXX)"
if hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$mnt" "$dmg" >/dev/null 2>&1; then
  if [ -d "$mnt/Cullimingo.app" ] && rm -rf "$app.new" && ditto "$mnt/Cullimingo.app" "$app.new"; then
    rm -rf "$app.old"
    if mv "$app" "$app.old"; then
      if mv "$app.new" "$app"; then rm -rf "$app.old"; else mv "$app.old" "$app"; fi
    fi
    rm -rf "$app.new"
  fi
  hdiutil detach "$mnt" -quiet || hdiutil detach "$mnt" -force -quiet
fi
rmdir "$mnt" 2>/dev/null
open "$app"
''';
