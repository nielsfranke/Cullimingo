import 'dart:io';

import 'package:cullimingo/core/files/directory_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('lists the .exe aliases sorted by name, nothing else', () {
    final dir = Directory.systemTemp.createTempSync('cm_aliases');
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final name in ['wt.exe', 'mspaint.exe', 'Notes.txt', 'Code.EXE']) {
      File(p.join(dir.path, name)).writeAsStringSync('');
    }
    Directory(p.join(dir.path, 'Microsoft.Paint_8wekyb3d8bbwe')).createSync();

    expect(windowsAppAliases(dir: dir.path).map(p.basename), [
      'Code.EXE',
      'mspaint.exe',
      'wt.exe',
    ]);
  });

  test('a missing folder yields no aliases', () {
    expect(windowsAppAliases(dir: '/no/such/WindowsApps'), isEmpty);
  });
}
