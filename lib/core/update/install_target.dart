import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// How this copy of Cullimingo was installed — which decides whether and how
/// it can replace itself with a newer release.
enum InstallMethod {
  /// Per-user NSIS setup (`%LOCALAPPDATA%\Programs\Cullimingo`): rerun the
  /// new setup silently over it.
  windowsNsis,

  /// Per-machine MSI (`Program Files`): `msiexec /passive`, one UAC prompt.
  windowsMsi,

  /// A `Cullimingo.app` bundle (from the DMG): replace the bundle.
  macApp,

  /// A Linux AppImage: replace the file.
  linuxAppImage,
}

/// Where and how this copy updates itself, and which `latest.json` package it
/// needs.
class InstallTarget {
  /// Creates a target.
  const InstallTarget({
    required this.method,
    required this.path,
    required this.manifestKey,
  });

  /// The install method.
  final InstallMethod method;

  /// What gets replaced: the install folder (Windows), the `.app` bundle
  /// (macOS) or the AppImage file (Linux).
  final String path;

  /// The package key in `latest.json` (see `tool/update_manifest.py`).
  final String manifestKey;

  @override
  String toString() => 'InstallTarget($method, $path, $manifestKey)';
}

/// This copy's [InstallTarget], or null when it can't update itself: a debug
/// or profile build, the Windows portable zip, a Flatpak (updated by
/// `flatpak update`), a Linux bundle that isn't an AppImage, or a layout we
/// don't recognise. Then the update notice only links to the release page.
/// Everything is injectable for tests.
InstallTarget? detectInstallTarget({
  String? executable,
  Map<String, String>? environment,
  String? os,
  Abi? abi,
  bool? releaseMode,
  bool Function(String path)? fileExists,
}) {
  if (!(releaseMode ?? kReleaseMode)) return null;
  final exe = executable ?? Platform.resolvedExecutable;
  final env = environment ?? Platform.environment;
  final exists = fileExists ?? (String path) => File(path).existsSync();
  switch (os ?? Platform.operatingSystem) {
    case 'windows':
      final ctx = p.Context(style: p.Style.windows);
      final dir = ctx.dirname(exe);
      if (exists(ctx.join(dir, 'uninstall.exe'))) {
        return InstallTarget(
          method: InstallMethod.windowsNsis,
          path: dir,
          manifestKey: 'windows-x64-nsis',
        );
      }
      final programFiles = env['ProgramFiles'] ?? env['PROGRAMFILES'];
      if (programFiles != null &&
          ctx.isWithin(programFiles.toLowerCase(), dir.toLowerCase())) {
        return InstallTarget(
          method: InstallMethod.windowsMsi,
          path: dir,
          manifestKey: 'windows-x64-msi',
        );
      }
      return null; // the portable zip
    case 'macos':
      // …/Cullimingo.app/Contents/MacOS/cullimingo
      final ctx = p.Context(style: p.Style.posix);
      final app = ctx.dirname(ctx.dirname(ctx.dirname(exe)));
      if (!app.endsWith('.app')) return null;
      final arm = (abi ?? Abi.current()) == Abi.macosArm64;
      return InstallTarget(
        method: InstallMethod.macApp,
        path: app,
        manifestKey: arm ? 'macos-arm64-dmg' : 'macos-x64-dmg',
      );
    case 'linux':
      final appImage = env['APPIMAGE'];
      if (env.containsKey('FLATPAK_ID') ||
          appImage == null ||
          appImage.isEmpty ||
          (abi ?? Abi.current()) != Abi.linuxX64) {
        return null;
      }
      return InstallTarget(
        method: InstallMethod.linuxAppImage,
        path: appImage,
        manifestKey: 'linux-x64-appimage',
      );
  }
  return null;
}
