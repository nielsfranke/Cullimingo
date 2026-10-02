import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cullimingo/core/cache/vips.dart';
import 'package:cullimingo/core/native/bundled_libs.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/core/raw/raw_display_jpeg.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_libraw/flutter_libraw.dart';

/// Candidate locations for the native `libraw` dynamic library — the
/// Homebrew/system paths used in development (`brew install libraw`). A packaged
/// macOS app ships its own copy and is preferred over these (see §6.1 /
/// [bundledNativeLib]).
const List<String> _candidateLibPaths = [
  '/opt/homebrew/lib/libraw.dylib', // Apple Silicon Homebrew
  '/opt/homebrew/lib/libraw_r.dylib',
  '/usr/local/lib/libraw.dylib', // Intel Homebrew
  '/usr/lib/x86_64-linux-gnu/libraw.so', // Debian/Ubuntu
  '/usr/lib/libraw.so',
];

/// LibRaw image type for an embedded JPEG preview (`LibRaw_image_formats`).
const int _librawImageJpeg = 1;

/// LibRaw image type for a decoded RGB bitmap (`LibRaw_image_formats`).
const int _librawImageBitmap = 2;

/// Offset of the flexible `data[]` member in `libraw_processed_image_t`
/// (type:4 + 4×ushort:8 + data_size:4). Stable across the LibRaw ABI.
const int _processedDataOffset = 16;

/// Embedded previews below this size are too small for a useful culling view.
const int _minUsablePreviewLongEdge = 512;

/// Extracts the **embedded full-res JPEG preview** from a RAW file via LibRaw
/// (`BUILD_PLAN.md` §6.1), then downscales it for the grid. Runs the whole FFI
/// sequence on a one-off background isolate so the UI never blocks.
class LibRawPreviewExtractor implements PreviewExtractor {
  /// Creates the extractor. [libraryPath] overrides dylib discovery (tests).
  const LibRawPreviewExtractor({this.libraryPath});

  /// Explicit path to the libraw dynamic library, or null to auto-discover.
  final String? libraryPath;

  /// Resolves the libraw dylib path, or null if none is present. Prefers the
  /// copy bundled in the packaged app, falling back to Homebrew/system paths.
  static String? resolveLibraryPath() {
    final bundled = bundledNativeLib('libraw.');
    if (bundled != null) return bundled;
    for (final path in _candidateLibPaths) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  @override
  Future<Uint8List?> thumbnail(
    String path, {
    int longEdge = 512,
    CancelToken? cancel,
    JobPriority priority = JobPriority.visible,
  }) async {
    final lib = libraryPath ?? resolveLibraryPath();
    if (lib == null || !File(path).existsSync()) return null;
    return Isolate.run(() => _extract(lib, path));
  }

  static Future<Uint8List?> _extract(String libPath, String path) async {
    final DynamicLibrary dylib;
    try {
      dylib = DynamicLibrary.open(libPath);
    } on Object {
      return null;
    }
    final raw = await rawDisplayJpeg(
      FlutterLibRawBindings(dylib),
      path,
      longEdge: 0,
      vips: Vips.tryLoad,
    );
    return raw?.bytes;
  }
}

/// An embedded JPEG plus the dimensions needed to judge whether it is useful.
class EmbeddedRawPreview {
  /// Creates embedded preview metadata owned by Dart.
  const EmbeddedRawPreview({
    required this.bytes,
    required this.width,
    required this.height,
  });

  /// Encoded JPEG bytes.
  final Uint8List bytes;

  /// Embedded JPEG width.
  final int width;

  /// Embedded JPEG height.
  final int height;

  /// Whether this preview is useful enough to retain the normal fast path.
  ///
  /// Unknown dimensions preserve the old embedded-preview behaviour. The
  /// fallback is deliberately limited to objectively tiny previews rather
  /// than demosaicing cameras whose normal preview is merely smaller than a
  /// high-resolution loupe tier.
  bool get isUsable {
    if (width <= 0 || height <= 0) return true;
    final previewEdge = width > height ? width : height;
    return previewEdge >= _minUsablePreviewLongEdge;
  }
}

/// Reads dimensions from a JPEG's SOF marker without decoding its pixels.
({int width, int height})? jpegDimensions(Uint8List jpeg) {
  if (jpeg.length < 4 || jpeg[0] != 0xff || jpeg[1] != 0xd8) return null;

  var offset = 2;
  while (offset < jpeg.length) {
    while (offset < jpeg.length && jpeg[offset] != 0xff) {
      offset++;
    }
    while (offset < jpeg.length && jpeg[offset] == 0xff) {
      offset++;
    }
    if (offset >= jpeg.length) return null;

    final marker = jpeg[offset++];
    if (marker == 0xd9 || marker == 0xda) return null;
    if (marker == 0xd8 ||
        marker == 0x01 ||
        (marker >= 0xd0 && marker <= 0xd7)) {
      continue;
    }
    if (offset + 1 >= jpeg.length) return null;

    final segmentLength = (jpeg[offset] << 8) | jpeg[offset + 1];
    if (segmentLength < 2 || offset + segmentLength > jpeg.length) return null;
    if (_isStartOfFrame(marker) && segmentLength >= 7) {
      final height = (jpeg[offset + 3] << 8) | jpeg[offset + 4];
      final width = (jpeg[offset + 5] << 8) | jpeg[offset + 6];
      if (width > 0 && height > 0) return (width: width, height: height);
      return null;
    }
    offset += segmentLength;
  }
  return null;
}

bool _isStartOfFrame(int marker) =>
    marker >= 0xc0 &&
    marker <= 0xcf &&
    marker != 0xc4 &&
    marker != 0xc8 &&
    marker != 0xcc;

/// Runs the LibRaw FFI sequence using already-loaded [lr] bindings and returns
/// the **raw embedded JPEG preview** with its dimensions — no Dart
/// decode/resize/re-encode (the pure-Dart `image` codecs are slow). Exposed so
/// workers can load libraw **once** and reuse it across files.
///
/// This is the embedded JPEG only, which may be a 160×120 thumbnail (or
/// absent). Anything that *displays* or *exports* the RAW must go through
/// [rawDisplayJpeg] instead so it gets the demosaic fallback; read this
/// directly only for the embedded JPEG's EXIF.
EmbeddedRawPreview? extractRawPreview(FlutterLibRawBindings lr, String path) {
  final handle = lr.libraw_init(0);
  if (handle == nullptr) return null;

  final pathC = path.toNativeUtf8();
  final errc = calloc<Int>();
  Pointer<libraw_processed_image_t> processed = nullptr;
  try {
    if (lr.libraw_open_file(handle, pathC.cast<Uint8>()) != 0) return null;
    if (lr.libraw_unpack_thumb(handle) != 0) return null;

    processed = lr.libraw_dcraw_make_mem_thumb(handle, errc);
    if (processed == nullptr || errc.value != 0) return null;

    final image = processed.ref;
    if (image.type != _librawImageJpeg || image.data_size <= 0) return null;

    final dataPtr = Pointer<Uint8>.fromAddress(
      processed.address + _processedDataOffset,
    );
    final bytes = Uint8List.fromList(dataPtr.asTypedList(image.data_size));
    final dimensions = jpegDimensions(bytes);
    return EmbeddedRawPreview(
      bytes: bytes,
      width: image.width > 0 ? image.width : dimensions?.width ?? 0,
      height: image.height > 0 ? image.height : dimensions?.height ?? 0,
    );
  } on Object {
    return null;
  } finally {
    if (processed != nullptr) lr.libraw_dcraw_clear_mem(processed);
    calloc.free(errc);
    malloc.free(pathC);
    lr.libraw_close(handle);
  }
}

/// Synchronous consumer of an 8-bit interleaved LibRaw bitmap.
typedef RawBitmapConsumer<T> =
    T? Function(
      Pointer<Uint8> pixels,
      int byteLength,
      int width,
      int height,
      int channels,
    );

/// Fully decodes [path] and lends its 8-bit RGB buffer to [consume].
///
/// [minLongEdge] is the smallest long edge the caller needs (0 = full
/// resolution). When half of the sensor still covers it, LibRaw's
/// half-resolution mode is used: about one quarter of the pixels and memory,
/// which keeps several concurrent preview workers from exhausting RAM. If
/// half-size mode can't be set safely on the loaded runtime and a downscaled
/// result was requested, this returns `null` rather than risk a full-sensor
/// demosaic (several GB transient across workers). Camera white balance is
/// applied and output is converted to sRGB; this is a practical SDR culling
/// preview, not a colour-managed rendering of an HLG master.
///
/// [dataErrorHandler] is registered with `libraw_set_dataerror_handler`, with
/// [dataErrorData] as its context. LibRaw reports corrupt or undecodable data
/// (e.g. Nikon HE/HE* TicoRAW) only through that callback — unpack and
/// process still return success and produce noise — so callers must treat a
/// reported error as a failed decode. It can be invoked from LibRaw's OpenMP
/// worker threads, so it must be thread-safe (see `rawDisplayJpeg`).
///
/// The pointer is valid only during the synchronous [consume] call. Lending
/// it directly to libvips avoids two full-size bitmap copies per worker.
T? processRawBitmap<T>(
  FlutterLibRawBindings lr,
  String path, {
  required RawBitmapConsumer<T> consume,
  int minLongEdge = 0,
  data_callback? dataErrorHandler,
  Pointer<Void>? dataErrorData,
}) {
  final handle = lr.libraw_init(0);
  if (handle == nullptr) return null;

  final pathC = path.toNativeUtf8();
  final errc = calloc<Int>();
  Pointer<libraw_processed_image_t> processed = nullptr;
  try {
    if (dataErrorHandler != null) {
      lr.libraw_set_dataerror_handler(
        handle,
        dataErrorHandler,
        dataErrorData ?? nullptr,
      );
    }
    if (lr.libraw_open_file(handle, pathC.cast<Uint8>()) != 0) return null;

    // Use the stable C accessors instead of writing `use_camera_wb` through
    // libraw_data_t. The bindings target 0.21.2, while a system LibRaw 0.22 can
    // move `params` inside that outer struct; direct access then silently sets
    // the wrong field and falls back to a very warm daylight white balance.
    final cameraMultipliers = [
      for (var channel = 0; channel < 4; channel++)
        lr.libraw_get_cam_mul(handle, channel),
    ];
    if (cameraMultipliers.take(3).every((value) => value > 0)) {
      if (cameraMultipliers[3] <= 0) {
        cameraMultipliers[3] = cameraMultipliers[1];
      }
      for (var channel = 0; channel < 4; channel++) {
        lr.libraw_set_user_mul(handle, channel, cameraMultipliers[channel]);
      }
    }

    // Before half_size is set, iwidth/iheight are the full output size.
    final sensorEdge = math.max(
      lr.libraw_get_iwidth(handle),
      lr.libraw_get_iheight(handle),
    );
    final wantHalf = minLongEdge > 0 && sensorEdge ~/ 2 >= minLongEdge;
    if (wantHalf && !setLibRawHalfSize(lr, handle, enabled: true)) {
      return null;
    }
    lr
      ..libraw_set_demosaic(handle, 0) // fast linear interpolation
      ..libraw_set_output_color(handle, 1) // sRGB
      ..libraw_set_output_bps(handle, 8);

    if (lr.libraw_unpack(handle) != 0) return null;
    if (lr.libraw_dcraw_process(handle) != 0) return null;

    processed = lr.libraw_dcraw_make_mem_image(handle, errc);
    if (processed == nullptr || errc.value != 0) return null;

    final image = processed.ref;
    if (image.type != _librawImageBitmap ||
        image.bits != 8 ||
        image.colors != 3 ||
        image.width <= 0 ||
        image.height <= 0 ||
        image.data_size <= 0) {
      return null;
    }

    final expected = image.width * image.height * image.colors;
    if (image.data_size < expected) return null;
    final dataPtr = Pointer<Uint8>.fromAddress(
      processed.address + _processedDataOffset,
    );
    return consume(
      dataPtr,
      expected,
      image.width,
      image.height,
      image.colors,
    );
  } on Object {
    return null;
  } finally {
    if (processed != nullptr) lr.libraw_dcraw_clear_mem(processed);
    calloc.free(errc);
    malloc.free(pathC);
    lr.libraw_close(handle);
  }
}

/// Byte offset of `params.half_size` inside `libraw_data_t` for each loaded
/// libraw (keyed by its bindings), found by [_probeHalfSizeOffset]. `-1`
/// caches a failed probe.
final Expando<int> _halfSizeOffsets = Expando('libraw half_size offset');

/// Sets LibRaw's `half_size` output parameter on [handle].
///
/// LibRaw has no C setter for it, and the generated struct bindings match the
/// 0.21 ABI only: 0.22 grew the structs before `params`, so writing through
/// `handle.ref.params` there hits the wrong field (and the macOS release ships
/// Homebrew's 0.22). The head of `libraw_output_params_t` itself — `bright`,
/// `threshold`, `half_size`, … `output_color` — is unchanged across 0.21/0.22,
/// so this locates it on the running library through two C setters that *do*
/// exist (`libraw_set_bright`, `libraw_set_output_color`) and writes
/// `half_size` relative to them. Returns `false` when the layout can't be
/// confirmed; nothing is written then.
bool setLibRawHalfSize(
  FlutterLibRawBindings lr,
  Pointer<libraw_data_t> handle, {
  required bool enabled,
}) {
  var offset = _halfSizeOffsets[lr];
  if (offset == null) {
    offset = _probeHalfSizeOffset(lr, handle) ?? -1;
    _halfSizeOffsets[lr] = offset;
  }
  if (offset < 0) return false;
  (handle.cast<Uint8>() + offset).cast<Int32>().value = enabled ? 1 : 0;
  return true;
}

// Offsets within libraw_output_params_t, stable since LibRaw 0.18:
// float bright; float threshold; int half_size; int four_color_rgb;
// int highlight; int use_auto_wb; int use_camera_wb; int use_camera_matrix;
// int output_color.
const int _halfSizeFromBright = 8;
const int _outputColorFromBright = 32;

int? _probeHalfSizeOffset(
  FlutterLibRawBindings lr,
  Pointer<libraw_data_t> handle,
) {
  // libraw_data_t is embedded in the larger LibRaw object, and a newer ABI
  // only grows it, so the 0.21 size is always safe to read — and `params` sits
  // well inside it (the big colour/rawdata blocks follow).
  final size = sizeOf<libraw_data_t>();
  final view = ByteData.sublistView(handle.cast<Uint8>().asTypedList(size));

  Set<int> floatsEqual(double v, Iterable<int> where) => {
    for (final o in where)
      if (view.getFloat32(o, Endian.host) == v) o,
  };
  Set<int> intsEqual(int v, Iterable<int> where) => {
    for (final o in where)
      if (o + 4 <= size && view.getInt32(o, Endian.host) == v) o,
  };

  try {
    final aligned = [for (var o = 0; o + 4 <= size; o += 4) o];
    lr.libraw_set_bright(handle, 1.5);
    var bright = floatsEqual(1.5, aligned);
    lr.libraw_set_bright(handle, 2.75);
    bright = floatsEqual(2.75, bright);

    final colourAt = bright.map((o) => o + _outputColorFromBright);
    lr.libraw_set_output_color(handle, 4);
    var colour = intsEqual(4, colourAt);
    lr.libraw_set_output_color(handle, 5);
    colour = intsEqual(5, colour);

    if (colour.length != 1) return null;
    return colour.single - _outputColorFromBright + _halfSizeFromBright;
  } finally {
    // Restore LibRaw's defaults (the caller sets output_color itself anyway).
    lr
      ..libraw_set_bright(handle, 1)
      ..libraw_set_output_color(handle, 1);
  }
}
