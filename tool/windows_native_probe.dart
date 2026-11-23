// Windows spike: proves the bundled native libs load the way the app loads
// them. Given the directory that holds the DLLs (the release bundle next to
// cullimingo.exe), it resolves libvips / glib / gobject / LibRaw with the
// app's own filename matcher (`nativeLibMatches`), opens each with
// `DynamicLibrary.open`, runs `vips_init` and reads both library versions.
//
//   dart run tool/windows_native_probe.dart build\windows\x64\runner\Release
//
// Exit code 0 = everything loaded; 1 = something is missing or failed to load.
//
// On Windows the dependency search for a DLL opened by full path starts in the
// *executable's* folder — cullimingo.exe's in the app, but dart.exe's here — so
// the probe first adds [dir] with SetDllDirectoryW, as the app's layout does
// implicitly.
import 'dart:ffi';
import 'dart:io';

import 'package:cullimingo/core/native/bundled_libs.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: windows_native_probe <dir-with-dlls>');
    exit(2);
  }
  final dir = Directory(args.single);
  if (Platform.isWindows) _addDllDirectory(dir.absolute.path);
  final names = dir
      .listSync()
      .whereType<File>()
      .map((f) => p.basename(f.path))
      .toList();

  String? find(String prefix) =>
      names.where((n) => nativeLibMatches(n, prefix)).firstOrNull;

  var ok = true;
  final libs = <String, DynamicLibrary>{};
  for (final prefix in [
    'libglib-2.0',
    'libgobject-2.0',
    'libvips.',
    'libraw.',
  ]) {
    final name = find(prefix);
    if (name == null) {
      stdout.writeln('MISSING  $prefix');
      ok = false;
      continue;
    }
    try {
      libs[prefix] = DynamicLibrary.open(p.join(dir.path, name));
      stdout.writeln('loaded   $prefix -> $name');
    } on Object catch (e) {
      stdout.writeln('FAILED   $prefix -> $name: $e');
      ok = false;
    }
  }

  final vips = libs['libvips.'];
  if (vips != null) {
    final init = vips
        .lookupFunction<
          Int Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)
        >(
          'vips_init',
        );
    final argv0 = 'cullimingo'.toNativeUtf8();
    final rc = init(argv0);
    calloc.free(argv0);
    final version = vips.lookupFunction<Int Function(Int), int Function(int)>(
      'vips_version',
    );
    stdout.writeln(
      'vips_init=$rc  libvips ${version(0)}.${version(1)}.${version(2)}',
    );
    if (rc != 0) ok = false;
  }

  final raw = libs['libraw.'];
  if (raw != null) {
    final version = raw
        .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'libraw_version',
        );
    stdout.writeln('LibRaw ${version().toDartString()}');
  }

  stdout.writeln(ok ? 'PROBE OK' : 'PROBE FAILED');
  exit(ok ? 0 : 1);
}

void _addDllDirectory(String path) {
  final setDllDirectory = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<
        Int32 Function(Pointer<Utf16>),
        int Function(Pointer<Utf16>)
      >('SetDllDirectoryW');
  final cPath = path.toNativeUtf16();
  if (setDllDirectory(cPath) == 0) stdout.writeln('SetDllDirectoryW failed');
  malloc.free(cPath);
}
