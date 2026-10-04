import 'package:cullimingo/core/files/destination_check.dart';
import 'package:cullimingo/core/files/verified_copy.dart';
import 'package:cullimingo/features/ingest/data/ingest_service.dart';
import 'package:cullimingo/features/ingest/presentation/ingest_dialog.dart';
import 'package:cullimingo/features/library/data/folder_scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// The import dialog's safety warnings (#9), driven with fake scan, check and
// copy steps — the real ones run on background isolates, which a widget
// test's fake clock never sees finish.

const _card = '/fake/card';
const _dest = '/fake/dest';

final _shot = DateTime(2026, 9, 1, 12);

SourceScan _scanWith({List<ScanProblem> unreadable = const []}) => SourceScan(
  [
    IngestSource(
      path: '$_card/DCIM/A001.ARW',
      capturedAt: _shot,
      sizeBytes: 10,
    ),
    IngestSource(
      path: '$_card/DCIM/A002.ARW',
      capturedAt: _shot,
      sizeBytes: 10,
    ),
  ],
  unreadable: unreadable,
);

const _locked = [
  ScanProblem('$_card/PRIVATE', 'Permission denied'),
  ScanProblem('$_card/DCIM/101', 'listing stalled (device unresponsive)'),
];

Future<DestinationCheck> _ok({
  required List<String> roots,
  required List<PlannedCopy> files,
  Map<String, String> rememberedMounts = const {},
}) async => const DestinationCheck();

Future<void> _pumpDialog(
  WidgetTester tester, {
  required SourceScan scan,
  Future<DestinationCheck> Function({
        required List<String> roots,
        required List<PlannedCopy> files,
        Map<String, String> rememberedMounts,
      })
      check =
      _ok,
  Copier? copier,
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: IngestDialog(
            initialSource: _card,
            initialDestination: _dest,
            volumeSearchRoots: const ['/cm-no-root'],
            scan: (_) async => scan,
            destinationChecker: check,
            copier: copier,
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
}

/// Lets the dialog's real async I/O (settings load, volume listing) finish:
/// the widget tester's fake clock alone never completes it.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _import(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Import 2 photos'));
  await _settle(tester);
}

void main() {
  testWidgets('warns before importing when part of the card is unreadable', (
    tester,
  ) async {
    await _pumpDialog(tester, scan: _scanWith(unreadable: _locked));

    expect(
      find.byKey(const ValueKey('ingest-unreadable-warning')),
      findsOneWidget,
    );
    expect(
      find.textContaining("2 items on the source couldn't be read"),
      findsOneWidget,
    );
    expect(find.textContaining("Don't format the card"), findsOneWidget);
    // Paths are shown relative to the card, with the OS reason.
    expect(find.text('• PRIVATE: Permission denied'), findsOneWidget);
    // The readable files can still be imported.
    expect(
      find.widgetWithText(FilledButton, 'Import 2 photos'),
      findsOneWidget,
    );
  });

  testWidgets('a fully readable card shows no warning', (tester) async {
    await _pumpDialog(tester, scan: _scanWith());

    expect(
      find.byKey(const ValueKey('ingest-unreadable-warning')),
      findsNothing,
    );
  });

  testWidgets('the summary carries unreadable and still-being-written files', (
    tester,
  ) async {
    Future<CopyResult> copier({
      required String source,
      required List<String> destinations,
      bool verify = true,
      Set<String> alwaysVerify = const {},
    }) async => CopyResult(
      source: source,
      outcome: source.endsWith('A002.ARW')
          ? CopyOutcome.sourceBusy
          : CopyOutcome.copied,
      message: source.endsWith('A002.ARW') ? 'Changed seconds ago' : null,
    );

    await _pumpDialog(
      tester,
      scan: _scanWith(unreadable: _locked),
      copier: copier,
    );
    await _import(tester);

    expect(find.text("Couldn't read on the source"), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ingest-summary-unreadable')),
      findsOneWidget,
    );
    expect(find.text('Still being written (import again)'), findsOneWidget);
    // Never "complete" while part of the card was never imported.
    expect(find.text('Import complete'), findsNothing);
    expect(find.text('Import finished with issues'), findsOneWidget);
  });

  testWidgets('destination problems stop the run and show under Destination', (
    tester,
  ) async {
    var copies = 0;
    Future<CopyResult> copier({
      required String source,
      required List<String> destinations,
      bool verify = true,
      Set<String> alwaysVerify = const {},
    }) async {
      copies++;
      return CopyResult(source: source, outcome: CopyOutcome.copied);
    }

    Future<DestinationCheck> refuse({
      required List<String> roots,
      required List<PlannedCopy> files,
      Map<String, String> rememberedMounts = const {},
    }) async => const DestinationCheck(
      problems: ["dest: its drive isn't connected (expected at /mnt/photos)."],
    );

    await _pumpDialog(
      tester,
      scan: _scanWith(),
      check: refuse,
      copier: copier,
    );
    await _import(tester);

    expect(find.textContaining("its drive isn't connected"), findsOneWidget);
    expect(copies, 0);
    // Back to the plan, ready to retry once the drive is connected.
    expect(
      find.widgetWithText(FilledButton, 'Import 2 photos'),
      findsOneWidget,
    );
  });
}
