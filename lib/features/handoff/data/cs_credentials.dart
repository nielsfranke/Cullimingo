import 'package:cullimingo/core/secrets/secret_store.dart';
import 'package:cullimingo/core/settings/app_settings.dart';

/// The stored ContactSheet connection: base URL from `settings.json`, token
/// from the platform secret store. Either may be empty when not configured.
typedef CsCredentials = ({String baseUrl, String token});

/// Loads the ContactSheet credentials, migrating a plaintext token out of a
/// pre-secret-store `settings.json` on the way: the legacy value is written to
/// [secrets] (unless a secret-store token already exists — that one is newer)
/// and then blanked in the settings file. If the secret write fails the legacy
/// token is still returned and left in place, so the migration retries next
/// time instead of losing the token.
Future<CsCredentials> loadCsCredentials(SecretStore secrets) async {
  final settings = await AppSettings.load();
  final baseUrl = settings.contactSheetBaseUrl ?? '';
  var token = await secrets.read(contactSheetTokenKey) ?? '';
  final legacy = settings.contactSheetToken ?? '';
  if (legacy.isNotEmpty) {
    if (token.isEmpty) {
      try {
        await secrets.write(contactSheetTokenKey, legacy);
        token = legacy;
      } on Object {
        return (baseUrl: baseUrl, token: legacy);
      }
    }
    await settings.clearLegacyContactSheetToken();
  }
  return (baseUrl: baseUrl, token: token);
}

/// Persists the ContactSheet connection: base URL to settings, token to the
/// secret store (an empty token deletes the stored one). Token storage is best
/// effort — on a secret-store failure the user re-enters it next time, which
/// beats failing the send that is about to run.
Future<void> saveCsCredentials(
  SecretStore secrets, {
  required String baseUrl,
  required String token,
}) async {
  final settings = await AppSettings.load();
  await settings.setContactSheetBaseUrl(baseUrl);
  try {
    if (token.isEmpty) {
      await secrets.delete(contactSheetTokenKey);
    } else {
      await secrets.write(contactSheetTokenKey, token);
    }
  } on Object {
    // Best effort (matches AppSettings' stance): a lost token only means
    // re-entering it, and the in-flight request already carries this one.
  }
}
