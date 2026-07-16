import 'dart:io';

import 'package:cullimingo/core/files/verified_copy.dart';
import 'package:cullimingo/features/handoff/data/transfer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('transfer'));
  tearDown(() async => tmp.delete(recursive: true));

  File src(String name, String content) =>
      File(p.join(tmp.path, name))..writeAsStringSync(content);

  String dest(String sub) => p.join(tmp.path, sub);

  group('buildTransferPlan', () {
    test('keeps basenames and de-duplicates within-batch clashes', () async {
      final a = src('a.arw', '1');
      // Same basename from a different folder → gets a _2 suffix.
      final other = Directory(p.join(tmp.path, 'sub'))..createSync();
      final b = File(p.join(other.path, 'a.arw'))..writeAsStringSync('2');

      final plan = await buildTransferPlan([a.path, b.path]);

      expect(plan.map((i) => i.relPath), ['a.arw', 'a_2.arw']);
    });

    test('pairs an existing .xmp sidecar, renamed to match', () async {
      final photo = src('DSC1.arw', 'raw');
      src('DSC1.xmp', '<xmp/>');

      final plan = await buildTransferPlan([photo.path]);

      expect(plan.single.sidecar, isNotNull);
      expect(p.basename(plan.single.sidecar!.source), 'DSC1.xmp');
      expect(plan.single.sidecar!.relPath, 'DSC1.xmp');
    });

    test('omits sidecars when includeSidecars is false', () async {
      final photo = src('DSC1.arw', 'raw');
      src('DSC1.xmp', '<xmp/>');

      final plan = await buildTransferPlan(
        [photo.path],
        includeSidecars: false,
      );

      expect(plan.single.sidecar, isNull);
    });
  });

  group('runTransfer copy', () {
    test(
      'copies the file (+ sidecar) and leaves the source in place',
      () async {
        final photo = src('DSC1.arw', 'raw-bytes');
        src('DSC1.xmp', 'sidecar');
        final out = dest('out');
        final plan = await buildTransferPlan([photo.path]);

        final ticks = await runTransfer(
          plan: plan,
          destinationRoot: out,
          mode: TransferMode.copy,
          copier: verifiedCopy, // direct, no isolate
        ).toList();

        expect(TransferSummary([for (final t in ticks) t.last]).transferred, 1);
        expect(File(p.join(out, 'DSC1.arw')).readAsStringSync(), 'raw-bytes');
        expect(File(p.join(out, 'DSC1.xmp')).readAsStringSync(), 'sidecar');
        // Copy leaves the originals untouched.
        expect(photo.existsSync(), isTrue);
        expect(File(p.join(tmp.path, 'DSC1.xmp')).existsSync(), isTrue);
      },
    );
  });

  group('runTransfer move', () {
    test('copies then deletes the source and its sidecar', () async {
      final photo = src('DSC1.arw', 'raw-bytes');
      final sidecar = src('DSC1.xmp', 'sidecar');
      final out = dest('out');
      final plan = await buildTransferPlan([photo.path]);

      await runTransfer(
        plan: plan,
        destinationRoot: out,
        mode: TransferMode.move,
        copier: verifiedCopy,
      ).toList();

      expect(File(p.join(out, 'DSC1.arw')).readAsStringSync(), 'raw-bytes');
      expect(File(p.join(out, 'DSC1.xmp')).readAsStringSync(), 'sidecar');
      // Move removes the originals once the copy verifies.
      expect(photo.existsSync(), isFalse);
      expect(sidecar.existsSync(), isFalse);
    });

    test('a name clash is left untouched and the source is kept', () async {
      final photo = src('DSC1.arw', 'new-bytes');
      final out = Directory(dest('out'))..createSync();
      // A different file already occupies the destination name.
      File(p.join(out.path, 'DSC1.arw')).writeAsStringSync('old-bytes');
      final plan = await buildTransferPlan([photo.path]);

      final ticks = await runTransfer(
        plan: plan,
        destinationRoot: out.path,
        mode: TransferMode.move,
        copier: verifiedCopy,
      ).toList();

      expect(ticks.single.last.outcome, CopyOutcome.conflict);
      // Destination not overwritten, source not deleted.
      expect(
        File(p.join(out.path, 'DSC1.arw')).readAsStringSync(),
        'old-bytes',
      );
      expect(photo.existsSync(), isTrue);
    });

    test(
      'transferring a file onto itself is a no-op skip, not a delete',
      () async {
        final photo = src('DSC1.arw', 'raw-bytes');
        // Destination root == source folder → dest path == source path.
        final plan = await buildTransferPlan(
          [photo.path],
          includeSidecars: false,
        );

        final ticks = await runTransfer(
          plan: plan,
          destinationRoot: tmp.path,
          mode: TransferMode.move,
          copier: verifiedCopy,
        ).toList();

        expect(ticks.single.last.outcome, CopyOutcome.skipped);
        // The only copy must survive.
        expect(photo.existsSync(), isTrue);
        expect(photo.readAsStringSync(), 'raw-bytes');
      },
    );
  });
}
