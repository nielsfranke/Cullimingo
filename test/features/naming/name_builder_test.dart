import 'package:cullimingo/features/naming/domain/name_preset.dart';
import 'package:cullimingo/features/naming/presentation/name_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host({
    required NamePreset initial,
    required ValueChanged<NamePreset> onChanged,
    List<NamePreset> saved = const [],
    ValueChanged<NamePreset>? onSave,
    ValueChanged<String>? onDelete,
  }) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: NameBuilder(
          initial: initial,
          savedPresets: saved,
          onChanged: onChanged,
          onSavePreset: onSave ?? (_) {},
          onDeletePreset: onDelete ?? (_) {},
        ),
      ),
    ),
  );

  const empty = NamePreset(name: '', folderPattern: '', filePattern: '');

  testWidgets('clicking a plain element inserts its token into the filename', (
    tester,
  ) async {
    NamePreset? emitted;
    await tester.pumpWidget(
      host(initial: empty, onChanged: (p) => emitted = p),
    );

    await tester.tap(find.text('Original filename'));
    await tester
        .pump(); // insert focuses the field; don't settle (cursor blink)

    expect(emitted?.filePattern, '{origname}');
  });

  testWidgets('elements insert at the caret, one after another', (
    tester,
  ) async {
    NamePreset? emitted;
    await tester.pumpWidget(
      host(initial: empty, onChanged: (p) => emitted = p),
    );

    await tester.tap(find.text('Original filename'));
    await tester.pump();
    await tester.tap(find.text('Camera'));
    await tester.pump();

    expect(emitted?.filePattern, '{origname}{camera}');
  });

  testWidgets('the counter element inserts a seq token with chosen digits', (
    tester,
  ) async {
    NamePreset? emitted;
    await tester.pumpWidget(
      host(initial: empty, onChanged: (p) => emitted = p),
    );

    await tester.tap(find.text('Counter ▾'));
    await tester.pumpAndSettle(); // menu opens (no field focus yet)
    await tester.tap(find.text('4 digits').last);
    await tester.pump();

    expect(emitted?.filePattern, '{seq:4}');
  });

  testWidgets('the date element inserts a date token in the chosen format', (
    tester,
  ) async {
    NamePreset? emitted;
    await tester.pumpWidget(
      host(initial: empty, onChanged: (p) => emitted = p),
    );

    await tester.tap(find.text('Date / time ▾'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Year (2026)').last);
    await tester.pump();

    expect(emitted?.filePattern, '{date:year}');
  });

  testWidgets('editing a field emits the new pattern', (tester) async {
    NamePreset? emitted;
    await tester.pumpWidget(
      host(
        initial: const NamePreset(
          name: '',
          folderPattern: '',
          filePattern: '{origname}',
        ),
        onChanged: (p) => emitted = p,
      ),
    );

    // The first TextField is the filename field; typing replaces its content.
    await tester.enterText(find.byType(TextField).first, '{origname}_v2');
    await tester.pump();

    expect(emitted?.filePattern, '{origname}_v2');
  });

  testWidgets('selecting a preset loads its scheme and shows the example', (
    tester,
  ) async {
    NamePreset? emitted;
    await tester.pumpWidget(
      host(initial: NamePreset.builtIns.first, onChanged: (p) => emitted = p),
    );

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Timestamped').last);
    await tester.pumpAndSettle();

    expect(emitted?.name, 'Timestamped');
    expect(emitted!.filePattern, contains('{seq:4}'));
    // The example is rendered from the engine with the sample data.
    expect(find.textContaining('2026-07-02_143005'), findsOneWidget);
  });
}
