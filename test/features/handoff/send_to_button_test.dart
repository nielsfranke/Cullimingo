import 'package:cullimingo/features/handoff/domain/external_editor.dart';
import 'package:cullimingo/features/handoff/presentation/send_to_button.dart';
import 'package:cullimingo/features/handoff/presentation/send_to_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _photos = ExternalEditor(
  label: 'Photos',
  path: '/System/Applications/Photos.app',
);
const _captureOne = ExternalEditor(
  label: 'Capture One',
  path: '/Applications/Capture One.app',
);

void main() {
  Future<List<ExternalEditor>> pumpButton(
    WidgetTester tester,
    List<ExternalEditor> editors,
  ) async {
    final sent = <ExternalEditor>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sendToEditorsProvider.overrideWith((ref) async => editors),
          editorIconProvider.overrideWith((ref, path) async => null),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SendToButton(
                onSendTo: sent.add,
                trailing: const Text('divider'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return sent;
  }

  testWidgets('hidden, with its divider, while no editor is configured', (
    tester,
  ) async {
    await pumpButton(tester, const []);
    expect(find.textContaining('Send to'), findsNothing);
    expect(find.text('divider'), findsNothing);
  });

  testWidgets('one editor: a single button that sends to it, no menu arrow', (
    tester,
  ) async {
    final sent = await pumpButton(tester, const [_photos]);
    expect(find.text('Send to Photos'), findsOneWidget);
    expect(find.text('divider'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_down), findsNothing);

    await tester.tap(find.text('Send to Photos'));
    expect(sent, [_photos]);
  });

  testWidgets('several editors: the arrow menu lists them all and sends to '
      'the chosen one', (tester) async {
    final sent = await pumpButton(tester, const [_photos, _captureOne]);
    expect(find.text('Send to Photos'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_drop_down));
    await tester.pumpAndSettle();
    expect(find.text('Send to Capture One'), findsOneWidget);

    await tester.tap(find.text('Send to Capture One'));
    await tester.pumpAndSettle();
    expect(sent, [_captureOne]);
  });
}
