import 'package:cullimingo/core/naming/rename_template.dart';
import 'package:cullimingo/features/export/domain/export_plan.dart';
import 'package:cullimingo/features/export/domain/export_preset.dart';
import 'package:flutter_test/flutter_test.dart';

ExportSource _src(String path, DateTime when, {String? camera}) => ExportSource(
  path: path,
  capturedAt: when,
  originalName: path.split('/').last,
  camera: camera,
);

void main() {
  group('buildExportPlan', () {
    test('keeps original names, forces the .jpg extension', () {
      final plan = buildExportPlan(
        [_src('/cards/DSC_0001.ARW', DateTime(2026, 6, 1, 10))],
        const ExportPreset(),
      );
      expect(plan.single.relPath, 'DSC_0001.jpg');
      expect(plan.single.isRaw, isTrue);
    });

    test('orders by capture time then path', () {
      final plan = buildExportPlan([
        _src('/c/b.jpg', DateTime(2026, 6, 1, 10, 30)),
        _src('/c/a.jpg', DateTime(2026, 6, 1, 10)),
      ], const ExportPreset());
      expect(plan.map((i) => i.relPath), ['a.jpg', 'b.jpg']);
      expect(plan.first.isRaw, isFalse);
    });

    test('de-duplicates colliding output names with _2', () {
      // Two different RAWs whose JPEG output names would collide.
      final plan = buildExportPlan([
        _src('/c/DSC_0001.ARW', DateTime(2026, 6, 1, 10)),
        _src('/c/DSC_0001.JPG', DateTime(2026, 6, 1, 10, 1)),
      ], const ExportPreset());
      expect(plan.map((i) => i.relPath), ['DSC_0001.jpg', 'DSC_0001_2.jpg']);
    });

    test(
      'perSourceDir keeps identical names in different folders un-suffixed',
      () {
        // Same output name, but different source folders → different
        // destinations under next-to-originals, so neither is suffixed.
        final plan = buildExportPlan(
          [
            _src('/a/DSC_0001.ARW', DateTime(2026, 6, 1, 10)),
            _src('/b/DSC_0001.ARW', DateTime(2026, 6, 1, 10, 1)),
          ],
          const ExportPreset(),
          perSourceDir: true,
        );
        expect(plan.map((i) => i.relPath), ['DSC_0001.jpg', 'DSC_0001.jpg']);
      },
    );

    test('perSourceDir still de-dupes a real clash within one folder', () {
      final plan = buildExportPlan(
        [
          _src('/a/DSC_0001.ARW', DateTime(2026, 6, 1, 10)),
          _src('/a/DSC_0001.JPG', DateTime(2026, 6, 1, 10, 1)),
        ],
        const ExportPreset(),
        perSourceDir: true,
      );
      expect(plan.map((i) => i.relPath), ['DSC_0001.jpg', 'DSC_0001_2.jpg']);
    });

    test('applies a folder template and the {seq} token', () {
      final plan = buildExportPlan(
        [
          _src('/c/DSC_0009.ARW', DateTime(2026, 6, 1, 10), camera: 'A7IV'),
          _src('/c/DSC_0010.ARW', DateTime(2026, 6, 1, 11), camera: 'A7IV'),
        ],
        const ExportPreset(
          template: RenameTemplate('{YYYY}/{shoot}/{seq}'),
          shoot: 'Wedding',
        ),
      );
      expect(plan.map((i) => i.relPath), [
        '2026/Wedding/0001.jpg',
        '2026/Wedding/0002.jpg',
      ]);
    });
  });
}
