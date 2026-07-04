import 'dart:io';
import 'dart:typed_data';

import 'package:cullimingo/core/cache/file_signature.dart';
import 'package:cullimingo/core/cache/preview_cache.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Records how often the real extraction runs, to prove decode-once.
class _CountingExtractor implements PreviewExtractor {
  int calls = 0;
  int? lastLongEdge;

  @override
  Future<Uint8List?> thumbnail(
    String path, {
    int longEdge = 512,
    CancelToken? cancel,
    JobPriority priority = JobPriority.visible,
  }) async {
    calls++;
    lastLongEdge = longEdge;
    if (path.endsWith('.arw')) return null; // RAW stub: no preview
    return Uint8List.fromList(List<int>.generate(32, (i) => i));
  }
}

void main() {
  late Directory tmp;
  late File photo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cullimingo_cache');
    photo = File(p.join(tmp.path, 'a.jpg'))
      ..writeAsBytesSync(List<int>.filled(200 * 1024, 7));
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  PreviewCache cacheWith(
    PreviewExtractor extractor, {
    int? thumbLongEdge,
    int? loupeLongEdge,
  }) {
    final dir = Directory(p.join(tmp.path, 'cache'));
    return PreviewCache(
      extractor: extractor,
      cacheDirProvider: () async => dir,
      thumbLongEdge: thumbLongEdge,
      loupeLongEdge: loupeLongEdge,
    );
  }

  group('fileSignature', () {
    test('is stable for identical content but varies with salt', () async {
      final a = await fileSignature(photo);
      final b = await fileSignature(photo);
      final salted = await fileSignature(photo, salt: 'loupe');
      expect(a, b);
      expect(a, isNot(salted));
    });

    test('changes when content changes', () async {
      final before = await fileSignature(photo);
      photo.writeAsBytesSync(List<int>.filled(200 * 1024, 9));
      expect(await fileSignature(photo), isNot(before));
    });
  });

  group('PreviewCache', () {
    test('decodes once, then serves from disk', () async {
      final extractor = _CountingExtractor();
      final cache = cacheWith(extractor);

      final first = await cache.thumbnail(photo.path);
      final second = await cache.thumbnail(photo.path);

      expect(first, isNotNull);
      expect(second, first);
      expect(extractor.calls, 1, reason: 'second call must hit the disk cache');
    });

    test('writes a cache file on a miss', () async {
      final cache = cacheWith(_CountingExtractor());
      await cache.thumbnail(photo.path);

      final thumbDir = Directory(p.join(tmp.path, 'cache', 'thumb'));
      expect(thumbDir.existsSync(), isTrue);
      expect(thumbDir.listSync().whereType<File>(), isNotEmpty);
    });

    test(
      'returns null and caches nothing when extractor yields null',
      () async {
        final raw = File(p.join(tmp.path, 'b.arw'))
          ..writeAsBytesSync(const [1, 2]);
        final cache = cacheWith(_CountingExtractor());

        expect(await cache.thumbnail(raw.path), isNull);
        final thumbDir = Directory(p.join(tmp.path, 'cache', 'thumb'));
        final files = thumbDir.existsSync()
            ? thumbDir.listSync().whereType<File>()
            : const <File>[];
        expect(files, isEmpty);
      },
    );

    test('returns null for a missing file', () async {
      final cache = cacheWith(_CountingExtractor());
      expect(await cache.thumbnail('/no/such.jpg'), isNull);
    });

    test('pruneToBudget deletes oldest files past the budget', () async {
      final cache = cacheWith(_CountingExtractor());
      for (var i = 0; i < 5; i++) {
        final f = File(p.join(tmp.path, 'p$i.jpg'))
          ..writeAsBytesSync(List<int>.filled(100, i));
        await cache.thumbnail(f.path); // each writes a 32-byte cache file
      }
      final thumbDir = Directory(p.join(tmp.path, 'cache', 'thumb'));
      expect(thumbDir.listSync().whereType<File>(), hasLength(5));

      await cache.pruneToBudget(
        maxBytes: 64,
      ); // room for ~2 of the 32-byte files
      expect(
        thumbDir.listSync().whereType<File>().length,
        lessThanOrEqualTo(2),
      );
    });

    test('thumb tier extracts at the configured thumbLongEdge', () async {
      final extractor = _CountingExtractor();
      final cache = cacheWith(extractor, thumbLongEdge: 768);
      await cache.thumbnail(photo.path);
      expect(extractor.lastLongEdge, 768);
    });

    test('a different thumbLongEdge keys separately (re-extracts)', () async {
      final extractor = _CountingExtractor();
      await cacheWith(extractor, thumbLongEdge: 1024).thumbnail(photo.path);
      await cacheWith(extractor, thumbLongEdge: 768).thumbnail(photo.path);
      // Different size → different cache key → a second real extraction.
      expect(extractor.calls, 2);
    });

    test('loupe tier extracts at the configured loupeLongEdge', () async {
      final extractor = _CountingExtractor();
      final cache = cacheWith(extractor, loupeLongEdge: 3840);
      await cache.get(photo.path, PreviewTier.loupe);
      expect(extractor.lastLongEdge, 3840);
    });

    test('a different loupeLongEdge keys separately (re-extracts)', () async {
      final extractor = _CountingExtractor();
      await cacheWith(
        extractor,
        loupeLongEdge: 2048,
      ).get(photo.path, PreviewTier.loupe);
      await cacheWith(
        extractor,
        loupeLongEdge: 3840,
      ).get(photo.path, PreviewTier.loupe);
      // Different size → different cache key → a second real extraction.
      expect(extractor.calls, 2);
    });

    test('full tier extracts at native size (longEdge 0)', () async {
      final extractor = _CountingExtractor();
      final cache = cacheWith(extractor);
      await cache.get(photo.path, PreviewTier.full);
      expect(extractor.lastLongEdge, 0);
    });

    test('full tier is RAM-cached but never written to disk', () async {
      final extractor = _CountingExtractor();
      final cache = cacheWith(extractor);

      final first = await cache.get(photo.path, PreviewTier.full);
      final second = await cache.get(photo.path, PreviewTier.full);
      expect(first, isNotNull);
      expect(second, first);
      // Served from RAM the second time — no re-extract…
      expect(extractor.calls, 1);
      // …and nothing landed on disk (the full tier is large + re-derivable).
      final fullDir = Directory(p.join(tmp.path, 'cache', 'full'));
      expect(fullDir.existsSync(), isFalse);
    });

    test('clear empties the disk cache', () async {
      final cache = cacheWith(_CountingExtractor());
      await cache.thumbnail(photo.path);
      final cacheDir = Directory(p.join(tmp.path, 'cache'));
      expect(cacheDir.existsSync(), isTrue);

      await cache.clear();
      expect(cacheDir.existsSync(), isFalse);
    });
  });
}
