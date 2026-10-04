import 'dart:io';

import 'package:cullimingo/core/files/part_cleanup.dart';
import 'package:cullimingo/core/files/verified_copy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('part_cleanup'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File touch(String name, [String dir = '']) =>
      File(p.join(tmp.path, dir, name))
        ..createSync(recursive: true)
        ..writeAsStringSync('x');

  // ctime can't be set from a test; "two hours from now" ages every file.
  final later = DateTime.now().add(const Duration(hours: 2));

  test('the pattern matches exactly what partPathFor produces', () {
    final made = p.basename(partPathFor(p.join(tmp.path, 'DSC_0001.NEF')));
    expect(kPartFileName.hasMatch(made), isTrue);
    for (final name in [
      'photo.part',
      '.x.part',
      '.DSC_0001.NEF.ABCDEF012345.part', // upper-case hex
      '.DSC_0001.NEF.0123456789a.part', // 11 hex
      'DSC_0001.NEF.0123456789ab.part', // not hidden
      '.DSC_0001.NEF.0123456789ab.part.bak',
    ]) {
      expect(kPartFileName.hasMatch(name), isFalse, reason: name);
    }
  });

  test('removes a stale part file, keeps everything else', () {
    final stale = touch('.DSC_0001.NEF.0123456789ab.part');
    final keep = [
      touch('photo.part'),
      touch('.x.part'),
      touch('DSC_0001.NEF'),
      touch('.DSC_0002.NEF.abcdef012345.part', 'sub'), // not listed: nested
    ];

    final removed = removeStalePartFilesSync([tmp.path], now: later);

    expect(removed, 1);
    expect(stale.existsSync(), isFalse);
    for (final f in keep) {
      expect(f.existsSync(), isTrue, reason: f.path);
    }
  });

  test('keeps a fresh part file — a concurrent run may be writing it', () {
    final fresh = touch('.DSC_0001.NEF.0123456789ab.part')
      // A copy sets the part's mtime to the capture date before publishing;
      // that must not make it look abandoned.
      ..setLastModifiedSync(DateTime(2020));

    expect(removeStalePartFilesSync([tmp.path]), 0);
    expect(fresh.existsSync(), isTrue);
  });

  test('skips missing folders and never follows a directory symlink', () {
    final elsewhere = Directory.systemTemp.createTempSync('part_elsewhere');
    addTearDown(() => elsewhere.deleteSync(recursive: true));
    final outside = File(
      p.join(elsewhere.path, '.DSC_0001.NEF.0123456789ab.part'),
    )..writeAsStringSync('x');
    Link(p.join(tmp.path, 'link')).createSync(elsewhere.path);

    final removed = removeStalePartFilesSync([
      p.join(tmp.path, 'missing'),
      tmp.path,
    ], now: later);

    expect(removed, 0);
    expect(outside.existsSync(), isTrue);
  });

  test('the async wrapper never throws and runs off-isolate', () async {
    touch('.DSC_0001.NEF.0123456789ab.part');
    expect(await removeStalePartFiles([p.join(tmp.path, 'missing')]), 0);
    expect(await removeStalePartFiles(const []), 0);
  });
}
