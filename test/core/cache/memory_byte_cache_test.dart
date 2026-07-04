import 'dart:typed_data';

import 'package:cullimingo/core/cache/memory_byte_cache.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(int n) => Uint8List(n);

void main() {
  test('stores and returns values, tracking total bytes', () {
    final cache = MemoryByteCache(maxBytes: 1000)
      ..put('a', _bytes(100))
      ..put('b', _bytes(200));

    expect(cache.get('a'), isNotNull);
    expect(cache.get('b')!.length, 200);
    expect(cache.currentBytes, 300);
    expect(cache.get('missing'), isNull);
  });

  test('evicts least-recently-used entries past the budget', () {
    final cache = MemoryByteCache(maxBytes: 300)
      ..put('a', _bytes(100))
      ..put('b', _bytes(100))
      // Touch 'a' so 'b' becomes least-recently-used, then overflow the budget.
      ..get('a')
      ..put('c', _bytes(150)); // 100+100+150 = 350 > 300 -> evict oldest (b)

    expect(cache.get('b'), isNull, reason: 'b was least-recently-used');
    expect(cache.get('a'), isNotNull);
    expect(cache.get('c'), isNotNull);
    expect(cache.currentBytes, lessThanOrEqualTo(300));
  });

  test('replacing a key updates the byte total', () {
    final cache = MemoryByteCache(maxBytes: 1000)
      ..put('a', _bytes(100))
      ..put('a', _bytes(50));

    expect(cache.currentBytes, 50);
  });

  test('clear empties the cache', () {
    final cache = MemoryByteCache(maxBytes: 1000)
      ..put('a', _bytes(100))
      ..clear();
    expect(cache.currentBytes, 0);
    expect(cache.get('a'), isNull);
  });
}
