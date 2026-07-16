import 'dart:io';

import 'package:cullimingo/core/files/verified_copy.dart';
import 'package:cullimingo/core/naming/rename_template.dart';
import 'package:cullimingo/features/ingest/data/ingest_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('buildPlan', () {
    test('orders by capture time, assigns a stable sequence', () {
      final plan = buildPlan(
        sources: [
          IngestSource(
            path: '/card/b.arw',
            capturedAt: DateTime(2026, 6, 1, 12),
          ),
          IngestSource(
            path: '/card/a.arw',
            capturedAt: DateTime(2026, 6, 1, 10),
          ),
        ],
        template: const RenameTemplate('{seq}_{origname}'),
      );

      // a.arw is earlier → sequence 1.
      expect(plan.items[0].source, '/card/a.arw');
      expect(plan.items[0].relPath, '0001_a.arw');
      expect(plan.items[1].relPath, '0002_b.arw');
    });

    test('resolves within-batch destination collisions', () {
      final plan = buildPlan(
        sources: [
          IngestSource(path: '/card/1/IMG.jpg', capturedAt: DateTime(2026)),
          IngestSource(path: '/card/2/IMG.jpg', capturedAt: DateTime(2026)),
        ],
        // Same date + same origname → collide without disambiguation.
        template: const RenameTemplate('{YYYY}/{origname}'),
      );

      expect(plan.items[0].relPath, '2026/IMG.jpg');
      expect(plan.items[1].relPath, '2026/IMG_2.jpg');
    });

    test('companions follow the photo path with their own extension', () {
      final plan = buildPlan(
        sources: [
          IngestSource(
            path: '/c/IMG.arw',
            capturedAt: DateTime(2026),
            companions: ['/c/IMG.xmp', '/c/IMG.thm'],
          ),
        ],
        template: const RenameTemplate('{YYYY}/{origname}'),
      );

      final item = plan.items.single;
      expect(item.relPath, '2026/IMG.arw');
      expect(
        item.companions.map((c) => '${c.source} -> ${c.relPath}').toSet(),
        {'/c/IMG.xmp -> 2026/IMG.xmp', '/c/IMG.thm -> 2026/IMG.thm'},
      );
    });

    test('companions inherit the de-duplicated photo basename', () {
      final plan = buildPlan(
        sources: [
          IngestSource(
            path: '/c/1/IMG.arw',
            capturedAt: DateTime(2026),
            companions: ['/c/1/IMG.xmp'],
          ),
          IngestSource(
            path: '/c/2/IMG.arw',
            capturedAt: DateTime(2026),
            companions: ['/c/2/IMG.xmp'],
          ),
        ],
        template: const RenameTemplate('{YYYY}/{origname}'),
      );

      // Second photo de-duplicates to IMG_2.arw → its xmp follows to IMG_2.xmp.
      expect(plan.items[1].relPath, '2026/IMG_2.arw');
      expect(plan.items[1].companions.single.relPath, '2026/IMG_2.xmp');
    });

    test('commonSubfolder is the shared dated-shoot folder', () {
      final plan = buildPlan(
        sources: [
          IngestSource(
            path: '/card/a.arw',
            capturedAt: DateTime(2026, 7, 6, 10),
          ),
          IngestSource(
            path: '/card/b.arw',
            capturedAt: DateTime(2026, 7, 6, 11),
          ),
        ],
        template: RenameTemplate.datedShoot,
        shoot: 'Wedding',
      );

      expect(plan.commonSubfolder, '2026/2026-07-06_Wedding');
    });

    test('commonSubfolder is null for a flat (no sub-folder) template', () {
      final plan = buildPlan(
        sources: [
          IngestSource(path: '/card/a.arw', capturedAt: DateTime(2026)),
        ],
        template: RenameTemplate.keepNames,
      );

      expect(plan.commonSubfolder, isNull);
    });

    test(
      'commonSubfolder is null when items span more than one sub-folder',
      () {
        final plan = buildPlan(
          sources: [
            IngestSource(path: '/card/a.arw', capturedAt: DateTime(2026, 7, 5)),
            IngestSource(path: '/card/b.arw', capturedAt: DateTime(2026, 7, 6)),
          ],
          template: const RenameTemplate('{YYYY}/{YYYY-MM-DD}/{origname}'),
        );

        expect(plan.commonSubfolder, isNull);
      },
    );

    test('totalBytes sums the source sizes', () {
      final plan = buildPlan(
        sources: [
          IngestSource(
            path: '/c/a.arw',
            capturedAt: DateTime(2026),
            sizeBytes: 1000,
          ),
          IngestSource(
            path: '/c/b.arw',
            capturedAt: DateTime(2026, 1, 2),
            sizeBytes: 2500,
          ),
        ],
        template: RenameTemplate.keepNames,
      );
      expect(plan.totalBytes, 3500);
    });
  });

  group('runIngest', () {
    late Directory tmp;
    setUp(
      () async => tmp = await Directory.systemTemp.createTemp('ingest_run'),
    );
    tearDown(() async => tmp.delete(recursive: true));

    test('copies every item into the destination root(s)', () async {
      final s1 = File(p.join(tmp.path, 's1.txt'))..writeAsStringSync('one');
      final s2 = File(p.join(tmp.path, 's2.txt'))..writeAsStringSync('two');
      final destA = p.join(tmp.path, 'A');
      final destB = p.join(tmp.path, 'B');

      final plan = IngestPlan([
        IngestItem(source: s1.path, relPath: '2026/s1.txt', sizeBytes: 3),
        IngestItem(source: s2.path, relPath: '2026/s2.txt', sizeBytes: 3),
      ]);

      final ticks = await runIngest(
        plan: plan,
        destinationRoots: [destA, destB],
        copier: verifiedCopy, // direct, no isolate
      ).toList();

      expect(ticks.last.done, 2);
      expect(ticks.last.total, 2);
      expect(ticks.last.bytesDone, 6); // 3 + 3 bytes copied (for the speed UI)
      final summary = IngestSummary([for (final t in ticks) t.last]);
      expect(summary.copied, 2);
      expect(summary.allOk, isTrue);
      // Landed in both destinations.
      expect(File(p.join(destA, '2026', 's1.txt')).readAsStringSync(), 'one');
      expect(File(p.join(destB, '2026', 's2.txt')).readAsStringSync(), 'two');
    });

    test('runs concurrently and still copies every file', () async {
      final sources = [
        for (var i = 0; i < 6; i++)
          File(p.join(tmp.path, 's$i.txt'))..writeAsStringSync('file $i'),
      ];
      final dest = p.join(tmp.path, 'out');
      final plan = IngestPlan([
        for (var i = 0; i < sources.length; i++)
          IngestItem(source: sources[i].path, relPath: '$i.txt'),
      ]);

      final ticks = await runIngest(
        plan: plan,
        destinationRoots: [dest],
        concurrency: 3,
        copier: verifiedCopy,
      ).toList();

      // Every file is reported once and every file lands on disk.
      expect(ticks.length, 6);
      expect(ticks.last.done, 6);
      expect(IngestSummary([for (final t in ticks) t.last]).copied, 6);
      for (var i = 0; i < 6; i++) {
        expect(File(p.join(dest, '$i.txt')).readAsStringSync(), 'file $i');
      }
    });

    test('copies companion sidecars alongside the media', () async {
      final media = File(p.join(tmp.path, 'IMG.arw'))..writeAsStringSync('raw');
      final xmp = File(p.join(tmp.path, 'IMG.xmp'))
        ..writeAsStringSync('<xmp/>');
      final dest = p.join(tmp.path, 'out');
      final plan = IngestPlan([
        IngestItem(
          source: media.path,
          relPath: '2026/IMG.arw',
          companions: [(source: xmp.path, relPath: '2026/IMG.xmp')],
        ),
      ]);

      await runIngest(
        plan: plan,
        destinationRoots: [dest],
        copier: verifiedCopy,
      ).drain<void>();

      expect(File(p.join(dest, '2026', 'IMG.arw')).readAsStringSync(), 'raw');
      expect(
        File(p.join(dest, '2026', 'IMG.xmp')).readAsStringSync(),
        '<xmp/>',
      );
    });

    test('summary counts a missing source as failed', () async {
      final plan = IngestPlan([
        IngestItem(source: p.join(tmp.path, 'gone.txt'), relPath: 'x.txt'),
      ]);

      final ticks = await runIngest(
        plan: plan,
        destinationRoots: [p.join(tmp.path, 'out')],
        copier: verifiedCopy,
      ).toList();

      final summary = IngestSummary([for (final t in ticks) t.last]);
      expect(summary.failed, 1);
      expect(summary.allOk, isFalse);
    });
  });

  group('captureDateCounts / excludeCaptureDates', () {
    final sources = [
      IngestSource(path: '/c/a.jpg', capturedAt: DateTime(2026, 7, 6, 9)),
      IngestSource(path: '/c/b.jpg', capturedAt: DateTime(2026, 7, 6, 18)),
      IngestSource(path: '/c/old.jpg', capturedAt: DateTime(2020, 1, 1, 12)),
    ];

    test('groups by day (time truncated) and sorts oldest first', () {
      final counts = captureDateCounts(sources);

      expect(counts.map((e) => e.key), [
        DateTime(2020),
        DateTime(2026, 7, 6),
      ]);
      expect(counts.map((e) => e.value), [1, 2]);
    });

    test('excludeCaptureDates with an empty set returns everything', () {
      expect(excludeCaptureDates(sources, {}), sources);
    });

    test('excludeCaptureDates drops only the matching day', () {
      final filtered = excludeCaptureDates(sources, {DateTime(2020)});

      expect(filtered.map((s) => s.path), ['/c/a.jpg', '/c/b.jpg']);
    });
  });
}
