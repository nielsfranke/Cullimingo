import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where delivery-server passwords live: the platform secret store — Keychain
/// on macOS, libsecret (Secret Service) on Linux — never `settings.json`
/// (`BUILD_PLAN.md` §11).
///
/// Interface kept tiny so tests inject an [InMemorySecretStore] and the UI
/// never touches the plugin directly.
abstract interface class SecretStore {
  /// The stored secret for [key], or null when none (or unreadable).
  Future<String?> read(String key);

  /// Stores [value] under [key], replacing any previous value.
  Future<void> write(String key, String value);

  /// Removes the secret under [key] (a missing key is not an error).
  Future<void> delete(String key);
}

/// The secret-store key holding the password of the delivery server with
/// [serverId] (the stable `DeliveryServer.id`, so renames keep the password).
String deliveryPasswordKey(String serverId) => 'delivery.$serverId.password';

/// The secret-store key holding the ContactSheet personal access token
/// (`cs_pat_…`). It used to live in plain `settings.json`; the handoff layer
/// migrates it here on first read (`cs_credentials.dart`).
const String contactSheetTokenKey = 'contactsheet.token';

/// The real store, backed by flutter_secure_storage. Reads swallow platform
/// errors into null (a missing secret just means the user re-enters it);
/// writes and deletes propagate so the UI can tell the user a password was
/// NOT saved.
class SecureSecretStore implements SecretStore {
  /// Creates the store.
  const SecureSecretStore();

  // macOS: the plugin's default — the data-protection keychain — silently
  // rejects every read/write unless the app is signed with a development
  // certificate + Keychain-Sharing entitlement. We ship ad-hoc-signed outside
  // the App Store (§6.1), so use the classic login keychain instead, which
  // works for any signing. Verified live 2026-07-03: with the default, tokens
  // never persisted on macOS.
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Test double: keeps secrets in a map.
class InMemorySecretStore implements SecretStore {
  /// Creates an empty store, optionally pre-seeded with [secrets].
  InMemorySecretStore([Map<String, String>? secrets]) : secrets = {...?secrets};

  /// The live backing map, inspectable by tests.
  final Map<String, String> secrets;

  @override
  Future<String?> read(String key) async => secrets[key];

  @override
  Future<void> write(String key, String value) async => secrets[key] = value;

  @override
  Future<void> delete(String key) async => secrets.remove(key);
}

/// The app-wide secret store; tests override this with an
/// [InMemorySecretStore]. Classic provider — no codegen needed for a constant.
final secretStoreProvider = Provider<SecretStore>(
  (_) => const SecureSecretStore(),
);
