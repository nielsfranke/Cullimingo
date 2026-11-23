import 'dart:io';

import 'package:cullimingo/core/native/bundled_libs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns null when not running from a packaged app', () {
    // Under `flutter test` the resolved executable is the test runner, so there
    // is no bundled libs dir — callers must fall back to Homebrew/system.
    expect(bundledNativeLib('libvips.'), isNull);
    expect(bundledNativeLib('libraw.'), isNull);
  });

  group('preloadHostPreferredLibs', _hostPreferredTests);

  group('nativeLibMatches', () {
    test('matches .dylib on macOS', () {
      expect(nativeLibMatches('libraw.dylib', 'libraw.', os: 'macos'), isTrue);
      expect(
        nativeLibMatches('libvips.42.dylib', 'libvips.', os: 'macos'),
        isTrue,
      );
      // Linux .so must not match on macOS.
      expect(
        nativeLibMatches('libraw.so.23', 'libraw.', os: 'macos'),
        isFalse,
      );
    });

    test('matches .so and versioned .so.N on Linux', () {
      expect(nativeLibMatches('libraw.so', 'libraw.', os: 'linux'), isTrue);
      expect(nativeLibMatches('libraw.so.23', 'libraw.', os: 'linux'), isTrue);
      expect(
        nativeLibMatches('libvips.so.42', 'libvips.', os: 'linux'),
        isTrue,
      );
      expect(
        nativeLibMatches('libglib-2.0.so.0', 'libglib-2.0', os: 'linux'),
        isTrue,
      );
      // macOS .dylib must not match on Linux.
      expect(
        nativeLibMatches('libraw.dylib', 'libraw.', os: 'linux'),
        isFalse,
      );
    });

    test('matches the build-win64-mxe DLL names on Windows', () {
      bool win(String name, String prefix) =>
          nativeLibMatches(name, prefix, os: 'windows');
      expect(win('libvips-42.dll', 'libvips.'), isTrue);
      expect(win('libraw_r-25.dll', 'libraw.'), isTrue);
      expect(win('libraw.dll', 'libraw.'), isTrue);
      expect(win('libglib-2.0-0.dll', 'libglib-2.0'), isTrue);
      expect(win('libgobject-2.0-0.dll', 'libgobject-2.0'), isTrue);
      expect(win('LIBVIPS-42.DLL', 'libvips.'), isTrue);
      // The C++ wrapper shares the prefix but is not libvips itself.
      expect(win('libvips-cpp-42.dll', 'libvips.'), isFalse);
      expect(win('libvips.so.42', 'libvips.'), isFalse);
      expect(win('libvips.42.dylib', 'libvips.'), isFalse);
    });

    test('requires the prefix', () {
      expect(nativeLibMatches('libother.so', 'libraw.', os: 'linux'), isFalse);
      expect(
        nativeLibMatches('libother.dylib', 'libraw.', os: 'macos'),
        isFalse,
      );
    });
  });
}

void _hostPreferredTests() {
  late Directory fallback;

  setUp(() {
    fallback = Directory.systemTemp.createTempSync('cullimingo-fallback');
    File('${fallback.path}/librsvg-2.so.2').writeAsStringSync('');
    File('${fallback.path}/libzeta.so.1').writeAsStringSync('');
    File('${fallback.path}/README').writeAsStringSync('');
    debugResetHostPreferredLibs();
  });

  tearDown(() {
    fallback.deleteSync(recursive: true);
    debugResetHostPreferredLibs();
  });

  test('lists the shipped sonames, sorted, skipping non-libraries', () {
    expect(hostPreferredSonames(fallback), ['librsvg-2.so.2', 'libzeta.so.1']);
  });

  test('opens the host copy by soname and never ours when it exists', () {
    final opened = <String>[];
    preloadHostPreferredLibs(fallbackDir: fallback, open: opened.add);
    expect(opened, ['librsvg-2.so.2', 'libzeta.so.1']);
  });

  test('falls back to the bundled copy by absolute path when the host '
      'has none', () {
    final opened = <String>[];
    preloadHostPreferredLibs(
      fallbackDir: fallback,
      open: (name) {
        opened.add(name);
        if (name == 'librsvg-2.so.2') throw ArgumentError('not on host');
      },
    );
    expect(opened, [
      'librsvg-2.so.2',
      '${fallback.path}/librsvg-2.so.2',
      'libzeta.so.1',
    ]);
  });

  test('is best effort when neither copy opens', () {
    expect(
      () => preloadHostPreferredLibs(
        fallbackDir: fallback,
        open: (_) => throw ArgumentError('nope'),
      ),
      returnsNormally,
    );
  });

  test('runs once per isolate', () {
    final opened = <String>[];
    preloadHostPreferredLibs(fallbackDir: fallback, open: opened.add);
    preloadHostPreferredLibs(fallbackDir: fallback, open: opened.add);
    expect(opened, ['librsvg-2.so.2', 'libzeta.so.1']);
  });

  test('is a no-op without a fallback dir', () {
    var calls = 0;
    preloadHostPreferredLibs(
      fallbackDir: Directory('${fallback.path}/missing'),
      open: (_) => calls++,
    );
    expect(calls, 0);
  });
}
