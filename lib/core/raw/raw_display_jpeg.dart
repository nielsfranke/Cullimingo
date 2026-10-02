import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cullimingo/core/cache/vips.dart';
import 'package:cullimingo/core/raw/libraw_preview_extractor.dart';
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
Future<RawDisplayJpeg?> rawDisplayJpeg(
  FlutterLibRawBindings lr,
  String path, {
  required int longEdge,
  required Vips? Function() vips,
  int? quality,
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
}) async {
  final token = _DataErrors.instance.newToken();
  final jpeg = processRawBitmap<Uint8List>(
    lr,
    path,
    minLongEdge: longEdge,
    dataErrorHandler: _DataErrors.instance.callback,
    dataErrorData: Pointer<Void>.fromAddress(token),
    consume: (pixels, byteLength, width, height, channels) {
      final nativeEdge = math.max(width, height);
      // Never upscale: a half-size decode smaller than the tier stays native.
      final targetEdge = longEdge > 0
          ? math.min(longEdge, nativeEdge)
          : nativeEdge;
      return vips.thumbnailRgbPointer(
        pixels,
        byteLength: byteLength,
        width: width,
        height: height,
        channels: channels,
        longEdge: targetEdge,
        quality: quality,
      );
    },
  );
  // Always collect the token, even on failure, so the set can't grow.
  final corrupt = await _DataErrors.instance.reported(token);
  return corrupt ? null : jpeg;
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
