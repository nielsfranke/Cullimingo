import 'package:cullimingo/features/delivery/domain/delivery_server.dart';
import 'package:cullimingo/features/delivery/presentation/delivery_server_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<DeliveryServerEdit? Function()> pumpDialog(
    WidgetTester tester, {
    DeliveryServer? initial,
  }) async {
    await tester.binding.setSurfaceSize(const Size(700, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    DeliveryServerEdit? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDeliveryServerDialog(
                  context,
                  initial: initial,
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
    return () => result;
  }

  Finder fieldWithHint(String hint) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint,
  );

  testWidgets('FTPS shows the self-signed toggle and keeps it in the result', (
    tester,
  ) async {
    final result = await pumpDialog(tester);

    // Default protocol is FTPS → toggle visible, key-file field not.
    expect(find.text('Accept self-signed certificate'), findsOneWidget);
    expect(
      fieldWithHint('Private key file (empty = password auth)'),
      findsNothing,
    );

    await tester.enterText(fieldWithHint('Name (e.g. AP wire)'), 'Wire');
    await tester.enterText(fieldWithHint('Host'), 'h');
    await tester.tap(find.text('Accept self-signed certificate'));
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(result()!.server.allowSelfSigned, isTrue);
    expect(result()!.server.keyFilePath, '');
  });

  testWidgets('SFTP shows the key-file field; password relabels as '
      'passphrase once a key is set', (tester) async {
    final result = await pumpDialog(tester);

    await tester.tap(find.text('FTPS (explicit TLS)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SFTP').last);
    await tester.pumpAndSettle();

    expect(find.text('Accept self-signed certificate'), findsNothing);
    final keyField = fieldWithHint('Private key file (empty = password auth)');
    expect(keyField, findsOneWidget);
    expect(fieldWithHint('Password'), findsOneWidget);

    await tester.enterText(keyField, '/home/n/.ssh/id_ed25519');
    await tester.pump();
    expect(
      fieldWithHint('Key passphrase (empty = unencrypted key)'),
      findsOneWidget,
    );

    // Port followed the protocol default.
    expect(
      tester.widget<TextField>(fieldWithHint('Port')).controller?.text,
      '22',
    );

    await tester.enterText(fieldWithHint('Name (e.g. AP wire)'), 'Wire');
    await tester.enterText(fieldWithHint('Host'), 'h');
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(result()!.server.protocol, DeliveryProtocol.sftp);
    expect(result()!.server.keyFilePath, '/home/n/.ssh/id_ed25519');
    expect(result()!.server.port, 22);
  });
}
