import 'package:cullimingo/core/cache/memory_budget.dart';
import 'package:flutter_test/flutter_test.dart';

const int _mb = 1024 * 1024;
const int _gb = 1024 * _mb;

void main() {
  group('cacheMemoryBudgetBytes', () {
    test('scales to RAM/64 between the floor and cap', () {
      expect(cacheMemoryBudgetBytes(totalBytes: 4 * _gb), 64 * _mb);
      expect(cacheMemoryBudgetBytes(totalBytes: 8 * _gb), 128 * _mb);
      expect(cacheMemoryBudgetBytes(totalBytes: 16 * _gb), 256 * _mb);
    });

    test('caps at 256 MB on a roomy machine', () {
      expect(cacheMemoryBudgetBytes(totalBytes: 64 * _gb), 256 * _mb);
    });

    test('never drops below the 64 MB floor', () {
      expect(cacheMemoryBudgetBytes(totalBytes: 1 * _gb), 64 * _mb);
    });

    test('falls back to the floor when RAM is unknown or invalid', () {
      expect(cacheMemoryBudgetBytes(totalBytes: 0), 64 * _mb);
      expect(cacheMemoryBudgetBytes(totalBytes: -1), 64 * _mb);
    });
  });

  test('totalPhysicalMemoryBytes reports a sane value on this host', () {
    final total = totalPhysicalMemoryBytes();
    // macOS/Linux should report something; other platforms may return null.
    if (total != null) {
      expect(total, greaterThan(_gb)); // any real desktop has > 1 GB
    }
  });
}
