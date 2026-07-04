import 'package:cullimingo/features/cull/domain/recent_folders.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('promoteRecentFolder', () {
    test('prepends a brand-new folder', () {
      expect(
        promoteRecentFolder(['/a', '/b'], '/c'),
        ['/c', '/a', '/b'],
      );
    });

    test('moves an already-known folder to the front (no duplicate)', () {
      expect(
        promoteRecentFolder(['/a', '/b', '/c'], '/c'),
        ['/c', '/a', '/b'],
      );
    });

    test('re-opening the current front is a no-op in effect', () {
      expect(
        promoteRecentFolder(['/a', '/b'], '/a'),
        ['/a', '/b'],
      );
    });

    test('caps the list at max, dropping the oldest', () {
      final current = [for (var i = 0; i < 12; i++) '/dir$i'];
      final next = promoteRecentFolder(current, '/new');
      expect(next.length, 12);
      expect(next.first, '/new');
      expect(next.contains('/dir11'), isFalse); // oldest evicted
    });

    test('a blank path leaves the list untouched', () {
      expect(promoteRecentFolder(['/a'], ''), ['/a']);
    });
  });
}
