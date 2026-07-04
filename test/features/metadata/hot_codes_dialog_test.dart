import 'package:cullimingo/features/metadata/domain/hot_codes.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/features/metadata/presentation/hot_codes_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<HotCodes? Function()> open(
    WidgetTester tester,
    HotCodes initial,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    HotCodes? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showHotCodesEditor(context, initial: initial);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  testWidgets('creating a hot code from scratch', (tester) async {
    final result = await open(tester, const HotCodes());

    // The empty table seeds one blank entry with a City field row.
    await tester.enterText(find.widgetWithText(TextField, 'e.g. arena'), 'hq');
    await tester.enterText(find.widgetWithText(TextField, 'value'), 'Bonn');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result()!.codes, {
      'hq': {IptcField.city: 'Bonn'},
    });
  });

  testWidgets('an existing table is rendered and editable', (tester) async {
    const initial = HotCodes(
      codes: {
        'arena': {IptcField.city: 'München', IptcField.state: 'Bayern'},
      },
    );
    final result = await open(tester, initial);

    expect(find.text('Hot codes'), findsOneWidget);
    // Both field rows render with their values.
    expect(find.widgetWithText(TextField, 'München'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Bayern'), findsOneWidget);

    // Add a third field to the code (prefills the first unused field).
    await tester.tap(find.text('Add field'));
    await tester.pumpAndSettle();
    // `.last` = the freshly added row (hint Texts exist on filled fields too).
    await tester.enterText(
      find.widgetWithText(TextField, 'value').last,
      'Allianz Arena',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final code = result()!.codes['arena']!;
    expect(code[IptcField.city], 'München');
    expect(code[IptcField.state], 'Bayern');
    // The new row defaulted to the first field not yet used (caption).
    expect(code[IptcField.caption], 'Allianz Arena');
  });

  testWidgets('blank names and empty values are dropped on save', (
    tester,
  ) async {
    final result = await open(tester, const HotCodes());
    // Leave the seeded blank row untouched.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result()!.isEmpty, isTrue);
  });

  testWidgets('Cancel returns null', (tester) async {
    final result = await open(tester, const HotCodes());
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result(), isNull);
  });
}
