import 'dart:convert';
import 'dart:io';

import 'package:cullimingo/core/secrets/secret_store.dart';
import 'package:cullimingo/core/settings/app_settings.dart';
import 'package:cullimingo/features/handoff/data/cs_credentials.dart';
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

/// A store whose writes always fail, for the migration-retry path.
class _ReadOnlySecretStore extends InMemorySecretStore {
  @override
  Future<void> write(String key, String value) async =>
      throw Exception('keychain unavailable');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late File settingsFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cm_cs_creds');
    settingsFile = File(p.join(tempDir.path, 'settings.json'));
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });
  tearDown(() => tempDir.deleteSync(recursive: true));

  test('a plaintext legacy token migrates to the secret store once', () async {
    settingsFile.writeAsStringSync(
      jsonEncode({
        'csBaseUrl': 'https://cs.example.com',
        'csToken': 'cs_pat_old',
      }),
    );
    final secrets = InMemorySecretStore();

    final creds = await loadCsCredentials(secrets);

    expect(creds.baseUrl, 'https://cs.example.com');
    expect(creds.token, 'cs_pat_old');
    expect(secrets.secrets[contactSheetTokenKey], 'cs_pat_old');
    // The plaintext copy is gone from settings.json.
    expect((await AppSettings.load()).contactSheetToken, isNull);
  });

  test('an existing secret-store token wins over a stale legacy one', () async {
    settingsFile.writeAsStringSync(jsonEncode({'csToken': 'cs_pat_stale'}));
    final secrets = InMemorySecretStore({contactSheetTokenKey: 'cs_pat_new'});

    final creds = await loadCsCredentials(secrets);

    expect(creds.token, 'cs_pat_new');
    expect(secrets.secrets[contactSheetTokenKey], 'cs_pat_new');
    expect((await AppSettings.load()).contactSheetToken, isNull);
  });

  test('a failed migration keeps the legacy token for a retry', () async {
    settingsFile.writeAsStringSync(jsonEncode({'csToken': 'cs_pat_old'}));

    final creds = await loadCsCredentials(_ReadOnlySecretStore());

    // Still usable this session, still in settings.json for next time.
    expect(creds.token, 'cs_pat_old');
    expect((await AppSettings.load()).contactSheetToken, 'cs_pat_old');
  });

  test(
    'save writes the base URL to settings, the token to the store',
    () async {
      final secrets = InMemorySecretStore();

      await saveCsCredentials(
        secrets,
        baseUrl: 'https://cs.example.com',
        token: 'cs_pat_x',
      );

      final settings = await AppSettings.load();
      expect(settings.contactSheetBaseUrl, 'https://cs.example.com');
      expect(settings.contactSheetToken, isNull);
      expect(secrets.secrets[contactSheetTokenKey], 'cs_pat_x');
    },
  );

  test('saving an empty token deletes the stored one', () async {
    final secrets = InMemorySecretStore({contactSheetTokenKey: 'cs_pat_x'});

    await saveCsCredentials(secrets, baseUrl: 'https://x', token: '');

    expect(secrets.secrets.containsKey(contactSheetTokenKey), isFalse);
  });

  test('a secret-store failure on save is swallowed (best effort)', () async {
    await expectLater(
      saveCsCredentials(
        _ReadOnlySecretStore(),
        baseUrl: 'https://x',
        token: 'cs_pat_x',
      ),
      completes,
    );
  });
}
