import 'dart:io';

import 'package:cullimingo/features/metadata/data/marks_reader.dart';
import 'package:cullimingo/features/metadata/data/xmp_sidecar.dart';
import 'package:cullimingo/features/metadata/domain/xmp_data.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cullimingo_marks');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('reads marks from a .xmp sidecar next to a RAW', () async {
    final raw = p.join(tmp.path, 'DSC0001.ARW');
    await writeSidecar(
      raw,
      const XmpData(rating: 4, color: ColorLabel.green, keywords: ['sunset']),
    );

    final marks = await readMarks(raw);
    expect(marks, isNotNull);
    expect(marks!.rating, 4);
    expect(marks.color, ColorLabel.green);
    expect(marks.keywords, ['sunset']);
  });

  test(
    'returns null for a RAW with no sidecar (never reads the RAW itself)',
    () async {
      // No sidecar written, and RAW is excluded from the embedded-XMP path.
      final marks = await readMarks(p.join(tmp.path, 'DSC0002.ARW'));
      expect(marks, isNull);
    },
  );

  test('sidecar wins over any embedded packet for a JPEG', () async {
    final jpeg = p.join(tmp.path, 'export.jpg');
    // A real (if tiny) file exists so the embedded path is reachable…
    await File(jpeg).writeAsBytes(const [0xFF, 0xD8, 0xFF, 0xD9]);
    // …but the sidecar must take precedence.
    await writeSidecar(jpeg, const XmpData(rating: 2, color: ColorLabel.red));

    final marks = await readMarks(jpeg);
    expect(marks!.rating, 2);
    expect(marks.color, ColorLabel.red);
  });

  test(
    'readMarksForPaths pairs each hit with its sidecar mtime, misses null',
    () async {
      final hit = p.join(tmp.path, 'A.ARW');
      final miss = p.join(tmp.path, 'B.ARW');
      await writeSidecar(hit, const XmpData(rating: 5));

      final results = await readMarksForPaths([hit, miss]);
      expect(results, hasLength(2));

      final (hitXmp, hitMtime) = results[0];
      expect(hitXmp!.rating, 5);
      expect(hitMtime, isNotNull);

      final (missXmp, missMtime) = results[1];
      expect(missXmp, isNull);
      expect(missMtime, isNull);
    },
  );

  test(
    'readMarksForPaths preserves input order across the concurrency batch',
    () async {
      // More paths than the internal batch size (16) to exercise batching.
      final paths = [for (var i = 0; i < 40; i++) p.join(tmp.path, 'P$i.ARW')];
      for (var i = 0; i < paths.length; i++) {
        if (i.isEven) await writeSidecar(paths[i], XmpData(rating: i % 5 + 1));
      }

      final results = await readMarksForPaths(paths);
      for (var i = 0; i < paths.length; i++) {
        final (xmp, _) = results[i];
        if (i.isEven) {
          expect(xmp, isNotNull, reason: 'index $i should have marks');
          expect(xmp!.rating, i % 5 + 1);
        } else {
          expect(xmp, isNull, reason: 'index $i should be a miss');
        }
      }
    },
  );
}
