import 'dart:io';

import 'package:cullimingo/core/files/destination_check.dart';
import 'package:cullimingo/core/files/posix_fs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('dest_check'));
  tearDown(() async => tmp.delete(recursive: true));

  const gb = 1024 * 1024 * 1024;

  /// A fake volume table: [mounts] maps mount point → free bytes; a path
  /// lives on the deepest mount point holding it.
  VolumeInfo? Function(String) fakeVolumes(Map<String, int> mounts) => (path) {
    final mount =
        (mounts.keys.where((m) => path == m || p.isWithin(m, path)).toList()
              ..sort((a, b) => b.length.compareTo(a.length)))
            .firstOrNull;
    return mount == null
        ? null
        : VolumeInfo(mountPoint: mount, freeBytes: mounts[mount]!);
  };

  PlannedCopy file(String rel, int size) =>
      (source: '/card/$rel', relPath: rel, sizeBytes: size);

  test('passes a connected destination with room', () {
    final dest = Directory(p.join(tmp.path, 'photos'))..createSync();

    final check = checkDestinationsSync(
      roots: [dest.path],
      files: [file('a.arw', gb)],
      rememberedMounts: {dest.path: tmp.path},
      probe: fakeVolumes({tmp.path: 10 * gb}),
    );

    expect(check.problems, isEmpty);
    expect(check.mounts, {dest.path: tmp.path});
  });

  test('refuses a destination whose drive is gone (empty mount point)', () {
    // The drive was mounted at <tmp>/nas; unplugged, the folder is still
    // there but now lives on the parent (system) volume.
    final nas = Directory(p.join(tmp.path, 'nas'))..createSync();

    final check = checkDestinationsSync(
      roots: [nas.path],
      files: [file('a.arw', 1)],
      rememberedMounts: {nas.path: nas.path},
      probe: fakeVolumes({'/': 100 * gb}),
    );

    expect(check.ok, isFalse);
    expect(check.problems.single, contains("isn't connected"));
  });

  test('never treats a vanished destination as a folder to create', () {
    final gone = p.join(tmp.path, 'Volumes', 'Card');

    final check = checkDestinationsSync(
      roots: [gone],
      files: [file('a.arw', 1)],
      probe: fakeVolumes({'/': 100 * gb}),
    );

    expect(check.problems.single, contains('folder not found'));
    expect(Directory(gone).existsSync(), isFalse);
  });

  test('refuses when the files would not fit', () {
    final dest = Directory(p.join(tmp.path, 'photos'))..createSync();

    final check = checkDestinationsSync(
      roots: [dest.path],
      files: [file('a.arw', 3 * gb), file('b.arw', 3 * gb)],
      probe: fakeVolumes({tmp.path: 5 * gb}),
    );

    expect(check.problems.single, contains('Not enough space'));
    expect(check.problems.single, contains('6.0 GB'));
  });

  test('two destinations on one drive add up', () {
    final main = Directory(p.join(tmp.path, 'main'))..createSync();
    final backup = Directory(p.join(tmp.path, 'backup'))..createSync();

    final check = checkDestinationsSync(
      roots: [main.path, backup.path],
      files: [file('a.arw', 3 * gb)],
      probe: fakeVolumes({tmp.path: 5 * gb}), // room for one copy, not two
    );

    expect(check.problems.single, contains('Not enough space'));
  });

  test('files already at the destination need no room', () {
    final dest = Directory(p.join(tmp.path, 'photos'))..createSync();
    File(p.join(dest.path, 'a.arw')).writeAsStringSync('done');

    final check = checkDestinationsSync(
      roots: [dest.path],
      files: [file('a.arw', 50 * gb), file('b.arw', gb)],
      probe: fakeVolumes({tmp.path: 2 * gb}),
    );

    expect(check.problems, isEmpty);
  });

  test('a subfolder still to be created is fine when allowed', () {
    final root = p.join(tmp.path, 'photos', 'Selects');
    Directory(p.dirname(root)).createSync();

    final check = checkDestinationsSync(
      roots: [root],
      files: [file('a.arw', 1)],
      mustExist: false,
      probe: fakeVolumes({tmp.path: gb}),
    );

    expect(check.problems, isEmpty);
    expect(check.mounts, {p.dirname(root): tmp.path});
  });

  test(
    'the real check runs off the UI isolate',
    () async {
      final check = await checkDestinations(
        roots: [tmp.path],
        files: const [(source: '/x', relPath: 'x', sizeBytes: 1)],
      );

      expect(check.problems, isEmpty);
      expect(check.mounts, isNotEmpty);
    },
    testOn: 'mac-os || linux',
  );

  group('a drive that is plainly not mounted, with nothing remembered', () {
    // System state is faked throughout: anchor = the nearest existing folder
    // (symlinks resolved), anchorMount = the volume it's on.
    String? missing(
      String root, {
      String? anchor,
      String? anchorMount,
      List<String> bases = const ['/media', '/run/media', '/Volumes'],
      String fstab = '',
      Set<String> mounted = const {'/'},
    }) => unmountedDriveFor(
      root,
      anchor: anchor,
      anchorMount: anchorMount,
      removableBases: bases,
      fstab: fstab,
      mounted: mounted,
    );

    test('macOS: an unplugged /Volumes drive resolves to the boot disk', () {
      expect(
        missing('/Volumes/Card/Shoots', anchor: '/Volumes', anchorMount: '/'),
        '/Volumes/Card',
      );
      // A leftover empty /Volumes/Card folder is no better.
      expect(
        missing(
          '/Volumes/Card/Shoots',
          anchor: '/Volumes/Card',
          anchorMount: '/',
        ),
        '/Volumes/Card',
      );
    });

    test('macOS: a connected drive and the boot-disk symlink pass', () {
      expect(
        missing(
          '/Volumes/Card/Shoots',
          anchor: '/Volumes/Card/Shoots',
          anchorMount: '/Volumes/Card',
        ),
        isNull,
      );
      // /Volumes/Macintosh HD → / : resolves out of /Volumes, not judged.
      expect(
        missing(
          '/Volumes/Macintosh HD/Users/me/Photos',
          anchor: '/Users/me/Photos',
          anchorMount: '/System/Volumes/Data',
        ),
        isNull,
      );
    });

    test('Linux: unplugged udisks drives under /media and /run/media', () {
      expect(
        missing(
          '/media/me/Backup/Photos',
          anchor: '/media/me',
          anchorMount: '/',
        ),
        '/media/me/Backup',
      );
      // /run is a tmpfs: the leftover path is on /run, not inside the base.
      expect(
        missing(
          '/run/media/me/Backup/Photos',
          anchor: '/run/media/me',
          anchorMount: '/run',
        ),
        '/run/media/me/Backup',
      );
      expect(
        missing(
          '/media/me/Backup/Photos',
          anchor: '/media/me/Backup/Photos',
          anchorMount: '/media/me/Backup',
        ),
        isNull,
      );
    });

    test('the system disk is never refused', () {
      for (final (root, mount) in [
        ('/home/me/Pictures/Import', '/'),
        ('/Users/me/Pictures/Import', '/System/Volumes/Data'),
        ('/home/me/Pictures/Import', '/home'),
      ]) {
        expect(
          missing(root, anchor: root, anchorMount: mount),
          isNull,
          reason: root,
        );
      }
    });

    test('/mnt is judged by fstab only, never by the folder heuristic', () {
      // A plain /mnt/photos folder on the system disk, nothing in fstab.
      expect(
        missing(
          '/mnt/photos/2026',
          anchor: '/mnt/photos/2026',
          anchorMount: '/',
          bases: const ['/media', '/run/media'], // what Linux uses
        ),
        isNull,
      );
    });

    const fstab = r'''
# <file system> <mount point> <type> <options> <dump> <pass>
UUID=1111 /             ext4  defaults 0 1
UUID=2222 none          swap  sw       0 0
//nas/photos /mnt/nas\040photos cifs noauto,user 0 0
UUID=3333 /srv/archive  ext4  nofail   0 2
''';

    test('Linux: an fstab mount point that is not mounted is refused', () {
      expect(
        missing(
          '/mnt/nas photos/2026',
          anchor: '/mnt/nas photos/2026',
          anchorMount: '/',
          fstab: fstab,
          mounted: const {'/', '/srv/archive'},
        ),
        '/mnt/nas photos',
      );
      expect(
        missing(
          '/srv/archive/raw',
          anchor: '/srv',
          anchorMount: '/',
          fstab: fstab,
        ),
        '/srv/archive',
      );
    });

    test('Linux: fstab passes when mounted, and is ignored when unrelated', () {
      expect(
        missing(
          '/mnt/nas photos/2026',
          anchor: '/mnt/nas photos/2026',
          anchorMount: '/mnt/nas photos',
          fstab: fstab,
          mounted: const {'/', '/mnt/nas photos'},
        ),
        isNull,
      );
      // `/` and swap entries never count; /home isn't under any fstab mount.
      expect(
        missing(
          '/home/me/Import',
          anchor: '/home/me/Import',
          anchorMount: '/',
          fstab: fstab,
        ),
        isNull,
      );
      // No mount table to compare with (unreadable): never guess.
      expect(
        missing(
          '/srv/archive/raw',
          anchor: '/srv',
          anchorMount: '/',
          fstab: fstab,
          mounted: const {},
        ),
        isNull,
      );
    });

    test('fstabMountPoints skips comments, / and swap; unescapes', () {
      expect(fstabMountPoints(fstab), ['/mnt/nas photos', '/srv/archive']);
    });

    test('checkDestinationsSync refuses with the drive message', () {
      final check = checkDestinationsSync(
        roots: ['/media/me/Backup/Photos'],
        files: [file('a.arw', 1)],
        mustExist: false,
        probe: fakeVolumes({'/': 10 * gb}),
        resolveAnchor: (_) => '/media/me',
        removableBases: const ['/media'],
        fstab: '',
        mountInfo: '',
      );
      expect(check.ok, isFalse);
      expect(
        check.problems.single,
        contains("its drive isn't connected (expected at /media/me/Backup)"),
      );
    });
  });
}
