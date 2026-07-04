import 'dart:io';

import 'package:cullimingo/features/metadata/data/template_file.dart';
import 'package:cullimingo/features/metadata/domain/code_replacements.dart';
import 'package:cullimingo/features/metadata/domain/hot_codes.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/features/metadata/domain/iptc_template.dart';
import 'package:cullimingo/features/metadata/domain/template_snapshots.dart';
import 'package:cullimingo/features/metadata/presentation/iptc_clipboard.dart';
import 'package:cullimingo/features/metadata/presentation/iptc_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Fields render in IptcField.values order, so the enum index is the TextField
  // index (caption = 0, credit = 10).
  final captionIndex = IptcField.values.indexOf(IptcField.caption);

  /// The text field of an IPTC field, found by its stable [ValueKey] (fields
  /// live behind the nav-rail sections, so index-based finders don't hold).
  Finder fieldOf(IptcField f) => find.descendant(
    of: find.byKey(ValueKey(f)),
    matching: find.byType(TextField),
  );

  /// Taps a nav-rail section by its label and settles.
  Future<void> selectSection(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  /// Pumps the dialog directly over [targets] (no providers needed).
  Future<void> open(WidgetTester tester, List<IptcCore> targets) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IptcEditorDialog(targets: targets, count: targets.length),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('single edit pops only the changed field', (tester) async {
    late Map<IptcField, String>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<Map<IptcField, String>>(
                  context: context,
                  builder: (_) => const IptcEditorDialog(
                    targets: [IptcCore(caption: 'Old', credit: 'AP')],
                    count: 1,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // No batch banner for a single photo.
    expect(find.textContaining('Editing'), findsNothing);

    await tester.enterText(
      find.byType(TextField).at(captionIndex),
      'New caption',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result, {IptcField.caption: 'New caption'});
  });

  testWidgets('Escape cancels the dialog even with a text field focused', (
    tester,
  ) async {
    var completed = false;
    Map<IptcField, String>? result = {IptcField.caption: 'sentinel'};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<Map<IptcField, String>>(
                  context: context,
                  barrierDismissible: false, // matches production
                  builder: (_) => const IptcEditorDialog(
                    targets: [IptcCore(caption: 'Old')],
                    count: 1,
                  ),
                );
                completed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Type into (and thus focus) the caption field, then press Escape.
    await tester.enterText(find.byType(TextField).at(captionIndex), 'edited');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Dialog closed as a cancel: no changes returned, edits discarded.
    expect(find.text('Metadata'), findsNothing);
    expect(completed, isTrue);
    expect(result, isNull);
  });

  testWidgets(
    'batch shows the banner and a Mixed hint for disagreeing fields',
    (
      tester,
    ) async {
      await open(tester, const [
        IptcCore(caption: 'One', credit: 'AP'),
        IptcCore(caption: 'Two', credit: 'AP'),
      ]);

      expect(find.textContaining('Editing 2 photos'), findsOneWidget);
      // Caption disagrees → a Mixed hint is shown on its field.
      expect(find.textContaining('Mixed'), findsWidgets);
      // Structured tables are per-photo (serial) only — hidden in batch.
      expect(find.text('Tables'), findsNothing);
    },
  );

  testWidgets('a shared batch value is prefilled, not shown as Mixed', (
    tester,
  ) async {
    await open(tester, const [
      IptcCore(caption: 'One', credit: 'AP'),
      IptcCore(caption: 'Two', credit: 'AP'),
    ]);

    // credit agrees across both → prefilled, editable as one value.
    await selectSection(tester, 'Rights');
    final creditField = tester.widget<TextField>(fieldOf(IptcField.credit));
    expect(creditField.controller!.text, 'AP');
  });

  testWidgets('batch writes only touched fields, leaving mixed ones alone', (
    tester,
  ) async {
    late Map<IptcField, String>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<Map<IptcField, String>>(
                  context: context,
                  builder: (_) => const IptcEditorDialog(
                    targets: [
                      IptcCore(caption: 'One'),
                      IptcCore(caption: 'Two'),
                    ],
                    count: 2,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Touch only credit; leave the mixed caption alone.
    await selectSection(tester, 'Rights');
    await tester.enterText(fieldOf(IptcField.credit), 'Reuters');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result, {IptcField.credit: 'Reuters'});
  });

  testWidgets(
    'Copy snapshots the fields; Paste overwrites from the clipboard',
    (
      tester,
    ) async {
      iptcClipboard.value = null;
      addTearDown(() => iptcClipboard.value = null);
      await open(tester, const [IptcCore(caption: 'One', credit: 'AP')]);

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      // Change the caption, then paste the copied snapshot back over it.
      await tester.enterText(fieldOf(IptcField.caption), 'Changed');
      await tester.tap(find.text('Paste'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(fieldOf(IptcField.caption)).controller!.text,
        'One',
      );
    },
  );

  testWidgets('⌘⇧C / ⌘⇧V copy and paste the IPTC fields via keyboard', (
    tester,
  ) async {
    iptcClipboard.value = null;
    addTearDown(() => iptcClipboard.value = null);

    Future<void> chord(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
    }

    await open(tester, const [IptcCore(caption: 'One')]);

    await chord(LogicalKeyboardKey.keyC);
    expect(iptcClipboard.value?[IptcField.caption], 'One');

    await tester.enterText(fieldOf(IptcField.caption), 'Changed');
    await chord(LogicalKeyboardKey.keyV);
    expect(
      tester.widget<TextField>(fieldOf(IptcField.caption)).controller!.text,
      'One',
    );
  });

  group('live =code= expansion', () {
    const codes = CodeReplacements(
      codes: {
        'cabral': ['Anna Cabral', 'Cabral (POR)'],
      },
    );

    Future<TextEditingController> captionAfterTyping(
      WidgetTester tester,
      String input,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: IptcEditorDialog(
              targets: [IptcCore()],
              count: 1,
              codes: codes,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final caption = find.byType(TextField).at(captionIndex);
      await tester.enterText(caption, input);
      await tester.pump();
      return tester.widget<TextField>(caption).controller!;
    }

    testWidgets('a defined code expands as soon as it is closed', (
      tester,
    ) async {
      final c = await captionAfterTyping(tester, '=cabral= wins');
      expect(c.text, 'Anna Cabral wins');
      // The caret follows the expansion (it was at the end of the typed text).
      expect(c.selection.baseOffset, 'Anna Cabral wins'.length);
    });

    testWidgets('#n selects an alternate replacement', (tester) async {
      final c = await captionAfterTyping(tester, '=cabral#2=');
      expect(c.text, 'Cabral (POR)');
    });

    testWidgets('an unknown code is left as written', (tester) async {
      final c = await captionAfterTyping(tester, '=nadal= wins');
      expect(c.text, '=nadal= wins');
    });

    testWidgets('an unclosed code does not expand yet', (tester) async {
      final c = await captionAfterTyping(tester, '=cabral');
      expect(c.text, '=cabral');
    });
  });

  group('hot codes', () {
    const hot = HotCodes(
      codes: {
        'arena': {
          IptcField.city: 'München',
          IptcField.state: 'Bayern',
          IptcField.country: 'Germany',
          // The value of a hot field may itself hold a text code.
          IptcField.credit: '=wire=',
          // …and map the field the user is typing in (must NOT clobber it).
          IptcField.caption: 'should not overwrite',
        },
      },
    );
    const codes = CodeReplacements(
      codes: {
        'wire': ['Associated Press'],
      },
    );

    String textOf(WidgetTester tester, IptcField f) =>
        tester.widget<TextField>(fieldOf(f)).controller!.text;

    testWidgets('typing a hot code fills its fields and strips the token', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: IptcEditorDialog(
              targets: [IptcCore()],
              count: 1,
              codes: codes,
              hotCodes: hot,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Type the hot code on the Content section (caption lives there).
      await tester.enterText(
        fieldOf(IptcField.caption),
        '=arena= injury time',
      );
      await tester.pump();

      // Token gone, remainder kept — the caption mapping was skipped.
      expect(textOf(tester, IptcField.caption), ' injury time');

      // The hot code filled fields in other sections; navigate to read them.
      await selectSection(tester, 'Location');
      expect(textOf(tester, IptcField.city), 'München');
      expect(textOf(tester, IptcField.state), 'Bayern');
      expect(textOf(tester, IptcField.country), 'Germany');
      await selectSection(tester, 'Rights');
      // The nested text code inside the hot value expanded immediately.
      expect(textOf(tester, IptcField.credit), 'Associated Press');
    });
  });

  group('Clear / Load / Save as template', () {
    String textOf(WidgetTester tester, IptcField f) =>
        tester.widget<TextField>(fieldOf(f)).controller!.text;

    /// Pumps the dialog via showDialog (so Save pops) and returns the changes.
    Future<Map<IptcField, String>?> run(
      WidgetTester tester,
      List<IptcCore> targets,
      Future<void> Function(WidgetTester) interact, {
      TemplateSnapshots templates = const TemplateSnapshots(),
      Future<void> Function(String, IptcTemplate)? onSaveTemplate,
      Future<String?> Function()? pickTemplatePath,
    }) async {
      Map<IptcField, String>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showDialog<Map<IptcField, String>>(
                    context: context,
                    builder: (_) => IptcEditorDialog(
                      targets: targets,
                      count: targets.length,
                      templates: templates,
                      onSaveTemplate: onSaveTemplate,
                      pickTemplatePath: pickTemplatePath,
                    ),
                  );
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
      return result;
    }

    testWidgets('Clear empties the fields; Save writes the clears through', (
      tester,
    ) async {
      final result = await run(
        tester,
        const [IptcCore(caption: 'Old', credit: 'AP')],
        (t) async {
          await t.tap(find.text('Clear'));
          await t.pumpAndSettle();
          expect(textOf(t, IptcField.caption), isEmpty);
        },
      );

      // Both previously-filled fields changed to '' — a real clear on save.
      expect(result, {IptcField.caption: '', IptcField.credit: ''});
    });

    testWidgets('Load stamps a snapshot with its merge modes', (tester) async {
      const wire = IptcTemplate(
        fields: {IptcField.credit: 'AP', IptcField.caption: '(staff)'},
        textModes: {IptcField.caption: TextApplyMode.append},
      );
      const templates = TemplateSnapshots(
        snapshots: [TemplateSnapshot(name: 'Wire', template: wire)],
        activeName: 'Wire',
      );

      final result = await run(
        tester,
        const [IptcCore(caption: 'Goal')],
        templates: templates,
        (t) async {
          await t.tap(find.text('Load'));
          await t.pumpAndSettle();
          await t.tap(find.text('Wire'));
          await t.pumpAndSettle();
          // Append mode merged into the existing caption; credit replaced.
          expect(textOf(t, IptcField.caption), 'Goal (staff)');
        },
      );

      expect(result, {
        IptcField.caption: 'Goal (staff)',
        IptcField.credit: 'AP',
      });
    });

    testWidgets('Load → From XMP file… stamps a PM template file', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('cullimingo_m_editor');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/wire.xmp';
      File(path).writeAsStringSync(
        templateToXmpSource(
          const IptcTemplate(fields: {IptcField.credit: 'AP'}),
        ),
      );

      final result = await run(
        tester,
        const [IptcCore(caption: 'Kept')],
        pickTemplatePath: () async => path,
        (t) async {
          await t.tap(find.text('Load'));
          await t.pumpAndSettle();
          await t.tap(find.text('From XMP file…'));
          // The parse runs in a real isolate — let it finish outside fake
          // async.
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)),
          );
          await t.pumpAndSettle();
        },
      );

      // Credit stamped from the file; the caption the template doesn't carry
      // was left alone (so it isn't a change on save).
      expect(result, {IptcField.credit: 'AP'});
    });

    testWidgets('Save as… prompts for a name and hands over the template', (
      tester,
    ) async {
      String? savedName;
      IptcTemplate? savedTemplate;

      await run(
        tester,
        const [IptcCore(caption: 'Cap', credit: 'AP')],
        onSaveTemplate: (name, template) async {
          savedName = name;
          savedTemplate = template;
        },
        (t) async {
          await t.tap(find.text('Save as…'));
          await t.pumpAndSettle();
          await t.enterText(
            find.descendant(
              of: find.byType(AlertDialog).last,
              matching: find.byType(TextField),
            ),
            'Client',
          );
          await t.tap(find.text('OK'));
          await t.pumpAndSettle();
        },
      );

      expect(savedName, 'Client');
      expect(savedTemplate!.fields, {
        IptcField.caption: 'Cap',
        IptcField.credit: 'AP',
      });
    });

    testWidgets('Load and Save as… are hidden without wiring', (tester) async {
      await run(tester, const [IptcCore()], (t) async {
        expect(find.text('Load'), findsNothing);
        expect(find.text('Save as…'), findsNothing);
        expect(find.text('Clear'), findsOneWidget);
      });
    });
  });
}
