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

  // Part names carry their creation time (epoch seconds).
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final old = now - 2 * 3600;

  test('the pattern matches exactly what partPathFor produces', () {
    final made = p.basename(partPathFor(p.join(tmp.path, 'DSC_0001.NEF')));
    expect(kPartFileName.hasMatch(made), isTrue, reason: made);
    for (final name in [
      'photo.part',
      '.x.part',
      '.DSC_0001.NEF.0123456789ab.part', // no creation time
      '.DSC_0001.NEF.ABCDEF012345.$now.part', // upper-case hex
      '.DSC_0001.NEF.0123456789a.$now.part', // 11 hex
      'DSC_0001.NEF.0123456789ab.$now.part', // not hidden
      '.DSC_0001.NEF.0123456789ab.$now.part.bak',
    ]) {
      expect(kPartFileName.hasMatch(name), isFalse, reason: name);
    }
  });

  test('removes a stale part file, keeps everything else', () {
    final stale = touch('.DSC_0001.NEF.0123456789ab.$old.part');
    final keep = [
      touch('photo.part'),
      touch('.x.part'),
      touch('DSC_0001.NEF'),
      touch('.DSC_0002.NEF.abcdef012345.$old.part', 'sub'), // nested
    ];

    final removed = removeStalePartFilesSync([tmp.path]);

    expect(removed, 1);
    expect(stale.existsSync(), isFalse);
    for (final f in keep) {
      expect(f.existsSync(), isTrue, reason: f.path);
    }
  });

  test('keeps a fresh part file — a concurrent run may be writing it', () {
    final fresh = touch(p.basename(partPathFor(p.join(tmp.path, 'a.NEF'))))
      // A copy sets the part's mtime to the capture date before publishing,
      // and exFAT/FAT then report the same ancient ctime: neither may make a
      // live part file look abandoned.
      ..setLastModifiedSync(DateTime(2020));

    expect(removeStalePartFilesSync([tmp.path]), 0);
    expect(fresh.existsSync(), isTrue);
  });

  test('skips missing folders and never follows a directory symlink', () {
    final elsewhere = Directory.systemTemp.createTempSync('part_elsewhere');
    addTearDown(() => elsewhere.deleteSync(recursive: true));
    final outside = File(
      p.join(elsewhere.path, '.DSC_0001.NEF.0123456789ab.$old.part'),
    )..writeAsStringSync('x');
    Link(p.join(tmp.path, 'link')).createSync(elsewhere.path);

    final removed = removeStalePartFilesSync([
      p.join(tmp.path, 'missing'),
      tmp.path,
    ]);

    expect(removed, 0);
    expect(outside.existsSync(), isTrue);
  });

  test('the async wrapper never throws and runs off-isolate', () async {
    touch('.DSC_0001.NEF.0123456789ab.$old.part');
    expect(await removeStalePartFiles([p.join(tmp.path, 'missing')]), 0);
    expect(await removeStalePartFiles(const []), 0);
  });
}
