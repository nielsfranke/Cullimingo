import 'dart:io';

import 'package:cullimingo/core/settings/app_settings.dart';
import 'package:cullimingo/features/handoff/domain/external_editor.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
  group('ExternalEditor.fromJson', () {
    test('parses a well-formed map', () {
      final e = ExternalEditor.fromJson({
        'label': 'Capture One',
        'path': '/Applications/Capture One.app',
      });
      expect(e, isNotNull);
      expect(e!.label, 'Capture One');
      expect(e.path, '/Applications/Capture One.app');
    });

    test('rejects missing, empty or wrong-typed fields', () {
      expect(ExternalEditor.fromJson({'label': 'x'}), isNull);
      expect(ExternalEditor.fromJson({'path': '/x'}), isNull);
      expect(ExternalEditor.fromJson({'label': '', 'path': '/x'}), isNull);
      expect(ExternalEditor.fromJson({'label': 'x', 'path': ''}), isNull);
      expect(ExternalEditor.fromJson({'label': 1, 'path': '/x'}), isNull);
    });

    test('round-trips through toJson', () {
      const e = ExternalEditor(label: 'GIMP', path: '/usr/bin/gimp');
      expect(ExternalEditor.fromJson(e.toJson()), e);
    });
  });

  group('AppSettings send-to editors', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('cm_editors');
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('persists and reloads the editor list, skipping bad rows', () async {
      const editors = [
        ExternalEditor(label: 'GIMP', path: '/usr/bin/gimp'),
        ExternalEditor(label: 'Darktable', path: '/usr/bin/darktable'),
      ];
      await (await AppSettings.load()).setSendToEditors([
        for (final e in editors) e.toJson(),
        {'label': 'broken'}, // missing path → dropped on parse
      ]);

      final raw = (await AppSettings.load()).sendToEditors;
      final parsed = [for (final r in raw) ExternalEditor.fromJson(r)];

      expect(parsed.whereType<ExternalEditor>().toList(), editors);
      expect(parsed.contains(null), isTrue); // the broken row survives as null
    });

    test('defaults to an empty list when never set', () async {
      expect((await AppSettings.load()).sendToEditors, isEmpty);
    });
  });
}
