import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cullimingo/core/cache/file_signature.dart';
import 'package:cullimingo/core/cache/memory_budget.dart';
import 'package:cullimingo/core/cache/memory_byte_cache.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Disk-cache ceiling (~2 GB). The cache survives across sessions for instant
/// re-opens, but is pruned to this on startup (oldest first) so it can't fill
/// the disk over time.
const int _defaultDiskBudget = 2 * 1024 * 1024 * 1024;

/// Preview size tiers (`BUILD_PLAN.md` §2/§3): a tiny grid thumbnail and a
/// screen-res loupe preview, each cached on disk.
enum PreviewTier {
  /// Grid thumbnail (~1024px long edge) — large enough to stay sharp at the
  /// grid's max zoom (Photo-Mechanic-style), small enough to extract fast.
  thumb(1024),

  /// Loupe / fullscreen preview. The default long edge is a floor — the actual
  /// size scales to the display's pixel long edge (see `loupeLongEdge` in the
  /// `PreviewCache` constructor and `display_metrics.dart`).
  loupe(2048),

  /// The full-resolution source for pixel-peeping at 100% zoom: the original
  /// bitmap, or a RAW's full embedded JPEG, with no downscale (long edge 0 is
  /// the "don't resize" sentinel). Lazily loaded on zoom and RAM-cached only —
  /// these are large and trivially re-derived, so they never touch the disk
  /// cache (which would blow its budget).
  full(0);

  const PreviewTier(this.longEdge);

  /// Default / fallback target long-edge size in pixels (0 = no downscale).
  final int longEdge;

  /// Whether this tier is persisted to the on-disk cache (all but [full]).
  bool get diskCached => this != PreviewTier.full;
}

/// Two-tier on-disk preview cache: decode-once, reuse forever (across
/// sessions), keyed by [fileSignature] + tier. Wraps a [PreviewExtractor] so
/// the heavy decode only happens on a cache miss (`BUILD_PLAN.md` §3, Phase 2).
class PreviewCache {
  /// Creates a cache backed by [extractor]. In tests pass [cacheDirProvider]
  /// to point the cache at a temp directory.
  PreviewCache({
    required this.extractor,
    Future<Directory> Function()? cacheDirProvider,
    MemoryByteCache? memory,
    int? thumbLongEdge,
    int? loupeLongEdge,
    int? ramBudgetBytes,
  }) : _cacheDirProvider = cacheDirProvider ?? _defaultCacheDir,
       _thumbLongEdge = thumbLongEdge ?? PreviewTier.thumb.longEdge,
       _loupeLongEdge = loupeLongEdge ?? PreviewTier.loupe.longEdge,
       // Photo-Mechanic-style trade of RAM for instant scroll-back. The budget
       // comes from the active performance preset (else scales to the machine
       // via memory_budget.dart) so a low-end box doesn't swap.
       _memory =
           memory ??
           MemoryByteCache(
             maxBytes: ramBudgetBytes ?? cacheMemoryBudgetBytes(),
           );

  /// The extractor invoked on a cache miss.
  final PreviewExtractor extractor;

  final Future<Directory> Function() _cacheDirProvider;
  final MemoryByteCache _memory;
  final Map<PreviewTier, Directory> _tierDirs = {};

  /// Grid-thumbnail source resolution, from the active performance preset. It's
  /// in the cache key, so changing it invalidates old (wrong-size) thumbnails
  /// naturally.
  final int _thumbLongEdge;

  /// Loupe-preview source resolution, scaled to the display (see
  /// `display_metrics.dart`). Also in the cache key, so moving to a bigger
  /// monitor next session re-extracts at the new size instead of upscaling.
  final int _loupeLongEdge;

  int _longEdgeFor(PreviewTier tier) => switch (tier) {
    PreviewTier.thumb => _thumbLongEdge,
    PreviewTier.loupe => _loupeLongEdge,
    PreviewTier.full => tier.longEdge, // 0 = extract at native size
  };

  static Future<Directory> _defaultCacheDir() async {
    final base = await getApplicationCacheDirectory();
    return Directory(p.join(base.path, 'previews'));
  }

  /// Returns cached preview bytes for [path] at [tier], rendering and storing
  /// them on a miss. Returns `null` if no preview can be produced (e.g. the
  /// RAW path before LibRaw is wired).
  Future<Uint8List?> get(
    String path,
    PreviewTier tier, {
    CancelToken? cancel,
    JobPriority priority = JobPriority.visible,
  }) async {
    // 1. RAM — instant, no I/O or decode (scroll-back). Always served, even if
    // the request was cancelled: it's free and may as well render.
    final memKey = '${tier.name}:$path';
    final cached = _memory.get(memKey);
    if (cached != null) return cached;
    if (cancel?.isCancelled ?? false) return null;

    final file = File(path);
    // One async stat covers the existence check and the cache key below. It
    // must not be a sync call: the original may live on slow removable media
    // (SD card), and this method runs on the UI isolate — a blocking syscall
    // here is exactly what janks the grid scroll (§0.6).
    // ignore: avoid_slow_async_io
    final stat = await file.stat();
    if (stat.type == FileSystemEntityType.notFound) return null;

    final longEdge = _longEdgeFor(tier);

    // The full tier skips the disk cache (large + trivially re-derived):
    // extract straight from the pool and only RAM-cache the result.
    if (!tier.diskCached) {
      final bytes = await extractor.thumbnail(
        path,
        longEdge: longEdge,
        cancel: cancel,
        priority: priority,
      );
      if (bytes != null) _memory.put(memKey, bytes);
      return bytes;
    }

    // 2. Disk — survives across sessions. The size is in the key so changing a
    // tier's resolution naturally invalidates its old (wrong-size) cache files.
    final key = await fileSignature(
      file,
      salt: '${tier.name}$longEdge',
      stat: stat,
    );
    final dir = await _tierDir(tier);
    final cacheFile = File(p.join(dir.path, '$key.jpg'));

    Uint8List? bytes;
    // Also deliberately async, like the stat above.
    // ignore: avoid_slow_async_io
    if (await cacheFile.exists()) {
      bytes = await cacheFile.readAsBytes();
    } else {
      // 3. Extract on the pool (skipped if still cancelled), then persist.
      bytes = await extractor.thumbnail(
        path,
        longEdge: longEdge,
        cancel: cancel,
        priority: priority,
      );
      // No flush: previews are reproducible (re-extracted on a miss), so we
      // don't need fsync durability here — and flushing every thumbnail
      // amplifies I/O badly on a cold scan of a large folder.
      if (bytes != null) await cacheFile.writeAsBytes(bytes);
    }

    if (bytes != null) _memory.put(memKey, bytes);
    return bytes;
  }

  /// Convenience for the grid thumbnail tier.
  Future<Uint8List?> thumbnail(
    String path, {
    CancelToken? cancel,
    JobPriority priority = JobPriority.visible,
  }) => get(path, PreviewTier.thumb, cancel: cancel, priority: priority);

  /// Prunes the on-disk cache down to [maxBytes], deleting the oldest files
  /// first. Runs the stat/delete sweep in a one-off isolate so the UI never
  /// blocks. Call once at startup.
  Future<void> pruneToBudget({int maxBytes = _defaultDiskBudget}) async {
    final dir = await _cacheDirProvider();
    if (!dir.existsSync()) return;
    await Isolate.run(() => _pruneDir(dir.path, maxBytes));
  }

  /// Drops the in-RAM previews for [path] (all tiers) so the next request
  /// re-reads from disk / re-decodes. Used after a rotate rewrites a JPEG's
  /// embedded EXIF orientation, which changes the baked preview.
  void evict(String path) {
    for (final tier in PreviewTier.values) {
      _memory.remove('${tier.name}:$path');
    }
  }

  /// Empties the cache — RAM and disk. Backs the toolbar's clear-cache action.
  Future<void> clear() async {
    _memory.clear();
    _tierDirs.clear();
    final dir = await _cacheDirProvider();
    if (dir.existsSync()) {
      await Isolate.run(() => Directory(dir.path).deleteSync(recursive: true));
    }
  }

  // Runs in a background isolate: total the cache, then delete oldest-first
  // (by mtime) until it fits the budget.
  static void _pruneDir(String path, int maxBytes) {
    final dir = Directory(path);
    if (!dir.existsSync()) return;
    final files = dir.listSync(recursive: true).whereType<File>();
    final entries = <(File, int, DateTime)>[];
    var total = 0;
    for (final f in files) {
      final st = f.statSync();
      total += st.size;
      entries.add((f, st.size, st.modified));
    }
    if (total <= maxBytes) return;
    entries.sort((a, b) => a.$3.compareTo(b.$3)); // oldest first
    for (final (file, size, _) in entries) {
      if (total <= maxBytes) break;
      try {
        file.deleteSync();
        total -= size;
      } on Object {
        // A file we couldn't delete (in use / gone) — skip it.
      }
    }
  }

  Future<Directory> _tierDir(PreviewTier tier) async {
    final cached = _tierDirs[tier];
    if (cached != null) return cached;
    final base = await _cacheDirProvider();
    final dir = Directory(p.join(base.path, tier.name));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _tierDirs[tier] = dir;
  }
}
