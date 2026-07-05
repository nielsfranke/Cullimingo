import 'dart:convert';
import 'dart:io';

import 'package:cullimingo/features/handoff/presentation/send_to_providers.dart';
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

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cm_cs_gate');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });
  tearDown(() => tempDir.deleteSync(recursive: true));

  void writeSettings(Map<String, dynamic> data) => File(
    p.join(tempDir.path, 'settings.json'),
  ).writeAsStringSync(jsonEncode(data));

  test('is false when no ContactSheet base URL is set', () async {
    writeSettings({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      await container.read(contactSheetConfiguredProvider.future),
      isFalse,
    );
  });

  test('is true once a base URL is configured', () async {
    writeSettings({'csBaseUrl': 'https://cs.example.com'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(await container.read(contactSheetConfiguredProvider.future), isTrue);
  });

  test('an empty base URL still reads as not configured', () async {
    writeSettings({'csBaseUrl': ''});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      await container.read(contactSheetConfiguredProvider.future),
      isFalse,
    );
  });
}
