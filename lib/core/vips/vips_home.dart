import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// Points `VIPSHOME` at the packaged app's bundle, so vips finds its runtime
/// modules (`$VIPSHOME/lib/vips-modules-<ver>/`, where the heif/AVIF saver
/// and loader live) inside the bundle instead of the compile-time
/// Homebrew/system prefix. [libPath] is the bundled libvips path from
/// `bundledNativeLib`.
///
/// **Must run before the process's very first `vips_init`.** libvips does
/// module discovery exactly once, on the first init; every later `vips_init`
/// is a no-op, so setting `VIPSHOME` afterwards changes nothing. In the app
/// that first init is `Vips.warmUpProcess()` (main.dart) — which is why both
/// `Vips.tryLoad` and `VipsEncoder.instance` call this before their init:
/// whichever runs first in a given process (app, standalone probe, test)
/// decides the module dir.
///
/// macOS bundles carry a `Contents/vipshome/lib → ../libs` symlink for this;
/// on Linux the bundle root already has `lib/`. Best effort — without it,
/// only HEIF/AVIF support is missing (the export dialog probes and hides
/// AVIF), WebP and JPEG are linked into libvips itself.
void pointVipsHomeAtBundle(String libPath) {
  final libsDir = p.dirname(libPath);
  final home = Platform.isMacOS
      ? p.join(p.dirname(libsDir), 'vipshome')
      : p.dirname(libsDir);
  if (!Directory(p.join(home, 'lib')).existsSync()) return;
  try {
    final setenv = DynamicLibrary.process()
        .lookupFunction<
          Int Function(Pointer<Utf8>, Pointer<Utf8>, Int),
          int Function(Pointer<Utf8>, Pointer<Utf8>, int)
        >('setenv');
    void set(String name, String value) {
      final key = name.toNativeUtf8();
      final val = value.toNativeUtf8();
      setenv(key, val, 1);
      calloc
        ..free(key)
        ..free(val);
    }

    set('VIPSHOME', home);
    // libheif dlopens its AVIF codec backend from a plugin dir; bundle_linux
    // bundles those under lib/libheif/plugins. Point libheif there so AVIF
    // works without the system plugin package (no-op when absent, e.g.
    // macOS, where the bundled libheif has its codecs built in).
    final plugins = p.join(libsDir, 'libheif', 'plugins');
    if (Directory(plugins).existsSync()) set('LIBHEIF_PLUGIN_PATH', plugins);
  } on Object {
    // Best effort — see above.
  }
}
