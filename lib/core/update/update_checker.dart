import 'dart:async';
import 'dart:convert';

import 'package:cullimingo/core/logging/app_logger.dart';
import 'package:cullimingo/core/settings/app_settings.dart';
import 'package:http/http.dart' as http;

/// A newer release found on GitHub than the running build.
class UpdateInfo {
  /// Creates an update descriptor.
  const UpdateInfo({required this.version, required this.releaseUrl});

  /// The newer version's marketing string (e.g. `1.2.0`), leading `v` stripped.
  final String version;

  /// The GitHub release page to open in the browser ("Download").
  final Uri releaseUrl;

  @override
  String toString() => 'UpdateInfo($version, $releaseUrl)';
}

/// The GitHub Releases API for the public mirror. The main repo is mirrored
/// from Forgejo to GitHub on release; `/releases/latest` returns the most
/// recent **non-prerelease, non-draft** release, which is exactly what we want.
final Uri kReleasesApiEndpoint = Uri.parse(
  'https://api.github.com/repos/nielsfranke/Cullimingo/releases/latest',
);

/// How long to wait between startup update checks — once a day is plenty and
/// keeps us far under GitHub's unauthenticated rate limit.
const Duration kUpdateCheckInterval = Duration(hours: 24);

/// Whether an update check is due given the [last] check time (null = never)
/// and [now]. Pure so it's trivially testable.
bool isUpdateCheckDue(DateTime? last, DateTime now) =>
    last == null || now.difference(last) >= kUpdateCheckInterval;

/// Whether [candidate] is a strictly newer version than [current]. Both are
/// dotted numeric versions (`1.2.3`), an optional leading `v` tolerated; any
/// pre-release/build suffix after the numeric core is ignored. Missing
/// components count as 0, so `1.2` == `1.2.0`. Unparseable input returns false
/// (we never nag on garbage).
bool isNewerVersion(String candidate, String current) {
  final a = _components(candidate);
  final b = _components(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

/// Parses the leading `major.minor.patch` of [version] into three ints, or null
/// if there's no numeric version at all. Strips a leading `v` and stops at the
/// first non-numeric/non-dot run (so `1.2.0-beta.1` → `[1, 2, 0]`).
List<int>? _components(String version) {
  final trimmed = version.trim();
  final core = RegExp(
    r'^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?',
  ).firstMatch(trimmed);
  if (core == null) return null;
  return [
    int.parse(core.group(1)!),
    int.tryParse(core.group(2) ?? '') ?? 0,
    int.tryParse(core.group(3) ?? '') ?? 0,
  ];
}

/// Fetches the latest GitHub release and returns an [UpdateInfo] when it is
/// newer than [currentVersion], else null. Never throws — a network error,
/// non-200, malformed body or timeout all resolve to null (a failed check is
/// silent; we retry next launch). [client]/[endpoint]/[timeout] are injectable
/// for tests.
Future<UpdateInfo?> fetchLatestUpdate({
  required String currentVersion,
  http.Client? client,
  Uri? endpoint,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final owned = client == null;
  final c = client ?? http.Client();
  try {
    final resp = await c
        .get(
          endpoint ?? kReleasesApiEndpoint,
          headers: const {
            // GitHub rejects requests without a User-Agent; the Accept header
            // pins the v3 JSON schema.
            'User-Agent': 'Cullimingo',
            'Accept': 'application/vnd.github+json',
          },
        )
        .timeout(timeout);
    if (resp.statusCode != 200) {
      appTalker.debug('update check: HTTP ${resp.statusCode}');
      return null;
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final tag = (json['tag_name'] as String?)?.trim();
    if (tag == null || tag.isEmpty) return null;
    if (!isNewerVersion(tag, currentVersion)) return null;
    final htmlUrl = json['html_url'] as String?;
    return UpdateInfo(
      version: tag.startsWith('v') ? tag.substring(1) : tag,
      releaseUrl: Uri.parse(
        htmlUrl ?? 'https://github.com/nielsfranke/Cullimingo/releases/latest',
      ),
    );
  } on Object catch (e) {
    appTalker.debug('update check failed: $e');
    return null;
  } finally {
    if (owned) c.close();
  }
}

/// The startup entry point: respects the user's opt-out and the once-a-day
/// throttle, records the check time, then defers to [fetchLatestUpdate].
/// Returns the newer release if one is found, else null. Kicked off from
/// `main()` (via a provider override) so widget tests never reach the network.
Future<UpdateInfo?> checkForUpdatesOnStartup({
  required AppSettings settings,
  required String currentVersion,
  DateTime? now,
  http.Client? client,
  Uri? endpoint,
}) async {
  if (!settings.checkForUpdatesEnabled) return null;
  final at = now ?? DateTime.now();
  if (!isUpdateCheckDue(settings.lastUpdateCheckAt, at)) return null;
  // Record the attempt up front so a hung/failed check still throttles the
  // next launch (we don't want to hammer GitHub on repeated quick relaunches).
  await settings.setLastUpdateCheckAt(at);
  return fetchLatestUpdate(
    currentVersion: currentVersion,
    client: client,
    endpoint: endpoint,
  );
}
