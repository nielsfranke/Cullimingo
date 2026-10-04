import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:cullimingo/core/cache/vips.dart';
import 'package:cullimingo/core/raw/libraw_preview_extractor.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_libraw/flutter_libraw.dart';

/// A displayable JPEG for a RAW, and how it was produced.
class RawDisplayJpeg {
  /// Wraps [bytes]; [demosaiced] marks a LibRaw render rather than the
  /// embedded preview.
  const RawDisplayJpeg(this.bytes, {required this.demosaiced});

  /// Encoded JPEG bytes.
  final Uint8List bytes;

  /// Whether [bytes] is a demosaic already sized to the requested long edge
  /// (and already upright — LibRaw applies the RAW's orientation). `false`
  /// means the embedded JPEG, untouched.
  final bool demosaiced;
}

/// The best JPEG to display or export for the RAW at [path]: one place, so the
/// preview pool, export and the legacy extractor all agree.
///
/// 1. The embedded JPEG when it is usable (the fast path, unchanged).
/// 2. Otherwise — missing, or an unusably small thumbnail like the 160×120 in
///    Nikon HLG NEFs — a LibRaw demosaic rendered to [longEdge] (0 = native
///    size), when libvips is available. [vips] is called lazily, so callers
///    that rarely need the fallback (export) only load libvips when they do.
/// 3. If the demosaic fails or LibRaw reports corrupt/undecodable data (Nikon
///    HE/HE* TicoRAW decodes "successfully" into noise), whatever embedded JPEG
///    there was — a soft thumbnail beats a cached noise frame or a blank cell.
///
/// Returns `null` only when there is nothing at all to show. [quality] is the
/// demosaic's JPEG Q (libvips' default when null).
///
/// [cache], when given, keeps the last demosaiced bitmap so another tier of
/// the same file is re-encoded from it instead of demosaiced again (GitHub
/// #7). [onDemosaic] is called just before a real LibRaw demosaic starts (not
/// on a cache hit) — the preview pool uses it to give that job the long
/// watchdog budget (GitHub #5).
Future<RawDisplayJpeg?> rawDisplayJpeg(
  FlutterLibRawBindings lr,
  String path, {
  required int longEdge,
  required Vips? Function() vips,
  int? quality,
  DemosaicCache? cache,
  void Function()? onDemosaic,
}) async {
  final embedded = extractRawPreview(lr, path);
  if (embedded != null && embedded.isUsable) {
    return RawDisplayJpeg(embedded.bytes, demosaiced: false);
  }
  final v = vips();
  if (v != null) {
    final rendered = await _demosaicJpeg(
      lr,
      path,
      vips: v,
      longEdge: longEdge,
      quality: quality,
      cache: cache,
      onDemosaic: onDemosaic,
    );
    if (rendered != null) return RawDisplayJpeg(rendered, demosaiced: true);
  }
  return embedded == null
      ? null
      : RawDisplayJpeg(embedded.bytes, demosaiced: false);
}

Future<Uint8List?> _demosaicJpeg(
  FlutterLibRawBindings lr,
  String path, {
  required Vips vips,
  required int longEdge,
  int? quality,
  DemosaicCache? cache,
  void Function()? onDemosaic,
}) async {
  Uint8List? encode(Pointer<Uint8> pixels, int byteLength, int w, int h) {
    final nativeEdge = math.max(w, h);
    return vips.thumbnailRgbPointer(
      pixels,
      byteLength: byteLength,
      width: w,
      height: h,
      channels: 3,
      // Never upscale: a half-size decode smaller than the tier stays native.
      longEdge: longEdge > 0 ? math.min(longEdge, nativeEdge) : nativeEdge,
      quality: quality,
    );
  }

  final key = cache == null ? null : DemosaicKey.of(path);
  final hit = key == null ? null : cache!.lookup(key, longEdge: longEdge);
  if (hit != null) {
    // libvips needs native memory; the cached copy lives on the Dart heap so a
    // killed worker can't leak it. One memcpy is far cheaper than a demosaic.
    final length = hit.pixels.length;
    final input = malloc<Uint8>(length);
    try {
      input.asTypedList(length).setAll(0, hit.pixels);
      return encode(input, length, hit.width, hit.height);
    } finally {
      malloc.free(input);
    }
  }

  onDemosaic?.call();
  final token = _DataErrors.instance.newToken();
  CachedDemosaic? decoded;
  final jpeg = processRawBitmap<Uint8List>(
    lr,
    path,
    minLongEdge: longEdge,
    dataErrorHandler: _DataErrors.instance.callback,
    dataErrorData: Pointer<Void>.fromAddress(token),
    consume: (pixels, byteLength, width, height, channels) {
      // The pointer dies with this call, so copy now if it's worth keeping;
      // it's only stored once the decode is known not to be corrupt.
      if (key != null && channels == 3 && byteLength <= cache!.maxBytes) {
        decoded = CachedDemosaic(
          key,
          Uint8List.fromList(pixels.asTypedList(byteLength)),
          width: width,
          height: height,
          fullResolution: longEdge <= 0,
        );
      }
      return encode(pixels, byteLength, width, height);
    },
  );
  // Always collect the token, even on failure, so the set can't grow.
  final corrupt = await _DataErrors.instance.reported(token);
  if (corrupt || jpeg == null) return null;
  final keep = decoded;
  if (keep != null) cache!.store(keep);
  return jpeg;
}

/// Identifies one version of a RAW on disk: path + size + mtime, like the
/// preview cache's key (no file content is read).
@immutable
class DemosaicKey {
  /// Creates a key from its parts.
  const DemosaicKey(this.path, this.size, this.modifiedMs);

  /// The key for the file at [path] as it is now; `null` if it can't be read.
  static DemosaicKey? of(String path) {
    try {
      final stat = File(path).statSync();
      if (stat.type == FileSystemEntityType.notFound) return null;
      return DemosaicKey(path, stat.size, stat.modified.millisecondsSinceEpoch);
    } on Object {
      return null;
    }
  }

  /// Absolute path of the RAW.
  final String path;

  /// File size in bytes.
  final int size;

  /// Modification time, ms since the epoch.
  final int modifiedMs;

  @override
  bool operator ==(Object other) =>
      other is DemosaicKey &&
      other.path == path &&
      other.size == size &&
      other.modifiedMs == modifiedMs;

  @override
  int get hashCode => Object.hash(path, size, modifiedMs);
}

/// One demosaiced 8-bit RGB bitmap, as LibRaw produced it (already upright).
class CachedDemosaic {
  /// Wraps [pixels] (width × height × 3 bytes) decoded from [key].
  CachedDemosaic(
    this.key,
    this.pixels, {
    required this.width,
    required this.height,
    required this.fullResolution,
  });

  /// The file version this was decoded from.
  final DemosaicKey key;

  /// Interleaved RGB, 3 bytes per pixel.
  final Uint8List pixels;

  /// Bitmap width in pixels.
  final int width;

  /// Bitmap height in pixels.
  final int height;

  /// Whether this is a full-tier decode (never LibRaw's half-size mode), so
  /// it can serve the full tier too.
  final bool fullResolution;

  /// Whether this bitmap renders a [longEdge] request (0 = full tier) as well
  /// as a fresh decode would.
  bool covers(int longEdge) =>
      longEdge <= 0 ? fullResolution : math.max(width, height) >= longEdge;
}

/// A single-entry, short-lived cache of the last demosaic, one per preview
/// worker (GitHub #7).
///
/// The grid, loupe and full tiers each ask for the same RAW separately, and
/// for a RAW without a usable embedded JPEG each ask used to repeat
/// `open + unpack + dcraw_process` (up to a second or more on 24–45 MP). The
/// grid and loupe tiers usually share one half-size decode, so keeping that
/// bitmap a few seconds turns the second ask into a downscale.
///
/// Memory is bounded explicitly: one entry, at most [maxBytes] (bigger decodes
/// — a full-sensor 45 MP bitmap is ~135 MB — are never kept), dropped after
/// [ttl] so an idle worker holds nothing.
class DemosaicCache {
  /// Creates an empty cache.
  DemosaicCache({
    this.maxBytes = defaultMaxBytes,
    this.ttl = const Duration(seconds: 20),
  });

  /// Default size cap: a half-size decode of a ~60 MP sensor still fits.
  static const int defaultMaxBytes = 64 * 1024 * 1024;

  /// Largest bitmap kept, in bytes.
  final int maxBytes;

  /// How long an entry lives after it was stored.
  final Duration ttl;

  CachedDemosaic? _entry;
  Timer? _expiry;

  /// The path of the cached decode, if any — the pool routes later tiers of
  /// that file to this worker.
  String? get path => _entry?.key.path;

  /// The cached bitmap for [key] if it can serve [longEdge], else `null`.
  CachedDemosaic? lookup(DemosaicKey key, {required int longEdge}) {
    final entry = _entry;
    if (entry == null || entry.key != key) return null;
    return entry.covers(longEdge) ? entry : null;
  }

  /// Keeps [entry] (replacing any previous one) unless it exceeds [maxBytes].
  void store(CachedDemosaic entry) {
    if (entry.pixels.length > maxBytes) return;
    _expiry?.cancel();
    _entry = entry;
    _expiry = Timer(ttl, clear);
  }

  /// Drops the cached bitmap.
  void clear() {
    _expiry?.cancel();
    _expiry = null;
    _entry = null;
  }
}

/// Collects LibRaw data-error reports for this isolate.
///
/// LibRaw calls the handler from inside `unpack`, and some decoders (Fuji
/// compressed) call it from their OpenMP worker threads. A synchronous Dart
/// callback invoked off the isolate's thread aborts the process, so this uses
/// a [NativeCallable.listener], which is safe from any thread but delivers
/// asynchronously: the report is queued on this isolate while the decode is
/// still running and handled once the worker yields. [reported] yields to the
/// event loop, so every report queued during the decode has been handled by
/// the time it answers.
class _DataErrors {
  _DataErrors._() {
    _listener = NativeCallable<data_callbackFunction>.listener(_onError)
      ..keepIsolateAlive = false;
  }

  static final _DataErrors instance = _DataErrors._();

  late final NativeCallable<data_callbackFunction> _listener;
  final Set<int> _flagged = {};
  int _next = 0;

  data_callback get callback => _listener.nativeFunction;

  // Non-zero, so it's distinguishable from a null context pointer.
  int newToken() => ++_next;

  void _onError(Pointer<Void> data, Pointer<Uint8> file, int offset) {
    _flagged.add(data.address);
  }

  Future<bool> reported(int token) async {
    // Messages from native code are queued in FIFO order with the timer event
    // below, so anything posted during the (synchronous) decode runs first.
    await Future<void>.delayed(Duration.zero);
    return _flagged.remove(token);
  }
}
