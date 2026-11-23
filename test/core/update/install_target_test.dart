import 'dart:ffi';
import 'dart:io';

import 'package:cullimingo/core/update/install_target.dart';
import 'package:cullimingo/core/update/update_installer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  InstallTarget? detect({
    required String os,
    required String exe,
    Map<String, String> env = const {},
    Abi abi = Abi.linuxX64,
    Set<String> files = const {},
    bool release = true,
  }) => detectInstallTarget(
    executable: exe,
    environment: env,
    os: os,
    abi: abi,
    releaseMode: release,
    fileExists: files.contains,
  );

  test('debug and profile builds never update themselves', () {
    expect(
      detect(
        os: 'linux',
        exe: '/x/cullimingo',
        env: {'APPIMAGE': '/x/C.AppImage'},
        release: false,
      ),
      isNull,
    );
  });

  test('Windows: NSIS by its uninstaller, MSI by Program Files, else none', () {
    const nsisDir = r'C:\Users\me\AppData\Local\Programs\Cullimingo';
    final nsis = detect(
      os: 'windows',
      exe: '$nsisDir\\cullimingo.exe',
      files: {'$nsisDir\\uninstall.exe'},
    )!;
    expect(nsis.method, InstallMethod.windowsNsis);
    expect(nsis.path, nsisDir);
    expect(nsis.manifestKey, 'windows-x64-nsis');

    final msi = detect(
      os: 'windows',
      exe: r'C:\Program Files\Cullimingo\cullimingo.exe',
      env: {'ProgramFiles': r'C:\Program Files'},
    )!;
    expect(msi.method, InstallMethod.windowsMsi);
    expect(msi.manifestKey, 'windows-x64-msi');

    expect(
      detect(
        os: 'windows',
        exe: r'D:\Tools\Cullimingo\cullimingo.exe',
        env: {'ProgramFiles': r'C:\Program Files'},
      ),
      isNull,
      reason: 'the portable zip',
    );
  });

  test('macOS: the .app bundle, keyed by architecture', () {
    const exe = '/Applications/Cullimingo.app/Contents/MacOS/cullimingo';
    final arm = detect(os: 'macos', exe: exe, abi: Abi.macosArm64)!;
    expect(arm.path, '/Applications/Cullimingo.app');
    expect(arm.manifestKey, 'macos-arm64-dmg');
    expect(
      detect(os: 'macos', exe: exe, abi: Abi.macosX64)!.manifestKey,
      'macos-x64-dmg',
    );
    expect(detect(os: 'macos', exe: '/usr/local/bin/cullimingo'), isNull);
  });

  test('Linux: only an x64 AppImage outside Flatpak', () {
    const env = {'APPIMAGE': '/home/me/Apps/Cullimingo-x86_64.AppImage'};
    final t = detect(os: 'linux', exe: '/tmp/.mount_x/cullimingo', env: env)!;
    expect(t.method, InstallMethod.linuxAppImage);
    expect(t.path, env['APPIMAGE']);
    expect(detect(os: 'linux', exe: '/app/bin/cullimingo'), isNull);
    expect(
      detect(
        os: 'linux',
        exe: '/app/cullimingo',
        env: {...env, 'FLATPAK_ID': 'io.github.nielsfranke.Cullimingo'},
      ),
      isNull,
    );
  });

  test('the Windows helper waits, installs silently and relaunches', () {
    String script(InstallMethod method) => windowsInstallScript(
      StagedUpdate(
        version: '1.14.0',
        file: File(r"C:\Users\o'neil\Temp\Cullimingo_1.14.0_x64-setup.exe"),
        target: InstallTarget(
          method: method,
          path: r"C:\Users\o'neil\AppData\Local\Programs\Cullimingo",
          manifestKey: 'x',
        ),
      ),
      processId: 4242,
    );
    final nsis = script(InstallMethod.windowsNsis);
    expect(nsis, startsWith('Wait-Process -Id 4242'));
    expect(nsis, contains(r"'/S', '/D=C:\Users\o''neil\AppData"));
    expect(nsis, endsWith("cullimingo.exe'"));
    final msi = script(InstallMethod.windowsMsi);
    expect(msi, contains('msiexec.exe'));
    expect(msi, contains("'/passive'"));
    expect(msi, contains('-Verb RunAs'));
  });
}
