import 'package:cullimingo/core/files/host_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('outside a sandbox the command is unchanged', () {
    final (exe, args) = hostCommand('lsblk', ['-J'], sandboxed: false);
    expect(exe, 'lsblk');
    expect(args, ['-J']);
  });

  test('inside Flatpak the command goes through flatpak-spawn --host', () {
    final (exe, args) = hostCommand('udisksctl', [
      'mount',
      '-b',
      '/dev/sda1',
    ], sandboxed: true);
    expect(exe, 'flatpak-spawn');
    expect(args, ['--host', 'udisksctl', 'mount', '-b', '/dev/sda1']);
  });
}
