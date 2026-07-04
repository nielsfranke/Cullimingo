import 'package:cullimingo/features/cull/domain/dropped_folders.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('droppedFoldersToOpen', () {
    // Treat anything without a file extension as a directory for these tests.
    bool fakeIsDir(String path) => !path.contains('.');

    test('a dropped directory opens itself', () {
      expect(
        droppedFoldersToOpen(['/photos/shoot'], isDirectory: fakeIsDir),
        ['/photos/shoot'],
      );
    });

    test('a dropped file opens its containing folder', () {
      expect(
        droppedFoldersToOpen([
          '/photos/shoot/IMG_1.arw',
        ], isDirectory: fakeIsDir),
        ['/photos/shoot'],
      );
    });

    test('multiple folders open in drop order', () {
      expect(
        droppedFoldersToOpen(['/a', '/b'], isDirectory: fakeIsDir),
        ['/a', '/b'],
      );
    });

    test('duplicates collapse (two files from the same folder)', () {
      expect(
        droppedFoldersToOpen(
          ['/shoot/a.jpg', '/shoot/b.jpg'],
          isDirectory: fakeIsDir,
        ),
        ['/shoot'],
      );
    });

    test('a folder and a file inside it both resolve to that folder once', () {
      expect(
        droppedFoldersToOpen(
          ['/shoot', '/shoot/a.jpg'],
          isDirectory: fakeIsDir,
        ),
        ['/shoot'],
      );
    });

    test('empty paths are skipped', () {
      expect(
        droppedFoldersToOpen(['', '/shoot'], isDirectory: fakeIsDir),
        ['/shoot'],
      );
    });
  });
}
