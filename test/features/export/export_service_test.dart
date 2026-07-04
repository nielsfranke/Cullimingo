import 'dart:async';
import 'dart:io';

import 'package:cullimingo/features/export/data/export_service.dart';
import 'package:cullimingo/features/export/domain/export_plan.dart';
import 'package:cullimingo/features/export/domain/export_preset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

List<ExportItem> _plan(int n) => [
  for (var i = 1; i <= n; i++)
    ExportItem(source: '/c/img$i.jpg', relPath: 'img$i.jpg', isRaw: false),
];

void main() {
  group('runExport', () {
    test('emits a progress tick per file and finishes all', () async {
      final progress = await runExport(
        plan: _plan(5),
        destinationRoot: '/out',
        preset: const ExportPreset(),
        renderer:
            ({
              required item,
              required destPath,
              required preset,
              required libraryPath,
            }) async => ExportOutcome.written,
      ).toList();

      expect(progress, hasLength(5));
      expect(progress.last.done, 5);
      expect(progress.last.total, 5);
      expect(ExportSummary(progress.map((t) => t.last).toList()).allOk, isTrue);
    });

    test('cancelling stops launching new renders', () async {
      var started = 0;
      final blocker = Completer<void>();
      final stream = runExport(
        plan: _plan(100),
        destinationRoot: '/out',
        preset: const ExportPreset(),
        concurrency: 1,
        renderer:
            ({
              required item,
              required destPath,
              required preset,
              required libraryPath,
            }) {
              started++;
              // Block the worker on the first file so cancel lands mid-run.
              return blocker.future.then((_) => ExportOutcome.written);
            },
      );

      final sub = stream.listen(null);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(started, 1); // one in flight, the rest still queued
      await sub.cancel();
      blocker.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // No further renders launched after cancel.
      expect(started, 1);
    });
  });

  group('renderExportToFile', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('cm_export_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('writes a downscaled JPEG for a bitmap source', () {
      final srcPath = p.join(tmp.path, 'in.jpg');
      File(srcPath).writeAsBytesSync(
        img.encodeJpg(img.Image(width: 4000, height: 3000)),
      );
      final destPath = p.join(tmp.path, 'out', 'in.jpg');

      final outcome = renderExportToFile(
        item: ExportItem(source: srcPath, relPath: 'in.jpg', isRaw: false),
        destPath: destPath,
        preset: const ExportPreset(longEdge: 1024),
      );

      expect(outcome, ExportOutcome.written);
      final decoded = img.decodeJpg(File(destPath).readAsBytesSync())!;
      expect(decoded.width, 1024);
      expect(decoded.height, 768);
    });

    test('reports an unreadable source when the file is missing', () {
      final outcome = renderExportToFile(
        item: const ExportItem(
          source: '/nope/missing.jpg',
          relPath: 'missing.jpg',
          isRaw: false,
        ),
        destPath: p.join(tmp.path, 'missing.jpg'),
        preset: const ExportPreset(),
      );
      expect(outcome, ExportOutcome.sourceUnreadable);
    });
  });
}
