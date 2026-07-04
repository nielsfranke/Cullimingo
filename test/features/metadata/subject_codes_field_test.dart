import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/features/metadata/domain/media_topics.dart';
import 'package:cullimingo/features/metadata/presentation/iptc_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const topics = MediaTopics([
    MediaTopic(
      qcode: 'medtop:20001065',
      label: 'soccer',
      parent: 'competition discipline',
    ),
    MediaTopic(qcode: 'medtop:15000000', label: 'sport'),
  ]);

  Future<void> pumpEditor(
    WidgetTester tester, {
    IptcCore initial = const IptcCore(),
    MediaTopics vocab = topics,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IptcEditorDialog(targets: [initial], count: 1, topics: vocab),
        ),
      ),
    );
  }

  Finder subjectField() => find.byWidgetPredicate(
    (w) =>
        w is TextField &&
        (w.decoration?.hintText?.contains('IPTC vocabulary') ?? false),
  );

  testWidgets('typing shows vocabulary suggestions; picking inserts the code', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.enterText(subjectField(), 'soc');
    await tester.pump();
    expect(find.textContaining('soccer'), findsWidgets);
    expect(find.text('medtop:20001065'), findsOneWidget);

    await tester.ensureVisible(find.text('medtop:20001065'));
    await tester.tap(find.text('medtop:20001065'));
    await tester.pump();
    expect(
      tester.widget<TextField>(subjectField()).controller?.text,
      'medtop:20001065',
    );
    // The friendly label line replaces the suggestion list.
    expect(find.text('soccer'), findsOneWidget);
  });

  testWidgets('a second fragment keeps earlier codes and dedupes them', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      initial: const IptcCore(subjectCodes: 'medtop:20001065'),
    );

    // Existing value shows its friendly label.
    expect(find.text('soccer'), findsOneWidget);

    await tester.enterText(subjectField(), 'medtop:20001065, s');
    await tester.pump();
    // 'soccer' is already picked → only 'sport' is suggested.
    expect(find.text('medtop:15000000'), findsOneWidget);
    expect(find.text('medtop:20001065'), findsNothing);

    await tester.ensureVisible(find.text('medtop:15000000'));
    await tester.tap(find.text('medtop:15000000'));
    await tester.pump();
    expect(
      tester.widget<TextField>(subjectField()).controller?.text,
      'medtop:20001065, medtop:15000000',
    );
    expect(find.text('soccer · sport'), findsOneWidget);
  });

  testWidgets('an empty vocabulary degrades to the plain field', (
    tester,
  ) async {
    await pumpEditor(tester, vocab: const MediaTopics([]));
    expect(subjectField(), findsNothing);
    expect(find.text('Media topics'), findsOneWidget);
  });
}
