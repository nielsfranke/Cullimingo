import 'package:cullimingo/core/native/bundled_libs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns null when not running from a packaged app', () {
    // Under `flutter test` the resolved executable is the test runner, so there
    // is no bundled libs dir — callers must fall back to Homebrew/system.
    expect(bundledNativeLib('libvips.'), isNull);
    expect(bundledNativeLib('libraw.'), isNull);
  });

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
