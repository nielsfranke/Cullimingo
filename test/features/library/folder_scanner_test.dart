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
    final files = await scanFolderFast(tmp.path, includeVideos: true);
    expect(await names(files), {'p1.jpg', 'p2.arw', 'v1.mp4', 'v2.mov'});
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
}
