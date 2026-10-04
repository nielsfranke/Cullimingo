import 'dart:async';
import 'dart:io';

import 'package:cullimingo/core/files/verified_copy.dart';
import 'package:cullimingo/core/files/watched_copy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('watched'));
  tearDown(() async => tmp.delete(recursive: true));

  /// A source whose read never returns, like a file on a NAS that dropped: a
  /// FIFO nobody writes to. Unblocked at teardown so no I/O thread lingers.
  String hungSource() {
    final fifo = p.join(tmp.path, 'hung.raw');
    final made = Process.runSync('mkfifo', [fifo]);
    if (made.exitCode != 0) fail('mkfifo failed: ${made.stderr}');
    // Opening the write end (and closing it) hands the stuck reader an EOF.
    addTearDown(
      () => Process.run('sh', ['-c', ': > "$fifo"']).timeout(
        const Duration(seconds: 5),
      ),
    );
    return fifo;
  }

  test('copies like verifiedCopy', () async {
    final s = File(p.join(tmp.path, 'a.arw'))..writeAsStringSync('photo');
    final dest = p.join(tmp.path, 'out', 'a.arw');

    final r = await watchedCopy(
      source: s.path,
      destinations: [dest],
      quietPeriod: Duration.zero,
    );

    expect(r.outcome, CopyOutcome.copied);
    expect(File(dest).readAsStringSync(), 'photo');
  });

  test(
    'a copy that stops making progress is given up on',
    () async {
      final r = await watchedCopy(
        source: hungSource(),
        destinations: [p.join(tmp.path, 'out', 'hung.raw')],
        quietPeriod: Duration.zero,
        stallTimeout: const Duration(seconds: 1),
      ).timeout(const Duration(seconds: 20));

      expect(r.outcome, CopyOutcome.error);
      expect(r.message, kCopyStalledMessage);
      expect(File(p.join(tmp.path, 'out', 'hung.raw')).existsSync(), isFalse);
    },
    testOn: 'mac-os || linux',
  );

  test(
    'abandoning a hung copy ends it at once',
    () async {
      final abandon = Completer<void>();
      final copy = watchedCopy(
        source: hungSource(),
        destinations: [p.join(tmp.path, 'out', 'hung.raw')],
        quietPeriod: Duration.zero,
        abandon: abandon.future,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      abandon.complete();

      final r = await copy.timeout(const Duration(seconds: 5));

      expect(r.outcome, CopyOutcome.error);
      expect(r.message, kCopyAbandonedMessage);
    },
    testOn: 'mac-os || linux',
  );
}
