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
      expect(nativeLibMatches('libraw.dylib', 'libraw.', linux: false), isTrue);
      expect(
        nativeLibMatches('libvips.42.dylib', 'libvips.', linux: false),
        isTrue,
      );
      // Linux .so must not match on macOS.
      expect(
        nativeLibMatches('libraw.so.23', 'libraw.', linux: false),
        isFalse,
      );
    });

    test('matches .so and versioned .so.N on Linux', () {
      expect(nativeLibMatches('libraw.so', 'libraw.', linux: true), isTrue);
      expect(nativeLibMatches('libraw.so.23', 'libraw.', linux: true), isTrue);
      expect(
        nativeLibMatches('libvips.so.42', 'libvips.', linux: true),
        isTrue,
      );
      expect(
        nativeLibMatches('libglib-2.0.so.0', 'libglib-2.0', linux: true),
        isTrue,
      );
      // macOS .dylib must not match on Linux.
      expect(
        nativeLibMatches('libraw.dylib', 'libraw.', linux: true),
        isFalse,
      );
    });

    test('requires the prefix', () {
      expect(nativeLibMatches('libother.so', 'libraw.', linux: true), isFalse);
      expect(
        nativeLibMatches('libother.dylib', 'libraw.', linux: false),
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
