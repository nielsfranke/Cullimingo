import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cullimingo/core/secrets/secret_store.dart';
import 'package:cullimingo/core/settings/app_settings.dart';
import 'package:cullimingo/features/export/domain/export_plan.dart';
import 'package:cullimingo/features/handoff/presentation/contactsheet_dialog.dart';
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
  _FakePathProvider(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

ExportSource _src(String path) => ExportSource(
  path: path,
  capturedAt: DateTime(2026, 6, 1, 10),
  originalName: path.split('/').last,
);

void main() {
  late Directory tempDir;
  late File settingsFile;
  late InMemorySecretStore secrets;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cm_cs_dialog');
    settingsFile = File(p.join(tempDir.path, 'settings.json'));
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    secrets = InMemorySecretStore();
    // These tests trigger settings saves inside the test's FakeAsync zone —
    // detach the queue so a previous test's zone can't wedge it.
    AppSettings.resetWriteQueueForTests();
  });
  tearDown(() => tempDir.deleteSync(recursive: true));

  Future<ContactSheetAction? Function()> pumpAndOpen(
    WidgetTester tester, {
    List<ExportSource>? sources,
    bool pullMode = false,
  }) async {
    ContactSheetAction? result;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [secretStoreProvider.overrideWithValue(secrets)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async => result = await showContactSheetDialog(
                  context,
                  sources: sources ?? [_src('/s/a.JPG')],
                  initialPullMode: pullMode,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  /// Drives the tester until the dialog's background settings save has
  /// flushed [requiredKey] to disk, returning the settings file's content.
  Future<Map<String, dynamic>> drainSave(
    WidgetTester tester,
    String requiredKey,
  ) async {
    for (var i = 0; i < 400; i++) {
      var queueIdle = false;
      unawaited(AppSettings.pendingWrites.whenComplete(() => queueIdle = true));
      await tester.pump();
      if (queueIdle && settingsFile.existsSync()) {
        try {
          final map =
              jsonDecode(settingsFile.readAsStringSync())
                  as Map<String, dynamic>;
          if (map.containsKey(requiredKey)) return map;
        } on Object {
          // Mid-write — keep polling.
        }
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await tester.pump();
    }
    throw StateError('settings save never completed');
  }

  testWidgets('Send returns a request for a new gallery with server + preset', (
    tester,
  ) async {
    final sources = [_src('/s/a.ARW'), _src('/s/b.JPG')];
    final result = await pumpAndOpen(tester, sources: sources);

    expect(find.text('ContactSheet'), findsOneWidget);

    // baseUrl, token, new-gallery-name fields (in form order).
    await tester.enterText(
      find.byType(TextField).at(0),
      'https://cs.example.com',
    );
    await tester.enterText(find.byType(TextField).at(1), 'cs_pat_x');
    await tester.enterText(find.byType(TextField).at(2), 'My Shoot');
    await tester.pump();

    await tester.tap(find.text('Send 2'));
    await tester.pumpAndSettle();

    expect(result(), isA<ContactSheetSend>());
    final request = (result()! as ContactSheetSend).request;
    expect(request.baseUrl, 'https://cs.example.com');
    expect(request.token, 'cs_pat_x');
    expect(request.galleryName, 'My Shoot');
    expect(request.galleryId, isNull);
    expect(request.sources.length, 2);
    expect(request.preset.longEdge, 2048);

    // The connection is remembered: token in the secret store (never
    // settings.json), base URL + last-used preset in settings.
    final saved = await drainSave(tester, 'lastContactSheet');
    expect(secrets.secrets[contactSheetTokenKey], 'cs_pat_x');
    expect(saved['csBaseUrl'], 'https://cs.example.com');
    expect(saved.containsKey('csToken'), isFalse);
    expect(saved['lastContactSheet'], {
      'size': 2048,
      'quality': 85,
      'importCollections': true,
    });
  });

  testWidgets('initialPullMode opens straight into pull mode', (tester) async {
    await pumpAndOpen(tester, pullMode: true);

    // The primary action reads "Pull marks" (not "Send 1") — pull is active
    // from the right-click "Pull marks…" entry, no toggle needed.
    expect(find.widgetWithText(FilledButton, 'Pull marks'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Send 1'), findsNothing);
  });

  testWidgets('Send is disabled until server + gallery are provided', (
    tester,
  ) async {
    await pumpAndOpen(tester);

    final send = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Send 1'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(send.onPressed, isNull);
  });

  testWidgets('a configured server collapses to a summary row', (
    tester,
  ) async {
    settingsFile.writeAsStringSync(
      jsonEncode({'csBaseUrl': 'https://cs.example.com'}),
    );
    secrets.secrets[contactSheetTokenKey] = 'cs_pat_x';

    await pumpAndOpen(tester);

    // Collapsed: host summary + Change, no URL/token fields — only the
    // new-gallery-name field remains.
    expect(find.text('cs.example.com'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    // Change expands the fields again, prefilled from the stores.
    await tester.tap(find.text('Change'));
    await tester.pump();
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    expect(
      tester.widget<TextField>(fields.at(0)).controller!.text,
      'https://cs.example.com',
    );
    expect(tester.widget<TextField>(fields.at(1)).controller!.text, 'cs_pat_x');
  });

  testWidgets('the last-used size and quality seed the next send', (
    tester,
  ) async {
    settingsFile.writeAsStringSync(
      jsonEncode({
        'lastContactSheet': {'size': 3072, 'quality': 70},
      }),
    );

    await pumpAndOpen(tester);

    expect(find.text('3072 px'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 70);
  });
}
