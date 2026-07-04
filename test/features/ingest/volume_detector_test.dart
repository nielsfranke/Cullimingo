import 'dart:io';

import 'package:cullimingo/features/ingest/data/volume_detector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('volumes'));
  tearDown(() async => root.delete(recursive: true));

  Directory mount(String name) =>
      Directory(p.join(root.path, name))..createSync();

  test('lists mounted directories under the search roots', () async {
    mount('CARD1');
    mount('CARD2');

    final vols = await listVolumes(searchRoots: [root.path]);

    expect(vols.map((v) => v.name), containsAll(['CARD1', 'CARD2']));
  });

  test('flags volumes that hold a DCIM folder and sorts them first', () async {
    mount('Plain');
    final card = mount('SonyCard');
    Directory(p.join(card.path, 'DCIM')).createSync();

    final vols = await listVolumes(searchRoots: [root.path]);

    expect(vols.first.name, 'SonyCard');
    expect(vols.first.hasDcim, isTrue);
    expect(vols.firstWhere((v) => v.name == 'Plain').hasDcim, isFalse);
  });

  test('DCIM detection is case-insensitive', () async {
    final card = mount('card');
    Directory(p.join(card.path, 'dcim')).createSync();

    final vols = await listVolumes(searchRoots: [root.path]);

    expect(vols.single.hasDcim, isTrue);
  });

  test('ignores missing roots without throwing', () async {
    final vols = await listVolumes(
      searchRoots: [p.join(root.path, 'does-not-exist')],
    );
    expect(vols, isEmpty);
  });

  test('excludes the macOS system/boot volume', () {
    final sys = mount('Macintosh HD');
    Directory(
      p.join(sys.path, 'System', 'Library', 'CoreServices'),
    ).createSync(recursive: true);
    File(
      p.join(
        sys.path,
        'System',
        'Library',
        'CoreServices',
        'SystemVersion.plist',
      ),
    ).writeAsStringSync('<plist/>');
    mount('CARD');

    return listVolumes(searchRoots: [root.path]).then((vols) {
      expect(vols.map((v) => v.name), ['CARD']); // system volume filtered out
    });
  });

  test('newCards returns only DCIM volumes not seen before', () {
    const seenCard = Volume(path: '/v/old', name: 'old', hasDcim: true);
    const freshCard = Volume(path: '/v/new', name: 'new', hasDcim: true);
    const plainDisk = Volume(path: '/v/disk', name: 'disk', hasDcim: false);

    final fresh = newCards(
      {seenCard.path},
      [seenCard, freshCard, plainDisk],
    );

    expect(fresh.map((v) => v.path), ['/v/new']); // not seen + has DCIM
  });
}
