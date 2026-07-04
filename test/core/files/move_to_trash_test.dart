import 'dart:io';

import 'package:cullimingo/core/files/move_to_trash.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cullimingo_trash');
  });

  tearDown(() => tmp.delete(recursive: true));

  String makeFile(String name) {
    final path = p.join(tmp.path, name);
    File(path).writeAsStringSync('x');
    return path;
  }

  ProcessResult ok() => ProcessResult(0, 0, '', '');
  ProcessResult fail() => ProcessResult(0, 1, '', 'refused');

  test('linux batches into one gio trash call with a -- guard', () async {
    final a = makeFile('a.jpg');
    final b = makeFile('b.jpg');
    final calls = <(String, List<String>)>[];

    final result = await moveToTrash(
      [a, b],
      os: 'linux',
      runProcess: (exe, args) async {
        calls.add((exe, args));
        return ok();
      },
    );

    expect(result.trashed, 2);
    expect(result.failed, isEmpty);
    expect(result.error, isNull);
    expect(calls.single.$1, 'gio');
    expect(calls.single.$2, ['trash', '--', a, b]);
  });

  test('macos sends one Finder delete per chunk with escaped paths', () async {
    final a = makeFile('with "quote".jpg');
    final calls = <(String, List<String>)>[];

    final result = await moveToTrash(
      [a],
      os: 'macos',
      runProcess: (exe, args) async {
        calls.add((exe, args));
        return ok();
      },
    );

    expect(result.trashed, 1);
    expect(calls.single.$1, 'osascript');
    final script = calls.single.$2[1];
    expect(script, startsWith('tell application "Finder" to delete {'));
    expect(script, contains(r'with \"quote\".jpg'));
  });

  test('missing files are skipped and counted as done', () async {
    final a = makeFile('a.jpg');
    final gone = p.join(tmp.path, 'never-existed.jpg');
    final calls = <List<String>>[];

    final result = await moveToTrash(
      [a, gone],
      os: 'linux',
      runProcess: (exe, args) async {
        calls.add(args);
        return ok();
      },
    );

    expect(result.trashed, 2);
    expect(result.failed, isEmpty);
    expect(calls.single, ['trash', '--', a]); // only the real file hits gio
  });

  test(
    'a failing chunk is retried per file to attribute the failure',
    () async {
      final a = makeFile('a.jpg');
      final b = makeFile('b.jpg');
      final c = makeFile('c.jpg');

      final result = await moveToTrash(
        [a, b, c],
        os: 'linux',
        runProcess: (exe, args) async {
          final paths = args.sublist(2); // after 'trash', '--'
          // The chunk (or the single retry) fails whenever b is included.
          return paths.contains(b) ? fail() : ok();
        },
      );

      expect(result.failed, [b]);
      expect(result.trashed, 2);
      expect(result.error, isNull);
    },
  );

  test('a missing tool fails the rest of the run with a clear error', () async {
    final a = makeFile('a.jpg');
    final b = makeFile('b.jpg');

    final result = await moveToTrash(
      [a, b],
      os: 'linux',
      chunkSize: 1,
      runProcess: (exe, args) async =>
          throw ProcessException(exe, args, 'not found'),
    );

    expect(result.trashed, 0);
    expect(result.failed, [a, b]);
    expect(result.error, contains('gio'));
  });

  test('an unsupported platform refuses without running anything', () async {
    final result = await moveToTrash(
      ['/x.jpg'],
      os: 'windows',
      runProcess: (exe, args) async => fail(),
    );

    expect(result.trashed, 0);
    expect(result.failed, ['/x.jpg']);
    expect(result.error, contains('not supported'));
  });

  test('progress ticks after each chunk over the full path count', () async {
    final paths = [for (var i = 0; i < 5; i++) makeFile('f$i.jpg')];
    final ticks = <(int, int)>[];

    await moveToTrash(
      paths,
      os: 'linux',
      chunkSize: 2,
      runProcess: (exe, args) async => ok(),
      onProgress: (processed, total) => ticks.add((processed, total)),
    );

    expect(ticks, [(0, 5), (2, 5), (4, 5), (5, 5)]);
  });
}
