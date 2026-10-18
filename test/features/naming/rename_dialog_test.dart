import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cullimingo/core/settings/app_settings.dart';
import 'package:cullimingo/features/naming/data/rename_service.dart';
import 'package:cullimingo/features/naming/presentation/rename_dialog.dart';
import 'package:flutter/material.dart';
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

const _mine = {
  'name': 'Mine',
  'folder': '',
  'file': '{shoot}_{seq:3}',
  'counterStart': 1,
};

void main() {
  late Directory tempDir;
  late File settingsFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cm_rename_dialog');
    settingsFile = File(p.join(tempDir.path, 'settings.json'));
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    AppSettings.resetWriteQueueForTests();
  });
  tearDown(() => tempDir.deleteSync(recursive: true));

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showRenameDialog(
                context,
                sources: [
                  RenameSource(
                    id: 1,
                    path: '/s/a.JPG',
                    capturedAt: DateTime(2026, 6, 1, 10),
                  ),
                ],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // Let the dialog's async settings load hit the disk.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('reopens on the last-used saved preset, not Custom (#20)', (
    tester,
  ) async {
    settingsFile.writeAsStringSync(
      jsonEncode({
        'namePresets': [_mine],
        'lastRenameNaming': _mine,
      }),
    );
    await open(tester);
    expect(find.text('Mine'), findsOneWidget);
    expect(find.text('Custom'), findsNothing);
  });

  testWidgets('Rename remembers the naming scheme for next time', (
    tester,
  ) async {
    settingsFile.writeAsStringSync(
      jsonEncode({
        'namePresets': [_mine],
      }),
    );
    await open(tester);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mine').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename 1'));
    await tester.pumpAndSettle();

    for (var i = 0; i < 400; i++) {
      var queueIdle = false;
      unawaited(AppSettings.pendingWrites.whenComplete(() => queueIdle = true));
      await tester.pump();
      if (queueIdle) {
        try {
          final map =
              jsonDecode(settingsFile.readAsStringSync())
                  as Map<String, dynamic>;
          if (map.containsKey('lastRenameNaming')) {
            expect(map['lastRenameNaming'], _mine);
            return;
          }
        } on Object {
          // Mid-write — keep polling.
        }
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
    }
    fail('settings save never completed');
  });
}
