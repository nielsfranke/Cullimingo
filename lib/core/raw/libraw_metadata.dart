import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_libraw/flutter_libraw.dart';

/// The scan-relevant metadata LibRaw can read straight from a RAW header —
/// cheap (`libraw_open_file` only, no unpack/decode). Used as a fallback for
/// container formats the pure-Dart `exif` package can't navigate (notably Fuji
/// `.RAF`, whose EXIF sits behind a proprietary wrapper).
class RawMetadata {
  /// Creates a RAW metadata record.
  const RawMetadata({
    this.capturedAt,
    this.camera,
    this.exposureTime,
  });

  /// Capture time from LibRaw's `imgother.timestamp` (unix seconds), when set.
  final DateTime? capturedAt;

  /// "Make Model" from `iparams`, deduplicated, when present.
  final String? camera;

  /// Shutter speed in seconds from `imgother.shutter`, when present.
  final double? exposureTime;
}

/// Reads [RawMetadata] for [path] using already-loaded [lr] bindings. Opens the
/// file (header parse only — no `unpack`), reads `iparams`/`imgother`, and
/// closes. Returns an empty record on any error so a stray file never breaks a
/// scan. Must run off the UI isolate (Rule 2).
RawMetadata readRawMetadata(FlutterLibRawBindings lr, String path) {
  final handle = lr.libraw_init(0);
  if (handle == nullptr) return const RawMetadata();
  final pathC = path.toNativeUtf8();
  try {
    if (lr.libraw_open_file(handle, pathC.cast<Uint8>()) != 0) {
      return const RawMetadata();
    }
    final other = lr.libraw_get_imgother(handle).ref;
    final params = lr.libraw_get_iparams(handle).ref;

    final ts = other.timestamp;
    final shutter = other.shutter;
    return RawMetadata(
      capturedAt: ts > 0
          ? DateTime.fromMillisecondsSinceEpoch(ts * 1000)
          : null,
      camera: _camera(
        _cString(params.make, 64),
        _cString(params.model, 64),
      ),
      exposureTime: shutter > 0 ? shutter : null,
    );
  } on Object {
    return const RawMetadata();
  } finally {
    malloc.free(pathC);
    lr.libraw_close(handle);
  }
}

/// Reads a fixed-size NUL-terminated C char array into a Dart string.
String _cString(Array<Uint8> arr, int maxLen) {
  final bytes = <int>[];
  for (var i = 0; i < maxLen; i++) {
    final b = arr[i];
    if (b == 0) break;
    bytes.add(b);
  }
  return String.fromCharCodes(bytes).trim();
}

/// Joins make + model the way the EXIF reader does (drop a make that the model
/// already repeats, e.g. Fuji's `X-H2S`).
String? _camera(String make, String model) {
  if (model.isEmpty) return make.isEmpty ? null : make;
  if (make.isEmpty || model.startsWith(make)) return model;
  return '$make $model';
}
