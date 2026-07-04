import 'package:cullimingo/features/metadata/domain/code_replacements.dart';
import 'package:cullimingo/features/metadata/presentation/code_table_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Tree order of TextFields: delimiter (0), row0 code (1), row0 repl (2),
  // preview (3). An empty table opens with one blank row.
  const delimiterIndex = 0;
  const codeIndex = 1;
  const replIndex = 2;
  const previewIndex = 3;

  Future<CodeReplacements> run(
    WidgetTester tester,
    CodeReplacements initial,
    Future<void> Function(WidgetTester) interact,
  ) async {
    CodeReplacements? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showCodeTableEditor(context, initial: initial);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await interact(tester);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    return result!;
  }

  testWidgets('a typed code + alternates is saved as a list', (tester) async {
    final result = await run(tester, const CodeReplacements(), (t) async {
      await t.enterText(find.byType(TextField).at(codeIndex), 'ff');
      await t.enterText(
        find.byType(TextField).at(replIndex),
        'staff | Jane Smith',
      );
    });

    expect(result.codes, {
      'ff': ['staff', 'Jane Smith'],
    });
    expect(result.delimiter, '=');
  });

  testWidgets('the preview expands live as you type', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showCodeTableEditor(
                context,
                initial: const CodeReplacements(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(codeIndex), 'lbj');
    await tester.enterText(
      find.byType(TextField).at(replIndex),
      'LeBron James',
    );
    await tester.enterText(find.byType(TextField).at(previewIndex), '=lbj=');
    await tester.pump();

    // The preview output is a Text widget (not the repl field's EditableText).
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && w.data == 'LeBron James',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a custom delimiter round-trips', (tester) async {
    final result = await run(tester, const CodeReplacements(), (t) async {
      await t.enterText(find.byType(TextField).at(delimiterIndex), '%');
      await t.enterText(find.byType(TextField).at(codeIndex), 'yr');
      await t.enterText(find.byType(TextField).at(replIndex), '2026');
    });

    expect(result.delimiter, '%');
    expect(result.codes['yr'], ['2026']);
  });
}
