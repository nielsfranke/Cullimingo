import 'dart:io';

import 'package:cullimingo/core/files/posix_fs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('posix_fs'));
  tearDown(() async => tmp.delete(recursive: true));

  group('publishNoReplace', () {
    test('gives the file its name and removes the old one', () {
      final from = File(p.join(tmp.path, 'from'))..writeAsStringSync('a');
      final to = p.join(tmp.path, 'to');

      expect(publishNoReplace(from.path, to), PublishOutcome.published);
      expect(File(to).readAsStringSync(), 'a');
      expect(from.existsSync(), isFalse);
    });

    test('never replaces an existing file', () {
      final from = File(p.join(tmp.path, 'from'))..writeAsStringSync('new');
      final to = File(p.join(tmp.path, 'to'))..writeAsStringSync('old');

      expect(publishNoReplace(from.path, to.path), PublishOutcome.taken);
      expect(to.readAsStringSync(), 'old');
      expect(from.readAsStringSync(), 'new');
    });

    test(
      'treats a dangling symlink as taken',
      () {
        final from = File(p.join(tmp.path, 'from'))..writeAsStringSync('x');
        final to = p.join(tmp.path, 'to');
        Link(to).createSync(p.join(tmp.path, 'nowhere'));

        expect(publishNoReplace(from.path, to), PublishOutcome.taken);
        expect(File(p.join(tmp.path, 'nowhere')).existsSync(), isFalse);
      },
      testOn: '!windows',
    );
  });

  group('volumeInfo', () {
    test(
      'reports a mount point and free space for a real folder',
      () {
        final info = volumeInfo(tmp.path);

        expect(info, isNotNull);
        expect(info!.freeBytes, greaterThan(0));
        final real = tmp.resolveSymbolicLinksSync();
        expect(
          info.mountPoint == '/' ||
              p.isWithin(info.mountPoint, real) ||
              info.mountPoint == real,
          isTrue,
          reason: '${info.mountPoint} should contain $real',
        );
      },
      testOn: 'mac-os || linux',
    );

    test(
      'a missing folder reports the volume it would be created on',
      () {
        final missing = p.join(tmp.path, 'gone', 'deeper');

        expect(
          volumeInfo(missing)?.mountPoint,
          volumeInfo(tmp.path)?.mountPoint,
        );
      },
      testOn: 'mac-os || linux',
    );
  });

  group('linuxMountPointOf', () {
    const mountInfo =
        '22 1 8:2 / / rw,relatime - ext4 /dev/sda2 rw\n'
        '40 22 0:35 / /mnt/nas rw - nfs srv:/x rw\n'
        r'41 22 8:17 / /media/u/My\040Card rw - exfat /dev/sdb1 rw'
        '\n';

    test('picks the deepest mount point holding the path', () {
      expect(linuxMountPointOf('/mnt/nas/2026/a', mountInfo), '/mnt/nas');
      expect(linuxMountPointOf('/mnt/nas', mountInfo), '/mnt/nas');
      expect(linuxMountPointOf('/mnt/nasty', mountInfo), '/');
      expect(linuxMountPointOf('/home/u', mountInfo), '/');
    });

    test('unescapes spaces in mount points', () {
      expect(
        linuxMountPointOf('/media/u/My Card/DCIM', mountInfo),
        '/media/u/My Card',
      );
    });

    test('an unmounted mount point resolves to the parent filesystem', () {
      const unmounted = '22 1 8:2 / / rw,relatime - ext4 /dev/sda2 rw\n';
      expect(linuxMountPointOf('/mnt/nas/2026', unmounted), '/');
    });
  });
}
