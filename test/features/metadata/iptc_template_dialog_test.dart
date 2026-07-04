import 'dart:io';

import 'package:cullimingo/features/metadata/data/template_file.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/features/metadata/domain/iptc_structured.dart';
import 'package:cullimingo/features/metadata/domain/iptc_template.dart';
import 'package:cullimingo/features/metadata/domain/recent_field_values.dart';
import 'package:cullimingo/features/metadata/presentation/iptc_template_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// The TextField inside a keyed template field.
  Finder fieldInput(IptcField field) => find.descendant(
    of: find.byKey(ValueKey(field)),
    matching: find.byType(TextField),
  );

  /// The "active" checkbox inside a keyed template field.
  Finder fieldCheckbox(IptcField field) => find.descendant(
    of: find.byKey(ValueKey(field)),
    matching: find.byType(Checkbox),
  );

  /// Taps the nav-rail section with [label] and settles.
  Future<void> goTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  /// Pumps the dialog over [initial] and returns the template it pops on Save
  /// (always non-null — every case taps Save).
  Future<IptcTemplate> run(
    WidgetTester tester,
    IptcTemplate initial,
    Future<void> Function(WidgetTester) interact, {
    RecentFieldValues recent = const RecentFieldValues(),
    Future<String?> Function()? pickLoadPath,
    Future<String?> Function()? pickSavePath,
  }) async {
    // A surface big enough for the fixed-size dialog to lay out.
    tester.view.physicalSize = const Size(1100, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    IptcTemplate? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<IptcTemplate>(
                  context: context,
                  builder: (_) => IptcTemplateDialog(
                    initial: initial,
                    recent: recent,
                    pickLoadPath: pickLoadPath,
                    pickSavePath: pickSavePath,
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
    return result!;
  }

  testWidgets('typing a field auto-activates it and Save includes it', (
    tester,
  ) async {
    final result = await run(tester, const IptcTemplate(), (t) async {
      await goTab(t, 'Location');
      await t.enterText(fieldInput(IptcField.city), 'Munich');
    });

    expect(result.fields, {IptcField.city: 'Munich'});
    expect(result.keywords, isNull); // keywords left untouched
  });

  testWidgets('caption goes in with text, keywords parsed when filled', (
    tester,
  ) async {
    final result = await run(tester, const IptcTemplate(), (t) async {
      // Content is the default tab; caption is there.
      await t.enterText(fieldInput(IptcField.caption), 'On the wire');
      await goTab(t, 'Keywords');
      await t.enterText(find.byType(TextField), 'a, b, a');
    });

    expect(result.fields[IptcField.caption], 'On the wire');
    expect(result.keywords, ['a', 'b']); // de-duped by parseKeywords
  });

  testWidgets('a seeded template round-trips through the form untouched', (
    tester,
  ) async {
    const initial = IptcTemplate(
      fields: {IptcField.credit: 'AP', IptcField.caption: 'Cap'},
      textModes: {IptcField.caption: TextApplyMode.append},
      keywords: ['sport'],
      keywordMode: KeywordApplyMode.append,
    );

    final result = await run(tester, initial, (_) async {});

    expect(result.fields, {IptcField.credit: 'AP', IptcField.caption: 'Cap'});
    expect(result.captionMode, TextApplyMode.append);
    expect(result.keywords, ['sport']);
    expect(result.keywordMode, KeywordApplyMode.append);
  });

  testWidgets('unticking a field drops it from the saved template', (
    tester,
  ) async {
    const initial = IptcTemplate(fields: {IptcField.credit: 'AP'});

    final result = await run(tester, initial, (t) async {
      await goTab(t, 'Rights');
      await t.tap(fieldCheckbox(IptcField.credit)); // untick credit
      await t.pump();
    });

    expect(result.fields.containsKey(IptcField.credit), isFalse);
  });

  testWidgets('adding a table row saves a structured record', (tester) async {
    final result = await run(tester, const IptcTemplate(), (t) async {
      await goTab(t, 'Tables');
      // First "Add row" button is the Locations-shown table.
      final add = find.widgetWithText(TextButton, 'Add row').first;
      await t.ensureVisible(add);
      await t.tap(add);
      await t.pumpAndSettle();
      // The Locations-shown table's first cell (Sublocation).
      await t.enterText(find.byType(TextField).first, 'Marienplatz');
      await t.pump();
    });

    expect(result.locationsShown.single.sublocation, 'Marienplatz');
  });

  testWidgets('a seeded table row round-trips through the editor', (
    tester,
  ) async {
    const initial = IptcTemplate(
      copyrightOwners: [IptcEntity(name: 'Cullimingo Wire')],
    );

    final result = await run(tester, initial, (_) async {});

    expect(result.copyrightOwners.single.name, 'Cullimingo Wire');
  });

  testWidgets('a seeded location row keeps all seven columns', (tester) async {
    const initial = IptcTemplate(
      locationsShown: [
        IptcLocation(
          city: 'Munich',
          country: 'Germany',
          countryCode: 'DE',
          worldRegion: 'Europe',
          locationId: 'geo:muc',
        ),
      ],
    );

    final result = await run(tester, initial, (_) async {});

    final loc = result.locationsShown.single;
    expect(loc.city, 'Munich');
    expect(loc.countryCode, 'DE');
    expect(loc.worldRegion, 'Europe');
    expect(loc.locationId, 'geo:muc');
  });

  testWidgets('seeded licensor and registry rows round-trip', (tester) async {
    const initial = IptcTemplate(
      licensors: [IptcLicensor(name: 'Cullimingo Wire', email: 'l@cw.app')],
      registryEntries: [IptcRegistryEntry(itemId: 'IMG-42')],
    );

    final result = await run(tester, initial, (_) async {});

    expect(result.licensors.single.name, 'Cullimingo Wire');
    expect(result.licensors.single.email, 'l@cw.app');
    expect(result.registryEntries.single.itemId, 'IMG-42');
  });

  testWidgets('Date Created is not offered in the template', (tester) async {
    await run(tester, const IptcTemplate(), (t) async {
      // Content is the default tab; the M editor shows Date Created here, the
      // template deliberately does not (a fixed capture date per batch is
      // nonsense).
      expect(find.byKey(const ValueKey(IptcField.dateCreated)), findsNothing);
      expect(find.text('Date created'), findsNothing);
    });
  });

  testWidgets('picking a recent value fills and activates the field', (
    tester,
  ) async {
    final recent = const RecentFieldValues().record(IptcField.credit, 'AP');

    final result = await run(tester, const IptcTemplate(), (t) async {
      await goTab(t, 'Rights');
      await t.ensureVisible(find.byTooltip('Recent values'));
      await t.tap(find.byTooltip('Recent values'));
      await t.pumpAndSettle();
      await t.tap(find.text('AP').last);
      await t.pumpAndSettle();
    }, recent: recent);

    expect(result.fields[IptcField.credit], 'AP');
  });

  testWidgets('Clear empties the whole pad', (tester) async {
    const initial = IptcTemplate(
      fields: {IptcField.caption: 'Old', IptcField.credit: 'AP'},
      keywords: ['sport'],
      licensors: [IptcLicensor(name: 'Agency')],
    );

    final result = await run(tester, initial, (t) async {
      await t.tap(find.text('Clear'));
      await t.pumpAndSettle();
      // The visible field really emptied (not just the saved template).
      expect(
        t.widget<TextField>(fieldInput(IptcField.caption)).controller!.text,
        isEmpty,
      );
    });

    expect(result.isEmpty, isTrue);
  });

  testWidgets('Load XMP… replaces the pad with the file template', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('cullimingo_tpl_dlg');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/wire.xmp';
    const loaded = IptcTemplate(
      fields: {IptcField.caption: 'From file', IptcField.credit: 'AP'},
      keywords: ['wire'],
      locationsShown: [IptcLocation(city: 'Bremen')],
    );
    File(path).writeAsStringSync(templateToXmpSource(loaded));

    final result = await run(
      tester,
      const IptcTemplate(fields: {IptcField.source: 'Stale'}),
      (t) async {
        await t.tap(find.text('Load XMP…'));
        // The parse runs in a real isolate — let it finish outside fake async.
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await t.pumpAndSettle();
      },
      pickLoadPath: () async => path,
    );

    expect(result.fields, loaded.fields);
    expect(result.keywords, ['wire']);
    expect(result.locationsShown.single.city, 'Bremen');
    // Load replaces (PM semantics): the stale field is gone.
    expect(result.fields.containsKey(IptcField.source), isFalse);
  });

  testWidgets('Save XMP… writes a file PM/Bridge can load back', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('cullimingo_tpl_dlg');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/out.xmp';

    await run(
      tester,
      const IptcTemplate(fields: {IptcField.credit: 'AP'}, keywords: ['a']),
      (t) async {
        await t.tap(find.text('Save XMP…'));
        // The write runs in a real isolate — let it finish outside fake async.
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await t.pumpAndSettle();
      },
      pickSavePath: () async => path,
    );

    final out = templateFromXmpSource(File(path).readAsStringSync());
    expect(out.fields, {IptcField.credit: 'AP'});
    expect(out.keywords, ['a']);
  });
}
