import 'dart:io';

import 'package:cullimingo/core/files/supported_files.dart';
import 'package:cullimingo/core/files/verified_copy.dart';
import 'package:cullimingo/features/library/data/folder_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('verify_copy'));
  tearDown(() async => tmp.delete(recursive: true));

  File src(String name, String content) =>
      File(p.join(tmp.path, name))..writeAsStringSync(content);

  test('copies and verifies, creating destination folders', () async {
    final s = src('a.txt', 'hello raw');
    final dest = p.join(tmp.path, 'out', '2026', 'a.txt');

    final r = await verifiedCopy(source: s.path, destinations: [dest]);

    expect(r.outcome, CopyOutcome.copied);
    expect(r.ok, isTrue);
    expect(File(dest).readAsStringSync(), 'hello raw');
  });

  test("keeps the source's mtime on the copy", () async {
    final s = src('m.txt', 'shot');
    final shotAt = DateTime(2024, 5, 4, 12);
    s.setLastModifiedSync(shotAt);
    final dest = p.join(tmp.path, 'out', 'm.txt');

    await verifiedCopy(source: s.path, destinations: [dest]);

    expect(File(dest).lastModifiedSync(), shotAt);
  });

  test(
    'an unwritable destination fails the copy instead of escaping',
    () async {
      final s = src('w.txt', 'data');
      final locked = Directory(p.join(tmp.path, 'locked'))..createSync();
      Process.runSync('chmod', ['555', locked.path]);
      addTearDown(() => Process.runSync('chmod', ['755', locked.path]));
      // Root ignores the mode bits (some CI containers) — nothing to test then.
      try {
        File(p.join(locked.path, 'probe')).writeAsStringSync('x');
        markTestSkipped('running with permission overrides (root)');
        return;
      } on FileSystemException {
        // Expected: the folder really is read-only.
      }

      final r = await verifiedCopy(
        source: s.path,
        destinations: [p.join(locked.path, 'w.txt')],
      );

      expect(r.outcome, CopyOutcome.error);
    },
    testOn: '!windows',
  );

  test(
    'a source that changes during the copy is not reported copied',
    () async {
      // Big enough that the copy yields many times; the source keeps growing
      // meanwhile, like a file a tether or sync tool is still writing.
      final s = File(p.join(tmp.path, 'growing.raw'))
        ..writeAsBytesSync(List.filled(32 * 1024 * 1024, 1));
      final dest = p.join(tmp.path, 'out', 'growing.raw');

      var copying = true;
      final copy = verifiedCopy(
        source: s.path,
        destinations: [dest],
      ).whenComplete(() => copying = false);
      while (copying) {
        s.writeAsBytesSync(const [2], mode: FileMode.append);
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      final r = await copy;

      expect(r.outcome, CopyOutcome.sourceChanged);
      expect(r.ok, isFalse);
      expect(File(dest).existsSync(), isFalse, reason: 'stale copy kept');
    },
  );

  test('copies to two destinations (dual-dest backup)', () async {
    final s = src('b.txt', 'data');
    final d1 = p.join(tmp.path, 'main', 'b.txt');
    final d2 = p.join(tmp.path, 'backup', 'b.txt');

    final r = await verifiedCopy(source: s.path, destinations: [d1, d2]);

    expect(r.outcome, CopyOutcome.copied);
    expect(File(d1).readAsStringSync(), 'data');
    expect(File(d2).readAsStringSync(), 'data');
  });

  test('skips an identical existing copy (resume / re-run)', () async {
    final s = src('c.txt', 'same');
    final dest = p.join(tmp.path, 'out', 'c.txt');
    await verifiedCopy(source: s.path, destinations: [dest]);

    final again = await verifiedCopy(source: s.path, destinations: [dest]);

    expect(again.outcome, CopyOutcome.skipped);
    expect(again.ok, isTrue);
  });

  test(
    'never overwrites a differing destination, reports a conflict',
    () async {
      final s = src('d.txt', 'new content');
      final dest = p.join(tmp.path, 'out', 'd.txt');
      File(dest)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('old content');

      final r = await verifiedCopy(source: s.path, destinations: [dest]);

      expect(r.outcome, CopyOutcome.conflict);
      expect(r.ok, isFalse);
      // The existing file is left untouched.
      expect(File(dest).readAsStringSync(), 'old content');
    },
  );

  test('verify:false still copies the bytes correctly', () async {
    final s = src('e.txt', 'no-verify content');
    final dest = p.join(tmp.path, 'out', 'e.txt');

    final r = await verifiedCopy(
      source: s.path,
      destinations: [dest],
      verify: false,
    );

    expect(r.outcome, CopyOutcome.copied);
    expect(File(dest).readAsStringSync(), 'no-verify content');
  });

  test('reports a missing source', () async {
    final r = await verifiedCopy(
      source: p.join(tmp.path, 'nope.txt'),
      destinations: [p.join(tmp.path, 'out.txt')],
    );
    expect(r.outcome, CopyOutcome.sourceMissing);
    expect(r.ok, isFalse);
  });

  group('quiet period (#9)', () {
    const quiet = Duration(seconds: 3);

    test('holds back a file modified moments ago, untouched', () async {
      final s = src('busy.arw', 'half written');
      final dest = p.join(tmp.path, 'out', 'busy.arw');

      final r = await verifiedCopy(
        source: s.path,
        destinations: [dest],
        quietPeriod: quiet,
      );

      expect(r.outcome, CopyOutcome.sourceBusy);
      expect(r.ok, isFalse);
      expect(r.message, contains('still being written'));
      expect(Directory(p.join(tmp.path, 'out')).existsSync(), isFalse);
    });

    test('copies a file that has settled', () async {
      final s = src('done.arw', 'complete')
        ..setLastModifiedSync(
          DateTime.now().subtract(const Duration(seconds: 10)),
        );

      final r = await verifiedCopy(
        source: s.path,
        destinations: [p.join(tmp.path, 'out', 'done.arw')],
        quietPeriod: quiet,
      );

      expect(r.outcome, CopyOutcome.copied);
    });

    test("a camera clock set in the future doesn't block forever", () async {
      final s = src('future.arw', 'shot')
        ..setLastModifiedSync(DateTime.now().add(const Duration(hours: 2)));

      final r = await verifiedCopy(
        source: s.path,
        destinations: [p.join(tmp.path, 'out', 'future.arw')],
        quietPeriod: quiet,
      );

      expect(r.outcome, CopyOutcome.copied);
    });
  });

  group('part file + publish (#9)', () {
    test('nothing appears under the final name until verified', () async {
      final s = File(p.join(tmp.path, 'big.raw'))
        ..writeAsBytesSync(List.filled(32 * 1024 * 1024, 7));
      final dest = p.join(tmp.path, 'out', 'big.raw');

      var copying = true;
      var sawPartial = false;
      final copy = verifiedCopy(
        source: s.path,
        destinations: [dest],
      ).whenComplete(() => copying = false);
      while (copying) {
        final f = File(dest);
        if (f.existsSync() && f.lengthSync() < 32 * 1024 * 1024) {
          sawPartial = true;
        }
        await Future<void>.delayed(Duration.zero);
      }
      final r = await copy;

      expect(r.outcome, CopyOutcome.copied);
      expect(sawPartial, isFalse, reason: 'half a photo under the real name');
      expect(File(dest).lengthSync(), 32 * 1024 * 1024);
    });

    test('leaves no part files behind after a copy', () async {
      final s = src('a.arw', 'photo');
      final out = Directory(p.join(tmp.path, 'out'));

      await verifiedCopy(
        source: s.path,
        destinations: [p.join(out.path, 'a.arw')],
      );

      expect(out.listSync().map((e) => p.basename(e.path)), ['a.arw']);
    });

    test(
      'a dangling symlink at the destination never redirects the write',
      () async {
        final s = src('l.arw', 'photo');
        Directory(p.join(tmp.path, 'outside')).createSync();
        final outside = p.join(tmp.path, 'outside', 'target.arw');
        final out = Directory(p.join(tmp.path, 'out'))..createSync();
        final dest = p.join(out.path, 'l.arw');
        Link(dest).createSync(outside);

        final r = await verifiedCopy(source: s.path, destinations: [dest]);

        expect(r.outcome, CopyOutcome.conflict);
        expect(File(outside).existsSync(), isFalse, reason: 'wrote outside');
        expect(Link(dest).targetSync(), outside, reason: 'link replaced');
      },
      testOn: '!windows',
    );

    test(
      'two copies into one name never truncate or delete each other',
      () async {
        final a = File(p.join(tmp.path, 'a.raw'))
          ..writeAsBytesSync(List.filled(8 * 1024 * 1024, 1));
        final b = File(p.join(tmp.path, 'b.raw'))
          ..writeAsBytesSync(List.filled(8 * 1024 * 1024, 2));
        final dest = p.join(tmp.path, 'out', 'same.raw');

        final results = await Future.wait([
          verifiedCopy(source: a.path, destinations: [dest]),
          verifiedCopy(source: b.path, destinations: [dest]),
        ]);

        final outcomes = results.map((r) => r.outcome).toSet();
        expect(outcomes, {CopyOutcome.copied, CopyOutcome.conflict});
        final winner = results.first.outcome == CopyOutcome.copied ? a : b;
        expect(File(dest).readAsBytesSync(), winner.readAsBytesSync());
        expect(
          Directory(p.dirname(dest)).listSync().map((e) => p.basename(e.path)),
          ['same.raw'],
        );
      },
    );

    test("a part file left by a crash isn't a photo", () async {
      final folder = Directory(p.join(tmp.path, 'lib'))..createSync();
      final part = partPathFor(p.join(folder.path, 'DSC_0001.NEF'));
      File(part).writeAsStringSync('half a photo');

      expect(p.basename(part), startsWith('.DSC_0001.NEF.'));
      expect(part, endsWith(kPartFileSuffix));
      expect(isSupportedMedia(part), isFalse);
      expect(await scanFolderFast(folder.path), isEmpty);
    });
  });
}
