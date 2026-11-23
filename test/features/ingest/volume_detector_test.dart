import 'dart:io';

import 'package:cullimingo/core/files/windows_fs.dart';
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

  group('windowsSourceVolumes', () {
    WindowsDrive drive(
      String root,
      WindowsDriveType type, [
      String label = '',
    ]) => (root: root, type: type, label: label);

    test('offers cards, external disks and shares, never the system drive', () {
      final volumes = windowsSourceVolumes(
        [
          drive(r'C:\', WindowsDriveType.fixed, 'Windows'),
          drive(r'D:\', WindowsDriveType.fixed, 'Data'),
          drive(r'E:\', WindowsDriveType.removable, 'EOS_DIGITAL'),
          drive(r'F:\', WindowsDriveType.cdrom, 'DVD'),
          drive(r'Z:\', WindowsDriveType.remote),
        ],
        systemDrive: 'C:',
        hasDcim: (root) => root == r'E:\',
      );

      expect(volumes.map((v) => v.path), [r'D:\', r'E:\', r'Z:\']);
      expect(volumes.map((v) => v.name), [
        'Data (D:)',
        'EOS_DIGITAL (E:)',
        'Z:',
      ]);
      expect(volumes.map((v) => v.hasDcim), [false, true, false]);
    });

    test('matches the system drive case- and slash-insensitively', () {
      final volumes = windowsSourceVolumes(
        [drive(r'D:\', WindowsDriveType.fixed)],
        systemDrive: r'd:\',
        hasDcim: (_) => false,
      );

      expect(volumes, isEmpty);
    });

    test('a new card shows up in newCards', () {
      final volumes = windowsSourceVolumes(
        [drive(r'E:\', WindowsDriveType.removable, 'NIKON Z 8')],
        systemDrive: 'C:',
        hasDcim: (_) => true,
      );

      expect(newCards({}, volumes).single.path, r'E:\');
    });
  });
}
