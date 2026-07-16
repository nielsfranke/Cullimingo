import 'dart:io';

import 'package:cullimingo/core/files/verified_copy.dart';
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
}
