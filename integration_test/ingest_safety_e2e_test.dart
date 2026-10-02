// Manual end-to-end verification of the import dialog's safety fixes (1.3.5).
// Runs the REAL `IngestDialog` inside a real dialog route (as `_ingest` opens
// it), with real isolate scans and copies — see
// `ingest_date_filter_e2e_test.dart` for why a plain widget test can't.
// Not part of CI. Linux:
//
//   SMALL_FS=<tiny tmpfs mount> flutter test \
//     integration_test/ingest_safety_e2e_test.dart -d linux
//
// The full-destination case is skipped without SMALL_FS. Writes the app's
// real settings.json (destination, last-import options) — back it up first
// on a machine you use.
import 'dart:convert';
import 'dart:io';

import 'package:cullimingo/features/ingest/presentation/ingest_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory scratch;
  setUp(() async {
    scratch = await Directory(
      p.join(Platform.environment['HOME']!, '.cache'),
    ).createTemp('cullimingo_e2e_ingest');
  });
  tearDown(() => scratch.deleteSync(recursive: true));

  /// Pre-fills the destination the dialog loads (the picker can't be driven).
  Future<void> useDestination(String dest) async {
    final dir = await getApplicationSupportDirectory();
    dir.createSync(recursive: true);
    File(
      p.join(dir.path, 'settings.json'),
    ).writeAsStringSync(jsonEncode({'lastDestination': dest}));
  }

  /// A camera card under [root]: `<name>/DCIM` with [count] JPEG-named files
  /// of [bytes] each (content is irrelevant to the copy).
  Directory card(String root, String name, int count, {int bytes = 16}) {
    final dcim = Directory(p.join(root, name, 'DCIM'))
      ..createSync(recursive: true);
    final data = Uint8List(bytes);
    for (var i = 0; i < count; i++) {
      File(p.join(dcim.path, 'IMG_$i.JPG')).writeAsBytesSync(data);
    }
    return Directory(p.join(root, name));
  }

  /// Opens the dialog the way the app does: a dismissible dialog route.
  Future<void> openDialog(WidgetTester tester, String volumesRoot) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showDialog<String>(
                    context: context,
                    builder: (_) =>
                        IngestDialog(volumeSearchRoots: [volumesRoot]),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
  }

  /// Pumps real frames until [finder] matches (real isolate work behind it).
  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final end = DateTime.now().add(timeout);
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) {
        final shown = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .whereType<String>()
            .join(' | ');
        fail('timed out waiting for $finder; on screen: $shown');
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The number in the summary row labelled [label].
  int stat(WidgetTester tester, String label) {
    final row = find.ancestor(of: find.text(label), matching: find.byType(Row));
    final texts = tester
        .widgetList<Text>(
          find.descendant(of: row.first, matching: find.byType(Text)),
        )
        .map((t) => t.data ?? '');
    return int.parse(texts.last);
  }

  FilledButton importButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton));

  testWidgets('switching cards disables Import until the new card is scanned', (
    tester,
  ) async {
    final volumes = Directory(p.join(scratch.path, 'volumes'))..createSync();
    card(volumes.path, 'cardA', 3);
    // Big enough that its scan is still running a frame after the switch.
    card(volumes.path, 'cardB', 20000);
    await useDestination(p.join(scratch.path, 'dest'));
    await openDialog(tester, volumes.path);

    // Card A is auto-selected and scanned.
    await waitFor(tester, find.text('Import 3 photos'));
    expect(importButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('cardA  •  card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('cardB  •  card').last);
    // One frame, before card B's scan isolate answers: card A's plan must
    // be gone and Import disabled (it used to say "Import 3 photos" here).
    await tester.pump();
    expect(find.text('Import 3 photos'), findsNothing);
    expect(find.text('Scanning…'), findsOneWidget);
    expect(importButton(tester).onPressed, isNull);

    await waitFor(tester, find.text('Import 20000 photos'));
    expect(importButton(tester).onPressed, isNotNull);
  });

  testWidgets(
    'mid-import: Escape and the barrier keep the dialog; Cancel reports '
    'what landed; unverified copies say so',
    (tester) async {
      final volumes = Directory(p.join(scratch.path, 'volumes'))..createSync();
      const total = 60;
      card(volumes.path, 'card', total, bytes: 16 * 1024 * 1024);
      final dest = p.join(scratch.path, 'dest');
      await useDestination(dest);
      await openDialog(tester, volumes.path);
      await waitFor(tester, find.text('Import $total photos'));

      // Verification off (the summary must not claim it).
      await tester.tap(find.text('Verify each copy by checksum (recommended)'));
      await tester.pump();
      await tester.tap(find.text('Import $total photos'));
      await waitFor(tester, find.textContaining('Copying '));

      // Escape and a click on the barrier used to close the dialog mid-run.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.tapAt(const Offset(4, 4));
      await tester.pump();
      expect(find.text('Import photos'), findsOneWidget);
      expect(find.text('Importing…'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await waitFor(tester, find.text('Import cancelled'));

      final copied = stat(tester, 'Copied (not verified)');
      final notCopied = stat(tester, 'Not copied (cancelled)');
      final onDisk = Directory(
        dest,
      ).listSync(recursive: true).whereType<File>().length;
      expect(find.text('Copied & verified'), findsNothing);
      expect(copied, greaterThan(0));
      expect(notCopied, greaterThan(0));
      expect(copied + notCopied, total);
      // Every file on disk is accounted for (in-flight copies were dropped
      // from the count before).
      expect(onDisk, copied);
    },
  );

  testWidgets(
    'a full destination fails the overflow cleanly instead of hanging',
    (tester) async {
      final small = Platform.environment['SMALL_FS'];
      if (small == null) {
        markTestSkipped('set SMALL_FS to a small tmpfs mount');
        return;
      }
      for (final e in Directory(small).listSync()) {
        e.deleteSync(recursive: true);
      }
      final volumes = Directory(p.join(scratch.path, 'volumes'))..createSync();
      const fileBytes = 4 * 1024 * 1024;
      card(volumes.path, 'card', 8, bytes: fileBytes);
      await useDestination(small);
      await openDialog(tester, volumes.path);
      await waitFor(tester, find.text('Import 8 photos'));

      await tester.tap(find.text('Import 8 photos'));
      // It used to sit on "Importing…" forever.
      await waitFor(tester, find.text('Import finished with issues'));

      expect(stat(tester, 'Failed'), greaterThan(0));
      final files = Directory(
        small,
      ).listSync(recursive: true).whereType<File>().toList();
      expect(stat(tester, 'Copied & verified'), files.length);
      // No truncated partial copies left behind.
      for (final f in files) {
        expect(f.lengthSync(), fileBytes, reason: f.path);
      }
    },
  );
}
