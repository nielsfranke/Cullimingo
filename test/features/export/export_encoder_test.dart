import 'dart:typed_data';

import 'package:cullimingo/core/vips/vips_encoder.dart';
import 'package:cullimingo/features/export/data/export_encoder.dart';
import 'package:cullimingo/features/export/domain/export_preset.dart';
import 'package:cullimingo/features/metadata/data/iptc_iim.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/features/metadata/domain/xmp_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _sourceJpeg(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(120, 80, 40));
  return img.encodeJpg(image);
}

void main() {
  test('downscales so the long edge matches, preserving aspect', () {
    final out = renderExportJpeg(
      _sourceJpeg(400, 200),
      longEdge: 100,
      quality: 85,
    );
    final decoded = img.decodeJpg(out!)!;
    expect(decoded.width, 100);
    expect(decoded.height, 50);
  });

  test('never upscales a smaller source', () {
    final out = renderExportJpeg(
      _sourceJpeg(300, 200),
      longEdge: 2048,
      quality: 85,
    );
    final decoded = img.decodeJpg(out!)!;
    expect(decoded.width, 300);
    expect(decoded.height, 200);
  });

  test('sharpen returns a valid, same-size JPEG', () {
    final out = renderExportJpeg(
      _sourceJpeg(400, 300),
      longEdge: 200,
      quality: 90,
      sharpen: true,
    );
    final decoded = img.decodeJpg(out!);
    expect(decoded, isNotNull);
    expect(decoded!.width, 200);
  });

  test('bakes orientation into pixels and clears the orientation tag', () {
    final src = img.Image(width: 400, height: 200);
    img.fill(src, color: img.ColorRgb8(10, 20, 30));
    src.exif.imageIfd.orientation = 6; // display-rotate 90° CW
    final bytes = Uint8List.fromList(img.encodeJpg(src));

    final decoded = img.decodeJpg(
      renderExportJpeg(bytes, longEdge: 4096, quality: 90)!,
    )!;
    // Pixels physically rotated (400×200 → 200×400)…
    expect(decoded.width, 200);
    expect(decoded.height, 400);
    // …and the tag reset so a viewer won't rotate again.
    final orientation = decoded.exif.imageIfd.orientation;
    expect(orientation == null || orientation == 1, isTrue);
  });

  test('bakes the user rotation into the export pixels', () {
    // A 400×200 landscape with a single user quarter-turn becomes portrait.
    final out = renderExportJpeg(
      _sourceJpeg(400, 200),
      longEdge: 4096,
      quality: 90,
      userRotation: 1,
    )!;
    final decoded = img.decodeJpg(out)!;
    expect(decoded.width, 200);
    expect(decoded.height, 400);
  });

  test('maxBytes steps quality down to hit a target size', () {
    // Noise resists compression, so Q has a real effect on size.
    final noisy = img.Image(width: 1200, height: 900);
    for (final pixel in noisy) {
      pixel.setRgb(
        pixel.x * 7 % 256,
        pixel.y * 13 % 256,
        (pixel.x + pixel.y) % 256,
      );
    }
    final bytes = Uint8List.fromList(img.encodeJpg(noisy));

    final unbounded = renderExportJpeg(bytes, longEdge: 1200, quality: 95)!;
    final capped = renderExportJpeg(
      bytes,
      longEdge: 1200,
      quality: 95,
      maxBytes: unbounded.lengthInBytes ~/ 2,
    )!;
    expect(capped.lengthInBytes, lessThan(unbounded.lengthInBytes));
  });

  test('returns null for undecodable bytes', () {
    expect(
      renderExportJpeg(
        Uint8List.fromList([1, 2, 3, 4]),
        longEdge: 100,
        quality: 85,
      ),
      isNull,
    );
  });

  group('XMP embedding', () {
    const xmp =
        '<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?> '
        '<x:xmpmeta xmlns:x="adobe:ns:meta/"> CAPTION_HERE </x:xmpmeta> '
        '<?xpacket end="w"?>';

    test('embeds a valid APP1 XMP segment and stays a decodable JPEG', () {
      final jpeg = Uint8List.fromList(_sourceJpeg(64, 48));
      final out = embedXmpInJpeg(jpeg, xmp);

      // Still a JPEG that decodes.
      expect(img.decodeJpg(out), isNotNull);
      // SOI, then an APP1 (FF E1) marker with the XMP identifier.
      expect(out[0], 0xFF);
      expect(out[1], 0xD8);
      expect(out[2], 0xFF);
      expect(out[3], 0xE1);
      final segLen = (out[4] << 8) | out[5];
      expect(segLen, 2 + _xmpApp1HeaderLen + xmp.length);
      // The packet (and our marker text) survive in the bytes.
      final text = String.fromCharCodes(out);
      expect(text.contains('http://ns.adobe.com/xap/1.0/'), isTrue);
      expect(text.contains('CAPTION_HERE'), isTrue);
    });

    test('renderExportJpeg embeds meta as both XMP and legacy IIM', () {
      final out = renderExportJpeg(
        Uint8List.fromList(_sourceJpeg(120, 80)),
        longEdge: 100,
        quality: 85,
        meta: const XmpData(iptc: IptcCore(caption: 'On the wire')),
      )!;
      final text = String.fromCharCodes(out);
      expect(text.contains('ns.adobe.com/xap/1.0/'), isTrue); // XMP APP1
      expect(text.contains('Photoshop 3.0'), isTrue); // IIM APP13
      expect(text.contains('On the wire'), isTrue);
    });

    test('no meta leaves the JPEG without XMP or IIM', () {
      final out = renderExportJpeg(
        Uint8List.fromList(_sourceJpeg(120, 80)),
        longEdge: 100,
        quality: 85,
      )!;
      final text = String.fromCharCodes(out);
      expect(text.contains('ns.adobe.com/xap'), isFalse);
      expect(text.contains('Photoshop 3.0'), isFalse);
    });

    test('empty xmp or non-JPEG input is returned unchanged', () {
      final jpeg = Uint8List.fromList(_sourceJpeg(32, 32));
      expect(embedXmpInJpeg(jpeg, ''), same(jpeg));
      final notJpeg = Uint8List.fromList([1, 2, 3]);
      expect(embedXmpInJpeg(notJpeg, xmp), same(notJpeg));
    });
  });

  group('legacy IIM embedding', () {
    const meta = XmpData(
      keywords: ['sport'],
      iptc: IptcCore(caption: 'Goal!', creator: 'Jane Doe', credit: 'AP'),
    );

    test(
      'buildIptcIim emits a UTF-8 charset marker then record-2 datasets',
      () {
        final iim = buildIptcIim(meta);
        // Starts with the 1:90 coded-character-set dataset (0x1C 0x01 0x5A).
        expect(iim.sublist(0, 3), [0x1C, 0x01, 0x5A]);
        // The editorial values are present as UTF-8 bytes.
        final text = String.fromCharCodes(iim);
        expect(text.contains('Goal!'), isTrue);
        expect(text.contains('Jane Doe'), isTrue);
        expect(text.contains('AP'), isTrue);
        expect(text.contains('sport'), isTrue);
      },
    );

    test('buildIptcIim is empty when there are no classic fields', () {
      expect(buildIptcIim(const XmpData(rating: 5)).isEmpty, isTrue);
    });

    test('buildIptcIim writes DateCreated (2:55) + TimeCreated (2:60) in '
        'ascending dataset order', () {
      final iim = buildIptcIim(
        XmpData(
          iptc: const IptcCore(caption: 'x', creator: 'Jane'),
          dateCreated: DateTime(2026, 7, 2, 9, 5, 3),
        ),
      );
      final text = String.fromCharCodes(iim);
      expect(text, contains('20260702'));
      expect(text, contains('090503'));
      // IIM wants record-2 datasets ascending; walk the markers to verify.
      var lastDataset = -1;
      for (var i = 0; i + 5 <= iim.length;) {
        expect(iim[i], 0x1C);
        final length = (iim[i + 3] << 8) | iim[i + 4];
        if (iim[i + 1] == 2) {
          expect(iim[i + 2], greaterThanOrEqualTo(lastDataset));
          lastDataset = iim[i + 2];
        }
        i += 5 + length;
      }
    });

    test('embeds an APP13 8BIM/0x0404 block into a valid JPEG', () {
      final jpeg = Uint8List.fromList(_sourceJpeg(64, 48));
      final out = embedIptcIimInJpeg(jpeg, meta);

      expect(img.decodeJpg(out), isNotNull); // still a JPEG
      expect(out[2], 0xFF);
      expect(out[3], 0xED); // APP13
      final text = String.fromCharCodes(out);
      expect(text.contains('Photoshop 3.0'), isTrue);
      expect(text.contains('8BIM'), isTrue);
      expect(text.contains('Goal!'), isTrue);
    });

    test('non-JPEG or empty-meta input is returned unchanged', () {
      final jpeg = Uint8List.fromList(_sourceJpeg(32, 32));
      expect(embedIptcIimInJpeg(jpeg, const XmpData(rating: 3)), same(jpeg));
      final notJpeg = Uint8List.fromList([1, 2, 3]);
      expect(embedIptcIimInJpeg(notJpeg, meta), same(notJpeg));
    });
  });

  group('WebP/AVIF via libvips', () {
    final hasVips = VipsEncoder.instance() != null;

    test('renders a downscaled WebP the image package decodes', () {
      if (!hasVips) {
        markTestSkipped('libvips not installed on this machine');
        return;
      }
      final out = renderExportBytes(
        _sourceJpeg(400, 200),
        longEdge: 100,
        quality: 80,
        format: ExportFormat.webp,
      );
      final decoded = img.decodeWebP(out!)!;
      expect(decoded.width, 100);
      expect(decoded.height, 50);
    });

    test('WebP carries the XMP packet (caption reaches the file)', () {
      if (!hasVips) {
        markTestSkipped('libvips not installed on this machine');
        return;
      }
      final out = renderExportBytes(
        _sourceJpeg(64, 48),
        longEdge: 64,
        quality: 80,
        format: ExportFormat.webp,
        meta: const XmpData(iptc: IptcCore(caption: 'vips-caption-marker')),
      );
      expect(String.fromCharCodes(out!), contains('vips-caption-marker'));
    });

    test('renders an AVIF (ftyp brand)', () {
      if (!hasVips) {
        markTestSkipped('libvips not installed on this machine');
        return;
      }
      final out = renderExportBytes(
        _sourceJpeg(64, 48),
        longEdge: 64,
        quality: 60,
        format: ExportFormat.avif,
      );
      expect(String.fromCharCodes(out!.sublist(4, 12)), 'ftypavif');
    });

    test('maxBytes steps WebP quality down until it fits', () {
      if (!hasVips) {
        markTestSkipped('libvips not installed on this machine');
        return;
      }
      // A noisy source resists compression, so the loop has work to do.
      final noisy = img.Image(width: 256, height: 256);
      for (var y = 0; y < 256; y++) {
        for (var x = 0; x < 256; x++) {
          noisy.setPixelRgb(x, y, (x * 37 + y * 91) % 256, (x ^ y) % 256, x);
        }
      }
      final source = Uint8List.fromList(img.encodeJpg(noisy, quality: 98));
      final unlimited = renderExportBytes(
        source,
        longEdge: 256,
        quality: 95,
        format: ExportFormat.webp,
      )!;
      final capped = renderExportBytes(
        source,
        longEdge: 256,
        quality: 95,
        format: ExportFormat.webp,
        maxBytes: unlimited.lengthInBytes ~/ 2,
      )!;
      expect(capped.lengthInBytes, lessThan(unlimited.lengthInBytes));
    });
  });
}

/// Length of the NUL-terminated XMP APP1 header (`http://ns.adobe.com/xap/1.0/`
/// + NUL) — 29 bytes.
const int _xmpApp1HeaderLen = 29;
