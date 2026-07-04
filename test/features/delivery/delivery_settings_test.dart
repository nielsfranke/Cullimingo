import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cullimingo/core/secrets/secret_store.dart';
import 'package:cullimingo/core/settings/app_settings.dart';
import 'package:cullimingo/features/delivery/domain/delivery_server.dart';
import 'package:cullimingo/features/settings/presentation/settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// Test-only transitive deps (via path_provider) for mocking the platform.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// Test-only transitive dep (via path_provider) for the mock mixin.
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.supportDir);
  final String supportDir;
  @override
  Future<String?> getApplicationSupportPath() async => supportDir;
}

void main() {
  late Directory tempDir;
  late InMemorySecretStore secrets;

  const seed = DeliveryServer(
    id: 'seed-1',
    name: 'AP wire',
    protocol: DeliveryProtocol.ftps,
    host: 'ftp.example.com',
    port: 21,
    username: 'niels',
    remoteDir: 'incoming',
  );

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cm_delivery_settings');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    // These tests tap Apply, which saves settings inside the test's FakeAsync
    // zone — detach the queue so a previous test's zone can't wedge it.
    AppSettings.resetWriteQueueForTests();
    secrets = InMemorySecretStore();
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  File settingsFile() => File(p.join(tempDir.path, 'settings.json'));

  void seedSettings() => settingsFile().writeAsStringSync(
    jsonEncode({
      'deliveryServers': [seed.toJson()],
    }),
  );

  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [secretStoreProvider.overrideWithValue(secrets)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showSettingsDialog(context, onClearCache: () async {}),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Delivery servers now live under the dialog's "Delivery" nav-rail tab.
    await tester.tap(find.text('Delivery'));
    await tester.pumpAndSettle();
  }

  /// Drives the tester until Apply's background saves have fully flushed
  /// (same pump/runAsync alternation as settings_dialog_test.dart), then
  /// returns the settings file's content.
  Future<Map<String, dynamic>> drainApplyPersist(WidgetTester tester) async {
    const required = {'hotCodes', 'showTooltips'};
    for (var i = 0; i < 400; i++) {
      var queueIdle = false;
      unawaited(AppSettings.pendingWrites.whenComplete(() => queueIdle = true));
      await tester.pump();
      if (queueIdle) {
        try {
          final map =
              jsonDecode(settingsFile().readAsStringSync())
                  as Map<String, dynamic>;
          if (required.every(map.containsKey)) return map;
        } on Object {
          // Not written yet.
        }
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await tester.pump();
    }
    throw StateError('settings persist never completed');
  }

  Finder fieldWithHint(String hint) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint,
  );

  List<DeliveryServer> persistedServers(Map<String, dynamic> settings) => [
    for (final raw in (settings['deliveryServers'] as List? ?? []))
      ?DeliveryServer.fromJson((raw as Map).cast<String, dynamic>()),
  ];

  testWidgets('adds a server; Apply persists it + the password', (
    tester,
  ) async {
    await pumpDialog(tester);
    await tester.tap(find.text('Add server…'));
    await tester.pumpAndSettle();

    await tester.enterText(fieldWithHint('Name (e.g. AP wire)'), 'Reuters');
    await tester.enterText(fieldWithHint('Host'), 'wire.example.com');
    await tester.enterText(
      fieldWithHint('Username (empty = anonymous)'),
      'niels',
    );
    await tester.enterText(fieldWithHint('Password'), 'hunter2');
    await tester.enterText(
      fieldWithHint('Remote folder (e.g. incoming/photos)'),
      'in/tray',
    );
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Reuters'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    final settings = await drainApplyPersist(tester);

    final server = persistedServers(settings).single;
    expect(server.name, 'Reuters');
    expect(server.host, 'wire.example.com');
    expect(server.protocol, DeliveryProtocol.ftps);
    expect(server.port, 21);
    expect(server.remoteDir, 'in/tray');
    expect(secrets.secrets[deliveryPasswordKey(server.id)], 'hunter2');
  });

  testWidgets('edits a server; password lands under the same id', (
    tester,
  ) async {
    seedSettings();
    secrets.secrets[deliveryPasswordKey(seed.id)] = 'old-pass';
    await pumpDialog(tester);

    await tester.tap(find.byTooltip('Edit server'));
    await tester.pumpAndSettle();
    // The stored password is pre-filled for editing.
    expect(
      tester.widget<TextField>(fieldWithHint('Password')).controller?.text,
      'old-pass',
    );
    await tester.enterText(fieldWithHint('Name (e.g. AP wire)'), 'AP Berlin');
    await tester.enterText(fieldWithHint('Password'), 'new-pass');
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Apply'));
    final settings = await drainApplyPersist(tester);

    final server = persistedServers(settings).single;
    expect(server.id, seed.id);
    expect(server.name, 'AP Berlin');
    expect(secrets.secrets[deliveryPasswordKey(seed.id)], 'new-pass');
  });

  testWidgets('removes a server; Apply deletes its password too', (
    tester,
  ) async {
    seedSettings();
    secrets.secrets[deliveryPasswordKey(seed.id)] = 'old-pass';
    await pumpDialog(tester);

    await tester.tap(find.byTooltip('Remove server'));
    await tester.pump();
    expect(find.textContaining('AP wire'), findsNothing);

    await tester.tap(find.text('Apply'));
    final settings = await drainApplyPersist(tester);

    expect(persistedServers(settings), isEmpty);
    expect(secrets.secrets, isEmpty);
  });

  testWidgets('Cancel discards everything, including typed passwords', (
    tester,
  ) async {
    await pumpDialog(tester);
    await tester.tap(find.text('Add server…'));
    await tester.pumpAndSettle();
    await tester.enterText(fieldWithHint('Name (e.g. AP wire)'), 'Reuters');
    await tester.enterText(fieldWithHint('Host'), 'wire.example.com');
    await tester.enterText(fieldWithHint('Password'), 'hunter2');
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(settingsFile().existsSync(), isFalse);
    expect(secrets.secrets, isEmpty);
  });

  testWidgets('OK stays disabled until name, host and port are valid', (
    tester,
  ) async {
    await pumpDialog(tester);
    await tester.tap(find.text('Add server…'));
    await tester.pumpAndSettle();

    FilledButton okButton() => tester.widget<FilledButton>(
      find.ancestor(of: find.text('OK'), matching: find.byType(FilledButton)),
    );
    expect(okButton().onPressed, isNull);

    await tester.enterText(fieldWithHint('Name (e.g. AP wire)'), 'X');
    await tester.enterText(fieldWithHint('Host'), 'h');
    await tester.enterText(fieldWithHint('Port'), 'nope');
    await tester.pump();
    expect(okButton().onPressed, isNull);

    await tester.enterText(fieldWithHint('Port'), '2121');
    await tester.pump();
    expect(okButton().onPressed, isNotNull);
  });
}
