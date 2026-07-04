import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/features/metadata/domain/iptc_structured.dart';
import 'package:cullimingo/features/metadata/domain/reverse_geocoder.dart';
import 'package:cullimingo/features/metadata/presentation/iptc_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every [SerialCaptioning.onApply] call (index + changed fields).
class _Applied {
  final indexes = <int>[];
  final changes = <Map<IptcField, String>>[];
}

void main() {
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

  /// A serial walk whose applies are recorded in [applied]; [onApply] returns
  /// the payload with the changes merged, like the real write-through.
  SerialCaptioning serial(List<IptcCore> iptcs, _Applied applied) =>
      SerialCaptioning(
        iptcs: iptcs,
        filenames: [for (var i = 1; i <= iptcs.length; i++) 'DSC_000$i.jpg'],
        initialIndex: 0,
        onApply: (index, changes, applyTables) async {
          applied.indexes.add(index);
          applied.changes.add(changes);
          return applyTables(iptcs[index].withOverrides(changes));
        },
      );

  Future<void> pumpSerial(WidgetTester tester, SerialCaptioning s) async {
    await tester.binding.setSurfaceSize(const Size(900, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => IptcEditorDialog(
                  targets: [s.iptcs[s.initialIndex]],
                  count: 1,
                  serial: s,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder caption() => find.byType(TextField).at(captionIndex);

  Future<void> cmdEnter(WidgetTester tester, {bool shift = false}) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('header shows filename + position; prev is disabled at the '
      'start', (tester) async {
    final applied = _Applied();
    await pumpSerial(
      tester,
      serial([const IptcCore(), const IptcCore(), const IptcCore()], applied),
    );

    expect(find.text('DSC_0001.jpg'), findsOneWidget);
    expect(find.text('1 of 3'), findsOneWidget);
    final prev = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_left),
    );
    expect(prev.onPressed, isNull);
  });

  testWidgets('next auto-saves the edit, loads the next photo, and back '
      'shows what was written', (tester) async {
    final applied = _Applied();
    await pumpSerial(
      tester,
      serial(
        [const IptcCore(), const IptcCore(caption: 'Two'), const IptcCore()],
        applied,
      ),
    );

    await tester.enterText(caption(), 'One captioned');
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(applied.indexes, [0]);
    expect(applied.changes.single, {IptcField.caption: 'One captioned'});
    expect(find.text('2 of 3'), findsOneWidget);
    expect(tester.widget<TextField>(caption()).controller!.text, 'Two');

    // Back: photo 1 shows the value that was written through.
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(applied.indexes, [0]); // photo 2 untouched — no second apply
    expect(
      tester.widget<TextField>(caption()).controller!.text,
      'One captioned',
    );
  });

  testWidgets('Date Created shows the capture time as its prefill', (
    tester,
  ) async {
    final applied = _Applied();
    final s = SerialCaptioning(
      iptcs: const [IptcCore()],
      filenames: const ['DSC_0001.jpg'],
      initialIndex: 0,
      onApply: (index, changes, applyTables) async {
        applied.indexes.add(index);
        return const IptcCore();
      },
      captureTimes: [DateTime(2026, 6, 25, 10, 1)],
    );
    await pumpSerial(tester, s);

    // Content is the default tab, where Date Created lives.
    expect(find.text('2026-06-25 10:01'), findsOneWidget);
    expect(find.text('From capture time'), findsOneWidget);
  });

  testWidgets('the Tables section edits a photo’s structured tables', (
    tester,
  ) async {
    IptcCore? saved;
    final s = SerialCaptioning(
      iptcs: const [
        IptcCore(imageCreators: [IptcEntity(name: 'Jane Doe')]),
      ],
      filenames: const ['DSC_0001.jpg'],
      initialIndex: 0,
      onApply: (index, changes, applyTables) async {
        saved = applyTables(const IptcCore().withOverrides(changes));
        return saved!;
      },
    );
    await pumpSerial(tester, s);

    await tester.tap(find.text('Tables'));
    await tester.pumpAndSettle();

    // The seeded image-creator row shows in the first table cell.
    final nameCell = find.byType(TextField).first;
    expect(tester.widget<TextField>(nameCell).controller!.text, 'Jane Doe');

    await tester.enterText(nameCell, 'Jane Roe');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved?.imageCreators.single.name, 'Jane Roe');
  });

  testWidgets('navigating without edits does not apply anything', (
    tester,
  ) async {
    final applied = _Applied();
    await pumpSerial(
      tester,
      serial([const IptcCore(caption: 'A'), const IptcCore()], applied),
    );

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(applied.indexes, isEmpty);
    expect(find.text('2 of 2'), findsOneWidget);
  });

  testWidgets('⌘Enter walks forward, ⌘⇧Enter walks back', (tester) async {
    final applied = _Applied();
    await pumpSerial(
      tester,
      serial([const IptcCore(), const IptcCore(), const IptcCore()], applied),
    );

    await tester.enterText(caption(), 'First');
    await cmdEnter(tester);
    expect(find.text('2 of 3'), findsOneWidget);
    expect(applied.indexes, [0]);

    await cmdEnter(tester, shift: true);
    expect(find.text('1 of 3'), findsOneWidget);
  });

  testWidgets('⌘PgDn/⌘PgUp page-flip through the walk', (tester) async {
    Future<void> cmdPage(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
    }

    final applied = _Applied();
    await pumpSerial(
      tester,
      serial([const IptcCore(), const IptcCore()], applied),
    );

    await tester.enterText(caption(), 'First');
    await cmdPage(tester, LogicalKeyboardKey.pageDown);
    expect(find.text('2 of 2'), findsOneWidget);
    expect(applied.indexes, [0]); // navigation auto-saved the edit

    // At the end the flip stops — no close (unlike ⌘Enter).
    await cmdPage(tester, LogicalKeyboardKey.pageDown);
    expect(find.text('2 of 2'), findsOneWidget);

    await cmdPage(tester, LogicalKeyboardKey.pageUp);
    expect(find.text('1 of 2'), findsOneWidget);
  });

  testWidgets('⌘Enter on the last photo saves and closes', (tester) async {
    final applied = _Applied();
    await pumpSerial(
      tester,
      serial([const IptcCore(), const IptcCore()], applied),
    );

    await cmdEnter(tester); // 1 → 2, nothing to save
    expect(find.text('2 of 2'), findsOneWidget);

    await tester.enterText(caption(), 'Last one');
    await cmdEnter(tester); // at the end: apply + close
    expect(applied.indexes, [1]);
    expect(applied.changes.single, {IptcField.caption: 'Last one'});
    expect(find.text('Metadata'), findsNothing);
  });

  testWidgets('Save applies the current edits and closes', (tester) async {
    final applied = _Applied();
    await pumpSerial(
      tester,
      serial([const IptcCore(), const IptcCore()], applied),
    );

    await tester.enterText(caption(), 'Done');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(applied.indexes, [0]);
    expect(applied.changes.single, {IptcField.caption: 'Done'});
    expect(find.text('Metadata'), findsNothing);
  });

  testWidgets('Cancel closes without applying the current edits', (
    tester,
  ) async {
    final applied = _Applied();
    await pumpSerial(
      tester,
      serial([const IptcCore(), const IptcCore()], applied),
    );

    await tester.enterText(caption(), 'Discard me');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(applied.indexes, isEmpty);
    expect(find.text('Metadata'), findsNothing);
  });

  group('From GPS', () {
    SerialCaptioning gpsSerial(
      _Applied applied, {
      required List<bool> hasGps,
      required List<int> geocoded,
    }) => SerialCaptioning(
      iptcs: const [IptcCore(), IptcCore()],
      filenames: const ['DSC_0001.jpg', 'DSC_0002.jpg'],
      initialIndex: 0,
      onApply: (index, changes, applyTables) async {
        applied.indexes.add(index);
        applied.changes.add(changes);
        return applyTables(const IptcCore().withOverrides(changes));
      },
      hasGps: hasGps,
      onGeocode: (index) async {
        geocoded.add(index);
        return const GeoPlace(
          city: 'Lillehammer',
          state: 'Innlandet',
          country: 'Norway',
          countryCode: 'NO',
        );
      },
    );

    testWidgets('fills the location fields; save writes them through', (
      tester,
    ) async {
      final applied = _Applied();
      final geocoded = <int>[];
      await pumpSerial(
        tester,
        gpsSerial(applied, hasGps: [true, true], geocoded: geocoded),
      );

      await selectSection(tester, 'Location');
      await tester.tap(find.text('From GPS'));
      await tester.pumpAndSettle();
      expect(geocoded, [0]);

      expect(
        tester.widget<TextField>(fieldOf(IptcField.city)).controller!.text,
        'Lillehammer',
      );
      expect(
        tester
            .widget<TextField>(fieldOf(IptcField.countryCode))
            .controller!
            .text,
        'NO',
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(applied.changes.single, {
        IptcField.city: 'Lillehammer',
        IptcField.state: 'Innlandet',
        IptcField.country: 'Norway',
        IptcField.countryCode: 'NO',
      });
    });

    testWidgets('button is disabled for a photo without GPS', (tester) async {
      final applied = _Applied();
      await pumpSerial(
        tester,
        gpsSerial(applied, hasGps: [false, true], geocoded: []),
      );

      await selectSection(tester, 'Location');
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'From GPS'),
      );
      expect(button.onPressed, isNull);
    });
  });
}
