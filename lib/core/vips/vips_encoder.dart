// FFI native/Dart signature pairs read far better as named typedefs than
// inlined into every lookupFunction call.
// ignore_for_file: avoid_private_typedef_functions

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:cullimingo/core/native/bundled_libs.dart';
import 'package:cullimingo/core/vips/vips_home.dart';
import 'package:ffi/ffi.dart';

/// Where libvips lives when not bundled (dev / `flutter test`) — mirrors the
/// libraw candidate list (`BUILD_PLAN.md` §6.1).
const List<String> _candidateLibPaths = [
  '/opt/homebrew/lib/libvips.42.dylib', // Apple Silicon Homebrew
  '/usr/local/lib/libvips.42.dylib', // Intel Homebrew
  '/usr/lib/x86_64-linux-gnu/libvips.so.42', // Debian/Ubuntu
  '/usr/lib/libvips.so.42',
];

/// `VipsForeignHeifCompression.VIPS_FOREIGN_HEIF_COMPRESSION_AV1` — what makes
/// a HEIF container an AVIF file.
const int _heifCompressionAv1 = 4;

// vips_image_new_from_memory_copy(data, size, width, height, bands, format)
typedef _NewFromMemoryN =
    Pointer<Void> Function(Pointer<Uint8>, Size, Int, Int, Int, Int);
typedef _NewFromMemoryD =
    Pointer<Void> Function(Pointer<Uint8>, int, int, int, int, int);

// vips_image_set_blob_copy(image, name, data, length)
typedef _SetBlobN =
    Void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint8>, Size);
typedef _SetBlobD =
    void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint8>, int);

// vips_webpsave_buffer(image, &buf, &len, "Q", q, NULL)
typedef _WebpSaveN =
    Int Function(
      Pointer<Void>,
      Pointer<Pointer<Void>>,
      Pointer<Size>,
      VarArgs<(Pointer<Utf8>, Int, Pointer<Utf8>)>,
    );
typedef _WebpSaveD =
    int Function(
      Pointer<Void>,
      Pointer<Pointer<Void>>,
      Pointer<Size>,
      Pointer<Utf8>,
      int,
      Pointer<Utf8>,
    );

// vips_heifsave_buffer(image, &buf, &len, "Q", q, "compression", c, NULL)
typedef _HeifSaveN =
    Int Function(
      Pointer<Void>,
      Pointer<Pointer<Void>>,
      Pointer<Size>,
      VarArgs<(Pointer<Utf8>, Int, Pointer<Utf8>, Int, Pointer<Utf8>)>,
    );
typedef _HeifSaveD =
    int Function(
      Pointer<Void>,
      Pointer<Pointer<Void>>,
      Pointer<Size>,
      Pointer<Utf8>,
      int,
      Pointer<Utf8>,
      int,
      Pointer<Utf8>,
    );

typedef _InitN = Int Function(Pointer<Utf8>);
typedef _InitD = int Function(Pointer<Utf8>);
typedef _ErrorBufferN = Pointer<Utf8> Function();
typedef _ErrorBufferD = Pointer<Utf8> Function();
typedef _VoidPtrN = Void Function(Pointer<Void>);
typedef _VoidPtrD = void Function(Pointer<Void>);
typedef _VoidN = Void Function();
typedef _VoidD = void Function();

/// The alternative-format encoder behind the export pipeline: hands processed
/// RGB pixels to **libvips** to save as WebP or AVIF (`BUILD_PLAN.md` §2 —
/// the "libvips as the scale path" slot; JPEG stays on the `image` package,
/// whose byte-splicing metadata path is proven).
///
/// Hand-written FFI over five libvips calls — full ffigen over the vips
/// headers would generate thousands of bindings for no gain. Loads the
/// bundled dylib first, then Homebrew/system paths, like libraw.
///
/// One instance per isolate ([instance] caches). `vips_init` is not
/// thread-safe on its *first* call, so the UI isolate probes [available]
/// before export workers spawn; their init calls then hit vips' started
/// flag and no-op.
class VipsEncoder {
  VipsEncoder._(
    this._newFromMemory,
    this._setBlob,
    this._webpSave,
    this._heifSave,
    this._errorBuffer,
    this._errorClear,
    this._gFree,
    this._unref,
  );

  static VipsEncoder? _cached;
  static bool _resolved = false;

  /// The per-isolate encoder, or null when libvips can't be loaded (then the
  /// export UI hides the WebP/AVIF choices).
  static VipsEncoder? instance() {
    if (_resolved) return _cached;
    _resolved = true;
    final bundled = bundledNativeLib('libvips.');
    final path =
        bundled ??
        _candidateLibPaths.where((p) => File(p).existsSync()).firstOrNull;
    if (path == null) return null;
    // Only effective when this is the process's first vips_init (standalone
    // probes, tests); in the app, Vips.warmUpProcess already did both the
    // env setup and the module-discovering init. See pointVipsHomeAtBundle.
    if (bundled != null) pointVipsHomeAtBundle(bundled);
    try {
      final lib = DynamicLibrary.open(path);
      final init = lib.lookupFunction<_InitN, _InitD>('vips_init');
      final argv0 = 'cullimingo'.toNativeUtf8();
      final ok = init(argv0);
      calloc.free(argv0);
      if (ok != 0) return null;
      return _cached = VipsEncoder._(
        lib.lookupFunction<_NewFromMemoryN, _NewFromMemoryD>(
          'vips_image_new_from_memory_copy',
        ),
        lib.lookupFunction<_SetBlobN, _SetBlobD>('vips_image_set_blob_copy'),
        lib.lookupFunction<_WebpSaveN, _WebpSaveD>('vips_webpsave_buffer'),
        lib.lookupFunction<_HeifSaveN, _HeifSaveD>('vips_heifsave_buffer'),
        lib.lookupFunction<_ErrorBufferN, _ErrorBufferD>('vips_error_buffer'),
        lib.lookupFunction<_VoidN, _VoidD>('vips_error_clear'),
        lib.lookupFunction<_VoidPtrN, _VoidPtrD>('g_free'),
        lib.lookupFunction<_VoidPtrN, _VoidPtrD>('g_object_unref'),
      );
    } on Object {
      return null;
    }
  }

  /// Whether libvips is loadable here — the export dialog's probe. Calling it
  /// on the UI isolate also performs the one thread-sensitive `vips_init`.
  static bool get available => instance() != null;

  bool? _avifProbed;

  /// Whether AVIF actually encodes here. Unlike WebP (linked into libvips),
  /// HEIF is a *runtime module* (`vips-modules-x.y/vips-heif.dylib`) that a
  /// bundled app may not carry — so probe with a real 1×1 encode (cached)
  /// instead of trusting the symbol, and the dialog hides AVIF where it
  /// would fail.
  bool get supportsAvif => _avifProbed ??=
      encodeRgb(
        rgb: Uint8List(3),
        width: 1,
        height: 1,
        quality: 30,
        avif: true,
      ) !=
      null;

  final _NewFromMemoryD _newFromMemory;
  final _SetBlobD _setBlob;
  final _WebpSaveD _webpSave;
  final _HeifSaveD _heifSave;
  final _ErrorBufferD _errorBuffer;
  final void Function() _errorClear;
  final void Function(Pointer<Void>) _gFree;
  final void Function(Pointer<Void>) _unref;

  /// Encodes 8-bit interleaved RGB pixels as WebP ([avif] false) or AVIF, at
  /// [quality] 1–100, embedding [xmp] (a full XMP packet) when given. Returns
  /// null on any libvips error (the export records it as unreadable).
  Uint8List? encodeRgb({
    required Uint8List rgb,
    required int width,
    required int height,
    required int quality,
    bool avif = false,
    String? xmp,
  }) {
    if (rgb.length != width * height * 3) return null;
    final pixels = calloc<Uint8>(rgb.length);
    pixels.asTypedList(rgb.length).setAll(0, rgb);
    // 0 = VIPS_FORMAT_UCHAR.
    final image = _newFromMemory(pixels, rgb.length, width, height, 3, 0);
    if (image == nullptr) {
      calloc.free(pixels);
      _clearError();
      return null;
    }
    Pointer<Utf8>? xmpName;
    Pointer<Uint8>? xmpData;
    if (xmp != null && xmp.isNotEmpty) {
      final bytes = utf8.encode(xmp);
      xmpName = 'xmp-data'.toNativeUtf8();
      xmpData = calloc<Uint8>(bytes.length);
      xmpData.asTypedList(bytes.length).setAll(0, bytes);
      _setBlob(image, xmpName, xmpData, bytes.length);
    }

    final outBuf = calloc<Pointer<Void>>();
    final outLen = calloc<Size>();
    final q = 'Q'.toNativeUtf8();
    final compression = 'compression'.toNativeUtf8();
    try {
      final failed = avif
          ? _heifSave(
              image,
              outBuf,
              outLen,
              q,
              quality,
              compression,
              _heifCompressionAv1,
              nullptr,
            )
          : _webpSave(image, outBuf, outLen, q, quality, nullptr);
      if (failed != 0) {
        _clearError();
        return null;
      }
      final out = Uint8List.fromList(
        outBuf.value.cast<Uint8>().asTypedList(outLen.value),
      );
      _gFree(outBuf.value);
      return out;
    } finally {
      _unref(image);
      calloc
        ..free(pixels)
        ..free(outBuf)
        ..free(outLen)
        ..free(q)
        ..free(compression);
      if (xmpName != null) calloc.free(xmpName);
      if (xmpData != null) calloc.free(xmpData);
    }
  }

  /// The pending libvips error text (for logs), clearing it.
  void _clearError() {
    _errorBuffer();
    _errorClear();
  }
}
