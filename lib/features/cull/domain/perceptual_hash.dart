/// Perceptual-hash (dHash) helpers for finding visually similar photos
/// (`BUILD_PLAN.md` §8) — **no ML**. The decode/resize lives in the data layer;
/// these are the pure bit-twiddling + clustering parts, so they're testable.
library;

/// Computes a 64-bit **dHash** from a row-major grayscale image of [width] ×
/// [height] (default 9 × 8). Each of the 8 rows contributes 8 bits: 1 when a
/// pixel is brighter than its right neighbour. Robust to scale/brightness, so
/// near-duplicate frames hash close together.
int dHashBits(List<int> gray, {int width = 9, int height = 8}) {
  var bits = 0;
  for (var row = 0; row < height; row++) {
    for (var col = 0; col < width - 1; col++) {
      final left = gray[row * width + col];
      final right = gray[row * width + col + 1];
      bits = (bits << 1) | (left > right ? 1 : 0);
    }
  }
  return bits;
}

/// Hamming distance between two hashes (count of differing bits; 0 = identical,
/// 64 = opposite). Smaller means more visually similar.
int hammingDistance(int a, int b) {
  var x = a ^ b;
  var count = 0;
  while (x != 0) {
    count += x & 1;
    x >>>= 1;
  }
  return count;
}

/// Clusters [items] (photo id + dHash) into groups of visually similar photos:
/// two photos are linked when their hashes are within [maxDistance] bits, and
/// linkage is transitive (union-find). Returns one list of ids per cluster
/// (singletons included), in first-seen order. Pure and deterministic.
List<List<int>> clusterByHash(
  List<({int id, int hash})> items, {
  int maxDistance = 10,
}) {
  final parent = List<int>.generate(items.length, (i) => i);
  int find(int x) {
    var root = x;
    while (parent[root] != root) {
      root = parent[root];
    }
    // Path-compress.
    var cur = x;
    while (parent[cur] != root) {
      final next = parent[cur];
      parent[cur] = root;
      cur = next;
    }
    return root;
  }

  for (var i = 0; i < items.length; i++) {
    for (var j = i + 1; j < items.length; j++) {
      if (hammingDistance(items[i].hash, items[j].hash) <= maxDistance) {
        parent[find(i)] = find(j);
      }
    }
  }

  final byRoot = <int, List<int>>{};
  for (var i = 0; i < items.length; i++) {
    byRoot.putIfAbsent(find(i), () => []).add(items[i].id);
  }
  return byRoot.values.toList();
}
