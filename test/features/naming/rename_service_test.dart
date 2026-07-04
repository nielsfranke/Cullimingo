import 'dart:io';

import 'package:cullimingo/features/ingest/domain/rename_template.dart';
import 'package:cullimingo/features/naming/data/rename_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  RenameSource src(String path, {int id = 0}) => RenameSource(
    id: id,
    path: path,
    capturedAt: DateTime(2026, 7, 3, 14, 30, 5),
    camera: 'ILCE-7M4',
  );

  group('planRenames', () {
    test(
      'numbers the sequence in list order and keeps files in their folder',
      () {
        final plan = planRenames(
          [src('/shoot/DSC0001.ARW', id: 1), src('/shoot/DSC0002.ARW', id: 2)],
          template: const RenameTemplate('{YYYY}/{shoot}_{seq:3}'),
          shoot: 'Derby',
          exists: (_) => false,
        );
        // The folder token is flattened away — a rename stays in its folder.
        expect(plan[0].target, '/shoot/Derby_001.ARW');
        expect(plan[1].target, '/shoot/Derby_002.ARW');
        expect(plan.every((i) => p.dirname(i.target) == '/shoot'), isTrue);
      },
    );

    test('pairs an existing .xmp sidecar and renames it to match', () {
      final plan = planRenames(
        [src('/s/DSC0001.ARW', id: 1), src('/s/DSC0002.ARW', id: 2)],
        template: const RenameTemplate('{seq:2}'),
        // Only the first photo has a sidecar on disk.
        exists: (path) => path == '/s/DSC0001.xmp',
      );
      expect(plan[0].sidecar, '/s/DSC0001.xmp');
      expect(plan[0].sidecarTarget, '/s/01.xmp');
      expect(plan[1].sidecar, isNull);
      expect(plan[1].sidecarTarget, isNull);
    });

    test('de-dupes in-batch name clashes with a _2 suffix', () {
      final plan = planRenames(
        [src('/s/a.ARW', id: 1), src('/s/b.ARW', id: 2)],
        // A token-less pattern renders the same name for every photo.
        template: const RenameTemplate('roll'),
        exists: (_) => false,
      );
      expect(plan[0].target, '/s/roll.ARW');
      expect(plan[1].target, '/s/roll_2.ARW');
    });

    test('avoids a bystander file already on disk', () {
      final plan = planRenames(
        [src('/s/a.ARW', id: 1)],
        template: const RenameTemplate('taken'),
        // A non-batch file already owns the target name.
        exists: (path) => path == '/s/taken.ARW',
      );
      expect(plan[0].target, '/s/taken_2.ARW');
    });

    test('lets a rename reuse a name freed by another batch source', () {
      // Both files exist on disk, but b.ARW is itself being renamed, so a.ARW
      // may take "b" — the two-phase apply frees it first. b then clashes and
      // gets _2. Only genuine bystanders (not in the batch) block a name.
      final plan = planRenames(
        [src('/s/a.ARW', id: 1), src('/s/b.ARW', id: 2)],
        template: const RenameTemplate('b'),
        exists: (path) => path == '/s/a.ARW' || path == '/s/b.ARW',
      );
      expect(plan[0].target, '/s/b.ARW');
      expect(plan[1].target, '/s/b_2.ARW');
    });

    test('groups a RAW+JPEG pair into one base with a shared number', () {
      final plan = planRenames(
        [
          src('/s/DSC1.ARW', id: 1),
          src('/s/DSC1.JPG', id: 2),
          src('/s/DSC2.ARW', id: 3),
        ],
        template: const RenameTemplate('roll_{seq:3}'),
        exists: (_) => false,
      );
      final byId = {for (final i in plan) i.photoId: i};
      // The .ARW and .JPG twin share base roll_001 (the counter is per shot);
      // the next distinct shot is roll_002 — the pair is never split.
      expect(byId[1]!.target, '/s/roll_001.ARW');
      expect(byId[2]!.target, '/s/roll_001.JPG');
      expect(byId[3]!.target, '/s/roll_002.ARW');
    });

    test("renames a pair's shared .xmp sidecar exactly once", () {
      final plan = planRenames(
        [src('/s/DSC1.ARW', id: 1), src('/s/DSC1.JPG', id: 2)],
        template: const RenameTemplate('new'),
        exists: (path) => path == '/s/DSC1.xmp',
      );
      final withSidecar = plan.where((i) => i.sidecar != null).toList();
      expect(withSidecar, hasLength(1));
      expect(withSidecar.single.sidecar, '/s/DSC1.xmp');
      expect(withSidecar.single.sidecarTarget, '/s/new.xmp');
    });

    test('marks a no-op when the new name equals the old', () {
      final plan = planRenames(
        [src('/s/keep.ARW', id: 1)],
        template: RenameTemplate.keepNames,
        exists: (_) => false,
      );
      expect(plan[0].unchanged, isTrue);
    });
  });

  group('applyRenamePlan (real files)', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('cullrename'));
    tearDown(() => dir.deleteSync(recursive: true));

    String path(String name) => p.join(dir.path, name);
    void write(String name, String content) =>
        File(path(name)).writeAsStringSync(content);

    test('renames a file and its sidecar', () {
      write('a.jpg', 'A');
      write('a.xmp', 'Ax');
      final results = applyRenamePlan([
        RenameItem(
          photoId: 1,
          source: path('a.jpg'),
          target: path('z.jpg'),
          sidecar: path('a.xmp'),
          sidecarTarget: path('z.xmp'),
        ),
      ]);
      expect(results.single.ok, isTrue);
      expect(results.single.newPath, path('z.jpg'));
      expect(File(path('a.jpg')).existsSync(), isFalse);
      expect(File(path('z.jpg')).readAsStringSync(), 'A');
      expect(File(path('z.xmp')).readAsStringSync(), 'Ax');
    });

    test('swaps two names via the two-phase temp step', () {
      write('1.jpg', 'one');
      write('2.jpg', 'two');
      final results = applyRenamePlan([
        RenameItem(photoId: 1, source: path('1.jpg'), target: path('2.jpg')),
        RenameItem(photoId: 2, source: path('2.jpg'), target: path('1.jpg')),
      ]);
      expect(results.every((r) => r.ok), isTrue);
      // The swap survives — no file clobbered the other.
      expect(File(path('1.jpg')).readAsStringSync(), 'two');
      expect(File(path('2.jpg')).readAsStringSync(), 'one');
    });

    test('leaves an unchanged item untouched', () {
      write('keep.jpg', 'K');
      final results = applyRenamePlan([
        RenameItem(
          photoId: 1,
          source: path('keep.jpg'),
          target: path('keep.jpg'),
        ),
      ]);
      expect(results.single.outcome, RenameOutcome.unchanged);
      expect(File(path('keep.jpg')).readAsStringSync(), 'K');
    });

    test('summary counts renamed / unchanged', () {
      write('a.jpg', 'A');
      write('b.jpg', 'B');
      final results = applyRenamePlan([
        RenameItem(photoId: 1, source: path('a.jpg'), target: path('a2.jpg')),
        RenameItem(photoId: 2, source: path('b.jpg'), target: path('b.jpg')),
      ]);
      final summary = RenameSummary(results);
      expect(summary.renamed, 1);
      expect(summary.unchanged, 1);
      expect(summary.failed, 0);
    });

    test('rolls the file back to its source when phase 2 fails', () {
      write('a.jpg', 'A');
      write('a.xmp', 'Ax');
      // A directory sitting at the target makes the phase-2 rename (temp →
      // target) throw after phase 1 has already moved the file to a temp name —
      // the exact stranding case the rollback guards against.
      Directory(path('z.jpg')).createSync();
      write(p.join('z.jpg', 'blocker'), 'x');

      final results = applyRenamePlan([
        RenameItem(
          photoId: 1,
          source: path('a.jpg'),
          target: path('z.jpg'),
          sidecar: path('a.xmp'),
          sidecarTarget: path('z.xmp'),
        ),
      ]);

      // The rename is reported as a failure…
      expect(results.single.outcome, RenameOutcome.error);
      expect(results.single.newPath, isNull);
      // …the file (and its sidecar) are back where the DB row still points…
      expect(File(path('a.jpg')).readAsStringSync(), 'A');
      expect(File(path('a.xmp')).readAsStringSync(), 'Ax');
      // …and nothing is stranded at a hidden temp name.
      final leftovers = dir
          .listSync()
          .map((e) => p.basename(e.path))
          .where((n) => n.startsWith('.cullrename_'));
      expect(leftovers, isEmpty);
    });
  });
}
