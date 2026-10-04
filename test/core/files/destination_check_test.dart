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
}
