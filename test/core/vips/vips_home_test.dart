import 'dart:ffi';
import 'dart:io';

import 'package:cullimingo/core/vips/vips_home.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Reads the process environment through libc — `pointVipsHomeAtBundle` sets
/// it via `setenv`, which `Platform.environment` (snapshotted) may not see.
String? _getenv(String name) {
  final getenv = DynamicLibrary.process()
      .lookupFunction<
        Pointer<Utf8> Function(Pointer<Utf8>),
        Pointer<Utf8> Function(Pointer<Utf8>)
      >('getenv');
  final key = name.toNativeUtf8();
  final value = getenv(key);
  calloc.free(key);
  return value == nullptr ? null : value.toDartString();
}

void _unsetenv(String name) {
  final unsetenv = DynamicLibrary.process()
      .lookupFunction<Int Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>(
        'unsetenv',
      );
  final key = name.toNativeUtf8();
  unsetenv(key);
  calloc.free(key);
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('vips_home_test');
    _unsetenv('VIPSHOME');
    _unsetenv('LIBHEIF_PLUGIN_PATH');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
    _unsetenv('VIPSHOME');
    _unsetenv('LIBHEIF_PLUGIN_PATH');
  });

  /// Lays out a fake bundle for the current platform (§6.1) and returns the
  /// bundled libvips path plus the expected VIPSHOME. macOS: dylibs in `libs/`
  /// with a `vipshome/lib` next to it; Linux: everything in `<bundle>/lib`.
  (String libPath, String home) makeBundle(Directory root) {
    if (Platform.isMacOS) {
      final libs = Directory(p.join(root.path, 'libs'))..createSync();
      Directory(
        p.join(root.path, 'vipshome', 'lib'),
      ).createSync(recursive: true);
      return (
        p.join(libs.path, 'libvips.42.dylib'),
        p.join(root.path, 'vipshome'),
      );
    }
    final lib = Directory(p.join(root.path, 'lib'))..createSync();
    return (p.join(lib.path, 'libvips.so.42'), root.path);
  }

  test('points VIPSHOME at the bundle home', () {
    final (libPath, home) = makeBundle(tmp);
    pointVipsHomeAtBundle(libPath);
    expect(_getenv('VIPSHOME'), home);
  });

  test('leaves the environment alone when the layout is missing', () {
    pointVipsHomeAtBundle(p.join(tmp.path, 'nope', 'libvips.42.dylib'));
    expect(_getenv('VIPSHOME'), isNull);
  });

  test('points LIBHEIF_PLUGIN_PATH at bundled libheif plugins', () {
    final (libPath, _) = makeBundle(tmp);
    final plugins = Directory(
      p.join(p.dirname(libPath), 'libheif', 'plugins'),
    )..createSync(recursive: true);
    pointVipsHomeAtBundle(libPath);
    expect(_getenv('LIBHEIF_PLUGIN_PATH'), plugins.path);
  });

  test('no LIBHEIF_PLUGIN_PATH without a bundled plugin dir', () {
    final (libPath, _) = makeBundle(tmp);
    pointVipsHomeAtBundle(libPath);
    expect(_getenv('LIBHEIF_PLUGIN_PATH'), isNull);
  });
}
