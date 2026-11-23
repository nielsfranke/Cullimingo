import 'dart:io';

import 'package:cullimingo/core/logging/file_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:talker_flutter/talker_flutter.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('cm_file_log'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('mirrors talker entries into cullimingo.log after a header', () async {
    final talker = Talker(settings: TalkerSettings(useConsoleLogs: false));
    final log = (await FileLog.start(talker, dir: dir, header: 'test 1.0'))!;

    talker
      ..info('hello file')
      ..warning('careful');
    await Future<void>.delayed(Duration.zero);
    await log.close();

    final text = File(p.join(dir.path, 'cullimingo.log')).readAsStringSync();
    expect(text, contains('==== '));
    expect(text, contains('test 1.0'));
    expect(text, contains('hello file'));
    expect(text, contains('careful'));
    expect(text.indexOf('hello file'), lessThan(text.indexOf('careful')));
  });

  test('rotates past maxBytes, keeping one previous file', () async {
    final talker = Talker(settings: TalkerSettings(useConsoleLogs: false));
    final log = (await FileLog.start(talker, dir: dir, maxBytes: 200))!;

    for (var i = 0; i < 20; i++) {
      talker.info('entry $i ${'x' * 40}');
    }
    await Future<void>.delayed(Duration.zero);
    await log.close();

    final names = dir.listSync().map((e) => p.basename(e.path)).toSet();
    expect(names, {'cullimingo.log', 'cullimingo.1.log'});
    final current = File(p.join(dir.path, 'cullimingo.log'));
    expect(current.lengthSync(), lessThan(400));
    // The newest entries are in the two files together; nothing older than
    // the previous file survives.
    final both =
        File(p.join(dir.path, 'cullimingo.1.log')).readAsStringSync() +
        current.readAsStringSync();
    expect(both, contains('entry 19'));
    expect(both, isNot(contains('entry 0 ')));
  });

  test('appends across sessions', () async {
    for (final word in ['first', 'second']) {
      final talker = Talker(settings: TalkerSettings(useConsoleLogs: false));
      final log = (await FileLog.start(talker, dir: dir))!;
      talker.info(word);
      await Future<void>.delayed(Duration.zero);
      await log.close();
    }
    final text = File(p.join(dir.path, 'cullimingo.log')).readAsStringSync();
    expect(text, contains('first'));
    expect(text, contains('second'));
  });
}
