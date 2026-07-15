import 'package:cullimingo/features/ingest/presentation/ingest_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the card layout, preset, and footer guidance', (
    tester,
  ) async {
    // A non-existent search root → no volumes and no auto-selected source, and
    // only synchronous existsSync I/O (safe under the widget tester's clock).
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: IngestDialog(volumeSearchRoots: ['/cm-no-root']),
          ),
        ),
      ),
    );
    await tester.pump(); // volume scan (sync) settles

    expect(find.text('Import photos'), findsOneWidget);
    // The three cards of the what → where → named-how flow.
    expect(find.text('SOURCE'), findsOneWidget);
    expect(find.text('DESTINATION'), findsOneWidget);
    expect(find.text('NAMING'), findsOneWidget);
    // The default naming preset is selected in the builder's dropdown.
    expect(find.text('Year / date_shoot / name'), findsWidgets);
    // With no source, the source card says what to do next…
    expect(find.text('Select a card or folder to scan.'), findsOneWidget);
    // …and the footer explains why Import is greyed out.
    expect(find.text('Select a source above'), findsOneWidget);

    // The default preset uses the Job-name element, so its row is visible.
    expect(find.text('Job name'), findsOneWidget);
    // The pattern editor is collapsed behind the disclosure by default.
    expect(find.text('Customise filename & folders'), findsOneWidget);
    expect(find.text('Filename'), findsNothing);

    // With no source/destination chosen, the Import action is disabled.
    final importButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Import'),
    );
    expect(importButton.onPressed, isNull);
  });
}
