import 'dart:async';
import 'dart:io';

import 'package:cullimingo/features/library/data/folder_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('scan');
    File(p.join(tmp.path, 'p1.jpg')).writeAsStringSync('x');
    File(p.join(tmp.path, 'v1.mp4')).writeAsStringSync('x');
    File(p.join(tmp.path, 'junk.txt')).writeAsStringSync('x');
    // Companions of p1.jpg, plus an orphan sidecar with no media sibling.
    File(p.join(tmp.path, 'p1.xmp')).writeAsStringSync('x');
    File(p.join(tmp.path, 'p1.thm')).writeAsStringSync('x');
    File(p.join(tmp.path, 'orphan.xmp')).writeAsStringSync('x');
    final sub = Directory(p.join(tmp.path, 'sub'))..createSync();
    File(p.join(sub.path, 'p2.arw')).writeAsStringSync('x');
    File(p.join(sub.path, 'v2.mov')).writeAsStringSync('x');
  });
  tearDown(() async => tmp.delete(recursive: true));

  Future<Set<String>> names(List<ScannedFile> files) async =>
      files.map((f) => p.basename(f.path)).toSet();

  test('default: photos only, recursive, junk and video excluded', () async {
    final files = await scanFolderFast(tmp.path);
    expect(await names(files), {'p1.jpg', 'p2.arw'});
  });

  test('includeVideos adds videos (still recursive)', () async {
    final files = await scanFolderFast(tmp.path, includeVideos: true);
    expect(await names(files), {'p1.jpg', 'p2.arw', 'v1.mp4', 'v2.mov'});
  });

  test('a _Rejected folder is skipped, unless it is the root (#14)', () async {
    final rejected = Directory(p.join(tmp.path, '_Rejected'))..createSync();
    File(p.join(rejected.path, 'gone.jpg')).writeAsStringSync('x');
    File(p.join(tmp.path, 'sub', 'keep_Rejected.jpg')).writeAsStringSync('x');

    expect(await names(await scanFolderFast(tmp.path)), {
      'p1.jpg',
      'p2.arw',
      'keep_Rejected.jpg',
    });
    expect(await names(await scanFolderFast(rejected.path)), {'gone.jpg'});
  });

  test('recursive: false stays at the top level', () async {
    final files = await scanFolderFast(tmp.path, recursive: false);
    expect(await names(files), {'p1.jpg'});
  });

  test('top level + videos', () async {
    final files = await scanFolderFast(
      tmp.path,
      recursive: false,
      includeVideos: true,
    );
    expect(await names(files), {'p1.jpg', 'v1.mp4'});
  });

  test('an unreadable subdirectory is skipped, not fatal', () async {
    // A locked sub-tree, like the macOS-protected `.Trashes` on a camera card
    // that made a DJI import hang forever on "Scanning…".
    final locked = Directory(p.join(tmp.path, 'locked'))..createSync();
    File(p.join(locked.path, 'secret.jpg')).writeAsStringSync('x');
    await Process.run('chmod', ['000', locked.path]);
    // Always restore perms so tearDown's recursive delete can remove it.
    addTearDown(() => Process.run('chmod', ['755', locked.path]));

    // Only meaningful when 000 actually restricts us (not as root).
    var restricted = true;
    try {
      Directory(locked.path).listSync();
      restricted = false;
    } on FileSystemException {
      // Expected: the directory is genuinely unreadable.
    }
    if (!restricted) {
      markTestSkipped('cannot restrict directory access (running as root?)');
      return;
    }

    // The recursive walk hits "permission denied" descending into `locked`,
    // but completes over the readable files instead of throwing/hanging.
    final scan = await scanFolder(tmp.path, includeVideos: true);
    expect(await names(scan.files), {'p1.jpg', 'p2.arw', 'v1.mp4', 'v2.mov'});
    // …and says so: the listing is incomplete, naming the locked folder.
    expect(scan.complete, isFalse);
    expect(scan.unreadable.map((u) => u.path), contains(locked.path));
  });

  group('unreadable entries are reported, not just logged', () {
    // An injected listing: tests run as root in Docker, where `chmod 000`
    // restricts nothing, so the real case above is skipped there.
    // Errors are error *events* the listing carries on past, as a recursive
    // Directory.list does.
    Stream<FileSystemEntity> listingWith(List<Object> events) {
      final c = StreamController<FileSystemEntity>();
      for (final e in events) {
        e is FileSystemEntity ? c.add(e) : c.addError(e);
      }
      unawaited(c.close());
      return c.stream;
    }

    test('hidden entries are neither photos nor problems', () async {
      // What a Mac leaves on an exFAT/FAT card or drive: AppleDouble `._`
      // companions beside every file, and protected system folders.
      File(p.join(tmp.path, '._p1.jpg')).writeAsStringSync('appledouble');
      File(p.join(tmp.path, 'sub', '._p2.arw')).writeAsStringSync('x');
      final trash = Directory(p.join(tmp.path, '.Trashes', '501'))
        ..createSync(recursive: true);
      File(p.join(trash.path, 'deleted.jpg')).writeAsStringSync('x');
      File(
        p.join(tmp.path, '.p3.jpg.0a1b2c3d4e5f.part'),
      ).writeAsStringSync('x');

      final scan = await walkFolder(
        tmp.path,
        recursive: true,
        includeVideos: false,
        lister: (dir) => listingWith([
          ...dir.listSync(recursive: true),
          FileSystemException(
            'Directory listing failed',
            p.join(tmp.path, '.Spotlight-V100'),
            const OSError('Operation not permitted', 1),
          ),
        ]),
      );
      expect(await names(scan.files), {'p1.jpg', 'p2.arw'});
      expect(scan.complete, isTrue, reason: '${scan.unreadable}');
      // A hidden root itself is still scanned.
      final hiddenRoot = Directory(p.join(tmp.path, '.shoot'))..createSync();
      File(p.join(hiddenRoot.path, 'p4.jpg')).writeAsStringSync('x');
      expect(await names(await scanFolderFast(hiddenRoot.path)), {'p4.jpg'});
    });

    test('a complete scan has no problems', () async {
      final scan = await scanFolder(tmp.path);
      expect(scan.complete, isTrue);
      expect(scan.unreadable, isEmpty);
    });

    test('a permission error is recorded with its path and reason', () async {
      final locked = p.join(tmp.path, 'DCIM', '101MSDCF');
      final scan = await walkFolder(
        tmp.path,
        recursive: true,
        includeVideos: false,
        lister: (_) => listingWith([
          File(p.join(tmp.path, 'p1.jpg')),
          FileSystemException(
            'Directory listing failed',
            locked,
            const OSError('Permission denied', 13),
          ),
          File(p.join(tmp.path, 'sub', 'p2.arw')),
        ]),
      );
      expect(await names(scan.files), {'p1.jpg', 'p2.arw'});
      expect(scan.complete, isFalse);
      expect(scan.unreadable.single.path, locked);
      expect(scan.unreadable.single.reason, 'Permission denied');
    });

    test(
      'a stalled listing keeps what it found and is marked incomplete',
      () async {
        final scan = await walkFolder(
          tmp.path,
          recursive: true,
          includeVideos: false,
          // A seized card reader: one entry, then the next never comes.
          lister: (_) =>
              (StreamController<FileSystemEntity>()
                    ..add(File(p.join(tmp.path, 'p1.jpg'))))
                  .stream,
        );
        expect(await names(scan.files), {'p1.jpg'});
        expect(scan.unreadable.single.path, tmp.path);
        expect(scan.unreadable.single.reason, contains('stalled'));
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });

  test('attaches same-stem companions, ignores orphan sidecars', () async {
    final files = await scanFolderFast(tmp.path);
    final p1 = files.firstWhere((f) => p.basename(f.path) == 'p1.jpg');
    expect(
      p1.companions.map(p.basename).toSet(),
      {'p1.xmp', 'p1.thm'},
    );
    expect(p1.hasSidecar, isTrue);
    // The orphan .xmp belongs to no media file, so it's never attached.
    expect(
      files.every((f) => f.companions.every((c) => !c.endsWith('orphan.xmp'))),
      isTrue,
    );
  });

  test('attaches a per-file sidecar (p1.jpg.xmp) to its photo', () async {
    File(p.join(tmp.path, 'p1.jpg.xmp')).writeAsStringSync('x');
    final files = await scanFolderFast(tmp.path);
    final p1 = files.firstWhere((f) => p.basename(f.path) == 'p1.jpg');
    expect(p1.companions.map(p.basename).toSet(), {
      'p1.xmp',
      'p1.thm',
      'p1.jpg.xmp',
    });
  });
}
