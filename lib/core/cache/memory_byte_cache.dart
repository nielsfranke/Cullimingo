import 'dart:collection';
import 'dart:typed_data';

/// A simple byte-budgeted LRU cache. Keeps recently-used thumbnail bytes in RAM
/// so scrolling back to already-seen photos is instant — no disk read, no
/// re-decode (`BUILD_PLAN.md` §2, Photo-Mechanic-style). Evicts the
/// least-recently-used entries once [maxBytes] is exceeded.
class MemoryByteCache {
  /// Creates a cache holding up to [maxBytes] of values.
  MemoryByteCache({required this.maxBytes});

  /// Soft cap on the total size of cached values.
  final int maxBytes;

  final LinkedHashMap<String, Uint8List> _entries = LinkedHashMap();
  int _bytes = 0;

  /// Current total bytes held.
  int get currentBytes => _bytes;

  /// Returns the value for [key], marking it most-recently-used, or `null`.
  Uint8List? get(String key) {
    final value = _entries.remove(key);
    if (value == null) return null;
    _entries[key] = value; // re-insert at the end (most recent)
    return value;
  }

  /// Inserts [value] for [key], evicting the oldest entries past the budget.
  void put(String key, Uint8List value) {
    final previous = _entries.remove(key);
    if (previous != null) _bytes -= previous.length;

    _entries[key] = value;
    _bytes += value.length;

    while (_bytes > maxBytes && _entries.length > 1) {
      final oldest = _entries.keys.first;
      _bytes -= _entries.remove(oldest)!.length;
    }
  }

  /// Drops the entry for [key], if present.
  void remove(String key) {
    final previous = _entries.remove(key);
    if (previous != null) _bytes -= previous.length;
  }

  /// Drops everything.
  void clear() {
    _entries.clear();
    _bytes = 0;
  }
}
