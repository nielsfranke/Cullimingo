// FFI signature typedefs are each used once (by lookupFunction) but reading the
// long VarArgs types inline would be far worse.
// ignore_for_file: avoid_private_typedef_functions
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:cullimingo/core/native/bundled_libs.dart';
import 'package:cullimingo/core/vips/vips_home.dart';
import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as img;

// vips_init(const char*) -> int
typedef _InitNative = Int Function(Pointer<Utf8>);
typedef _InitDart = int Function(Pointer<Utf8>);

// vips_thumbnail_buffer(void* buf, size_t len, VipsImage** out, int width, ...)
// We pass the "height" option so the result fits within longEdge×longEdge
// regardless of orientation. vips auto-rotates from EXIF by default.
typedef _ThumbNative =
    Int Function(
      Pointer<Void>,
      Size,
      Pointer<Pointer<Void>>,
      Int,
      VarArgs<(Pointer<Utf8>, Int, Pointer<Void>)>,
    );
typedef _ThumbDart =
    int Function(
      Pointer<Void>,
      int,
      Pointer<Pointer<Void>>,
      int,
      Pointer<Utf8>,
      int,
      Pointer<Void>,
    );

// vips_jpegsave_buffer(VipsImage* in, void** buf, size_t* len, ...)
typedef _SaveNative =
    Int Function(
      Pointer<Void>,
      Pointer<Pointer<Void>>,
      Pointer<Size>,
      VarArgs<(Pointer<Void>,)>,
    );
typedef _SaveDart =
    int Function(
      Pointer<Void>,
      Pointer<Pointer<Void>>,
      Pointer<Size>,
      Pointer<Void>,
    );

typedef _PtrVoidNative = Void Function(Pointer<Void>);
typedef _PtrVoidDart = void Function(Pointer<Void>);

// vips_concurrency_set(int) -> void
typedef _ConcurrencyNative = Void Function(Int);
typedef _ConcurrencyDart = void Function(int);

// vips_error_clear() -> void
typedef _ErrorClearNative = Void Function();
typedef _ErrorClearDart = void Function();

/// Filename prefixes for each lib when bundled in the packaged app's
/// `Contents/libs` (§6.1); preferred over the Homebrew [_candidates].
const Map<String, String> _bundledPrefix = {
  'vips': 'libvips.',
  'glib': 'libglib-2.0',
  'gobject': 'libgobject-2.0',
};

/// Candidate paths for libvips and its glib/gobject deps (Homebrew in dev /
/// when not running from a packaged app). Both the Debian/Ubuntu multiarch
/// (`/usr/lib/x86_64-linux-gnu`) and the plain `/usr/lib` layout used by Arch,
/// Fedora and others are listed so the loader resolves on any distro.
const Map<String, List<String>> _candidates = {
  'vips': [
    '/opt/homebrew/lib/libvips.42.dylib',
    '/usr/local/lib/libvips.42.dylib',
    '/usr/lib/x86_64-linux-gnu/libvips.so.42',
    '/usr/lib64/libvips.so.42',
    '/usr/lib/libvips.so.42',
  ],
  'glib': [
    '/opt/homebrew/lib/libglib-2.0.dylib',
    '/usr/local/lib/libglib-2.0.dylib',
    '/usr/lib/x86_64-linux-gnu/libglib-2.0.so.0',
    '/usr/lib64/libglib-2.0.so.0',
    '/usr/lib/libglib-2.0.so.0',
  ],
  'gobject': [
    '/opt/homebrew/lib/libgobject-2.0.dylib',
    '/usr/local/lib/libgobject-2.0.dylib',
    '/usr/lib/x86_64-linux-gnu/libgobject-2.0.so.0',
    '/usr/lib64/libgobject-2.0.so.0',
    '/usr/lib/libgobject-2.0.so.0',
  ],
};

/// Fast native JPEG thumbnailing via libvips (shrink-on-load + EXIF
/// auto-rotate). Replaces the slow pure-Dart resize for the preview pipeline
/// (`BUILD_PLAN.md` §2/§6.1). Load once per isolate via [tryLoad].
class Vips {
  Vips._(this._thumb, this._save, this._gFree, this._gUnref, this._errorClear)
    : _heightKey = 'height'.toNativeUtf8();

  final _ThumbDart _thumb;
  final _SaveDart _save;
  final _PtrVoidDart _gFree;
  final _PtrVoidDart _gUnref;
  final _ErrorClearDart _errorClear;
  final Pointer<Utf8> _heightKey;

  static bool _warmedUp = false;

  /// Initialises libvips **once, single-threaded, on this (UI) isolate** and
  /// registers the thumbnail + JPEG load/save operation types by running one
  /// tiny real thumbnail.
  ///
  /// libvips' global GObject type system is *not* safe to register
  /// concurrently: if several preview-worker isolates call into vips for the
  /// first time at once (a burst of decode jobs from fast scrolling), they
  /// deadlock in
  /// `vips_type_find`/`vips_init`. Because the worker isolates share this
  /// process's heap and GC safepoints (`Isolate.spawn`), that wedges the whole
  /// app. Doing the first init + type registration up front, before any worker
  /// spawns, removes the race — workers then only ever *use* already-registered
  /// types, which libvips handles concurrently. Call from `main()` before the
  /// preview pool starts. No-op (best effort) if vips is unavailable.
  static void warmUpProcess() {
    if (_warmedUp) return;
    _warmedUp = true; // don't retry on failure
    final vips = tryLoad();
    if (vips == null) return;
    try {
      // A valid 2×2 JPEG forces the full thumbnail→jpegload→jpegsave path to
      // register its operation types here, on the main thread.
      vips.thumbnail(img.encodeJpg(img.Image(width: 2, height: 2)), 1);
    } on Object {
      // Best effort: registration still happened for whatever ran.
    }
    try {
      // Same reason, for the HEIF/AVIF *loader* (HEIC from iPhones, AVIF wire
      // images): the vips-heif module and its `heifload` type register lazily
      // on the first HEIF buffer, so warm it up here, on the main thread, or a
      // burst of HEIC decodes in worker isolates could race the same
      // concurrent-registration deadlock. Whether this tiny sample actually
      // decodes (the bundled libheif may lack this codec) is irrelevant — the
      // loader-type lookup that races happens regardless.
      vips.thumbnail(base64Decode(_heifWarmupAvif), 1);
    } on Object {
      // Best effort.
    }
  }

  // A 2×2 AVIF (ImageMagick), embedded solely to register the vips-heif loader
  // type during [warmUpProcess]. Both HEIC and AVIF share vips' one `heifload`
  // operation, so this one sample warms up the whole HEIF family.
  static const String _heifWarmupAvif =
      'AAAAHGZ0eXBhdmlmAAAAAG1pZjFhdmlmbWlhZgAAANRtZXRhAAAAAAAAACFoZGxyAAAAAAAA'
      'AABwaWN0AAAAAAAAAAAAAAAAAAAAACJpbG9jAAAAAERAAAEAAQAAAAAA+AABAAAAAAAAABYA'
      'AAAjaWluZgAAAAAAAQAAABVpbmZlAgAAAAABAABhdjAxAAAAAA5waXRtAAAAAAABAAAAVGlw'
      'cnAAAAA2aXBjbwAAAAxhdjFDgUB8AAAAABRpc3BlAAAAAAAAAAIAAAACAAAADnBpeGkAAAAA'
      'AQwAAAAWaXBtYQAAAAAAAAABAAEDgQIDAAAAHm1kYXQSAAoFWAA2uoAyCxlGIYmm'
      'aACQP5vg';

  /// Loads and initialises libvips, or returns `null` if it isn't available.
  static Vips? tryLoad() {
    try {
      // In the packaged app the warm-up call below is the process's *first*
      // vips_init — the one that discovers runtime modules (vips-heif: HEIC
      // loading, AVIF saving). VIPSHOME must point at the bundle before it,
      // or vips looks in the compile-time Homebrew/system prefix and the
      // bundled module is never found (the export encoder's own attempt
      // comes too late — its init is a no-op by then).
      final bundledVips = bundledNativeLib(_bundledPrefix['vips']!);
      if (bundledVips != null) pointVipsHomeAtBundle(bundledVips);
      final vips = DynamicLibrary.open(bundledVips ?? _resolve('vips')!);
      final glib = DynamicLibrary.open(_resolve('glib')!);
      final gobject = DynamicLibrary.open(_resolve('gobject')!);

      final init = vips.lookupFunction<_InitNative, _InitDart>('vips_init');
      final name = 'cullimingo'.toNativeUtf8();
      final ok = init(name) == 0;
      malloc.free(name);
      if (!ok) return null;

      // Single-threaded: no persistent vips thread pool, so a worker isolate
      // (and the process) can terminate cleanly. Each call is fast anyway.
      vips.lookupFunction<_ConcurrencyNative, _ConcurrencyDart>(
        'vips_concurrency_set',
      )(1);

      return Vips._(
        vips.lookupFunction<_ThumbNative, _ThumbDart>('vips_thumbnail_buffer'),
        vips.lookupFunction<_SaveNative, _SaveDart>('vips_jpegsave_buffer'),
        glib.lookupFunction<_PtrVoidNative, _PtrVoidDart>('g_free'),
        gobject.lookupFunction<_PtrVoidNative, _PtrVoidDart>('g_object_unref'),
        vips.lookupFunction<_ErrorClearNative, _ErrorClearDart>(
          'vips_error_clear',
        ),
      );
    } on Object {
      return null;
    }
  }

  /// Downscales [jpeg] so its long edge is ≤ [longEdge], applying EXIF
  /// orientation, and returns a small JPEG. Returns `null` on failure.
  Uint8List? thumbnail(Uint8List jpeg, int longEdge) {
    final input = malloc<Uint8>(jpeg.length);
    input.asTypedList(jpeg.length).setAll(0, jpeg);
    final outImage = malloc<Pointer<Void>>();
    final outBuf = malloc<Pointer<Void>>();
    final outLen = malloc<Size>();
    var haveImage = false;
    try {
      final rc = _thumb(
        input.cast(),
        jpeg.length,
        outImage,
        longEdge,
        _heightKey,
        longEdge,
        nullptr,
      );
      if (rc != 0) {
        // Clear the process-global error buffer: every failed decode appends
        // to it, so a folder full of corrupt/exotic files slowly grew native
        // memory (the encoder in core/vips already does this).
        _errorClear();
        return null;
      }
      haveImage = true;

      if (_save(outImage.value, outBuf, outLen, nullptr) != 0) {
        _errorClear();
        return null;
      }
      final bytes = Uint8List.fromList(
        outBuf.value.cast<Uint8>().asTypedList(outLen.value),
      );
      _gFree(outBuf.value);
      return bytes;
    } on Object {
      return null;
    } finally {
      if (haveImage) _gUnref(outImage.value);
      malloc
        ..free(input)
        ..free(outImage)
        ..free(outBuf)
        ..free(outLen);
    }
  }

  static String? _resolve(String key) {
    final bundled = bundledNativeLib(_bundledPrefix[key]!);
    if (bundled != null) return bundled;
    for (final path in _candidates[key]!) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }
}
