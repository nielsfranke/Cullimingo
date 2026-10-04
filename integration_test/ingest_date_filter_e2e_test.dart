// Manual end-to-end verification of the ingest dialog's per-day capture-date
// filter. Runs the REAL `IngestDialog` (real Isolate.run-based scan) via the
// integration_test harness — a plain `testWidgets()` widget test can't do this:
// `AutomatedTestWidgetsFlutterBinding`'s pump loop never observes a real
// cross-isolate result, so `scanSources` (which hops to a background isolate)
// never completes and the test hangs forever. Not part of CI.
import 'dart:io';

import 'package:cullimingo/features/ingest/presentation/ingest_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

/// Pumps until [finder] matches — the scan runs on real isolates (and reads
/// EXIF for every file), so a fixed wait is either flaky or slow.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('timed out waiting for $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('multi-day card shows day chips; toggling filters the plan', (
    tester,
  ) async {
    final card = await Directory(
      p.join(Platform.environment['HOME']!, '.cache'),
    ).createTemp('cullimingo_e2e_dates');
    addTearDown(() => card.deleteSync(recursive: true));

    File(p.join(card.path, 'a.jpg')).writeAsBytesSync([0]);
    File(p.join(card.path, 'b.jpg')).writeAsBytesSync([0]);
    File(p.join(card.path, 'old.jpg'))
      ..writeAsBytesSync([0])
      ..setLastModifiedSync(DateTime(2020, 1, 1, 12));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: IngestDialog(
              initialSource: card.path,
              volumeSearchRoots: const ['/no-such-root'],
            ),
          ),
        ),
      ),
    );
    // Real isolate scan — wait for the plan, in real wall-clock time.
    await pumpUntil(tester, find.text('Import 3 photos'));

    expect(find.text('Days on this card — 2 of 2 included'), findsOneWidget);
    expect(find.text('Jan 1 · 1'), findsOneWidget);

    await tester.tap(find.text('Jan 1 · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Import 2 photos'), findsOneWidget);
    expect(find.text('Days on this card — 1 of 2 included'), findsOneWidget);

    await tester.tap(find.text('Jan 1 · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Import 3 photos'), findsOneWidget);
  });

  testWidgets('single-day card shows no day-filter row', (tester) async {
    final card = await Directory(
      p.join(Platform.environment['HOME']!, '.cache'),
    ).createTemp('cullimingo_e2e_single_day');
    addTearDown(() => card.deleteSync(recursive: true));

    File(p.join(card.path, 'a.jpg')).writeAsBytesSync([0]);
    File(p.join(card.path, 'b.jpg')).writeAsBytesSync([0]);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: IngestDialog(
              initialSource: card.path,
              volumeSearchRoots: const ['/no-such-root'],
            ),
          ),
        ),
      ),
    );
    await pumpUntil(tester, find.text('Import 2 photos'));

    expect(find.textContaining('Days on this card'), findsNothing);
  });
}
