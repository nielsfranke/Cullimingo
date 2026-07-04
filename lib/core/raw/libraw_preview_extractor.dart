import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cullimingo/core/native/bundled_libs.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
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

/// Offset of the flexible `data[]` member in `libraw_processed_image_t`
/// (type:4 + 4×ushort:8 + data_size:4). Stable across the LibRaw ABI.
const int _processedDataOffset = 16;

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

  static Uint8List? _extract(String libPath, String path) {
    final DynamicLibrary dylib;
    try {
      dylib = DynamicLibrary.open(libPath);
    } on Object {
      return null;
    }
    return extractRawThumbnail(FlutterLibRawBindings(dylib), path);
  }
}

/// Runs the LibRaw FFI sequence using already-loaded [lr] bindings and returns
/// the **raw embedded JPEG preview bytes** — no Dart decode/resize/re-encode
/// (the pure-Dart `image` codecs are slow). The native engine codec downsamples
/// it to display size via `cacheWidth` at paint time. Exposed so the preview
/// pool can load libraw **once per worker** and reuse it across thumbnails.
Uint8List? extractRawThumbnail(FlutterLibRawBindings lr, String path) {
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
    return Uint8List.fromList(dataPtr.asTypedList(image.data_size));
  } on Object {
    return null;
  } finally {
    if (processed != nullptr) lr.libraw_dcraw_clear_mem(processed);
    calloc.free(errc);
    malloc.free(pathC);
    lr.libraw_close(handle);
  }
}
