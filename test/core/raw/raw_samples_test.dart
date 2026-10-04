import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:cullimingo/core/cache/vips.dart';
import 'package:cullimingo/core/raw/libraw_preview_extractor.dart';
import 'package:cullimingo/core/raw/raw_display_jpeg.dart';
import 'package:flutter_libraw/flutter_libraw.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Real camera RAWs through the display pipeline — opt-in, local only.
///
/// Sample files are large and mostly not licensed for redistribution, so they
/// never live in the repo. Point `CULLIMINGO_SAMPLES` at a folder holding them
/// plus an `expectations.json` mapping each relative path to what
/// [rawDisplayJpeg] must produce for a grid-size request:
///
/// - `demosaic`: a LibRaw render at exactly the requested long edge (e.g. a
///   lossless HLG NEF whose only embedded JPEG is a 160×120 thumbnail);
/// - `embedded`: the camera's own embedded JPEG (the fast path);
/// - `none`: nothing — e.g. Nikon HE/HE* files LibRaw can't decode, which must
///   never come back as a demosaiced noise frame;
/// - `heif`: not a RAW — a HEIF/HIF that [Vips.thumbnail] must decode at both
///   grid and loupe sizes (e.g. a Sony `.HIF` whose embedded thumbnails some
///   libheif builds can't decode, #10).
///
/// Run before a release or a LibRaw upgrade:
///
/// ```sh
/// CULLIMINGO_SAMPLES=~/.cache/cullimingo/samples \
///   flutter test test/core/raw/raw_samples_test.dart
/// ```
///
/// `CULLIMINGO_LIBRAW` selects another LibRaw build (e.g. 0.22), as in
/// `raw_display_jpeg_test.dart`. Skipped entirely when the samples aren't set.
void main() {
  final root = Platform.environment['CULLIMINGO_SAMPLES'];
  final manifest = root == null
      ? null
      : File(p.join(root, 'expectations.json'));
  if (manifest == null || !manifest.existsSync()) {
    test(
      'real RAW samples',
      () {},
      skip: 'set CULLIMINGO_SAMPLES to a folder with expectations.json',
    );
    return;
  }

  final libPath =
      Platform.environment['CULLIMINGO_LIBRAW'] ??
      LibRawPreviewExtractor.resolveLibraryPath();
  final vips = Vips.tryLoad();
  final expectations =
      (jsonDecode(manifest.readAsStringSync()) as Map).cast<String, Object?>()
        ..removeWhere((key, _) => key.startsWith('_'));

  for (final MapEntry(key: rel, :value) in expectations.entries) {
    test('$rel → $value', () async {
      if (libPath == null || vips == null) {
        markTestSkipped('libraw/libvips not installed on this machine');
        return;
      }
      final path = p.join(root!, rel);
      expect(File(path).existsSync(), isTrue, reason: 'missing sample $path');
      if (value == 'heif') {
        final bytes = File(path).readAsBytesSync();
        for (final longEdge in const [320, 2560]) {
          final out = vips.thumbnail(bytes, longEdge);
          expect(out, isNotNull, reason: 'no decode at $longEdge px');
          final dims = jpegDimensions(out!)!;
          expect(dims.width > dims.height ? dims.width : dims.height, longEdge);
        }
        return;
      }
      final lr = FlutterLibRawBindings(DynamicLibrary.open(libPath));
      const longEdge = 320;

      final out = await rawDisplayJpeg(
        lr,
        path,
        longEdge: longEdge,
        vips: () => vips,
      );

      switch (value) {
        case 'demosaic':
          expect(out?.demosaiced, isTrue);
          final dims = jpegDimensions(out!.bytes)!;
          expect(dims.width > dims.height ? dims.width : dims.height, longEdge);
        case 'embedded':
          expect(out, isNotNull);
          expect(out!.demosaiced, isFalse);
        case 'none':
          expect(out?.demosaiced ?? false, isFalse, reason: 'noise frame');
          expect(out, isNull);
        default:
          fail('unknown expectation "$value" for $rel');
      }
    });
  }
}
