import 'package:cullimingo/features/cull/domain/perceptual_hash.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dHashBits', () {
    test('a flat image hashes to 0 (no left>right anywhere)', () {
      expect(dHashBits(List.filled(72, 128)), 0);
    });

    test('a left-to-right gradient sets every bit', () {
      // Each row strictly decreasing → every pixel brighter than its right.
      final gray = <int>[
        for (var row = 0; row < 8; row++)
          for (var col = 0; col < 9; col++) 100 - col,
      ];
      expect(dHashBits(gray), 0xFFFFFFFFFFFFFFFF);
    });
  });

  group('hammingDistance', () {
    test('identical hashes have distance 0', () {
      expect(hammingDistance(0xABCD, 0xABCD), 0);
    });
    test('counts differing bits', () {
      expect(hammingDistance(0x0, 0xF), 4);
      expect(hammingDistance(0xA, 0x3), 2); // 1010 vs 0011 → 2 bits differ
    });
  });

  group('clusterByHash', () {
    test('groups hashes within the distance, splits far ones', () {
      final groups = clusterByHash([
        (id: 1, hash: 0x0),
        (id: 2, hash: 0x1), // 1 bit from id 1
        (id: 3, hash: 0xFFFF), // far away
      ], maxDistance: 4);
      expect(groups.length, 2);
      final byId = {for (final g in groups) g.first: g};
      expect(byId[1]!.toSet(), {1, 2});
      expect(byId[3], [3]);
    });

    test('linkage is transitive (a~b, b~c ⇒ one group)', () {
      final groups = clusterByHash([
        (id: 1, hash: 0x00),
        (id: 2, hash: 0x03), // 2 bits from 1
        (id: 3, hash: 0x0F), // 2 bits from 2, 4 from 1
      ], maxDistance: 2);
      expect(groups.length, 1);
      expect(groups.first.toSet(), {1, 2, 3});
    });
  });
}
