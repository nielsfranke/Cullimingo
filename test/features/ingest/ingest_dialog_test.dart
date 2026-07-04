import 'package:cullimingo/features/ingest/presentation/ingest_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the form, preset, and empty-source preview', (
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
    // The default naming preset is selected in the builder's dropdown.
    expect(find.text('Year / date_shoot / name'), findsWidgets);
    expect(find.text('No photos found in the source.'), findsOneWidget);

    // With no source/destination chosen, the Import action is disabled.
    final importButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Import'),
    );
    expect(importButton.onPressed, isNull);
  });
}
