import 'package:cullimingo/core/update/update_checker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('isNewerVersion', () {
    test('detects a newer major/minor/patch', () {
      expect(isNewerVersion('2.0.0', '1.9.9'), isTrue);
      expect(isNewerVersion('1.3.0', '1.2.9'), isTrue);
      expect(isNewerVersion('1.2.4', '1.2.3'), isTrue);
    });

    test('is false for equal or older', () {
      expect(isNewerVersion('1.2.3', '1.2.3'), isFalse);
      expect(isNewerVersion('1.2.3', '1.2.4'), isFalse);
      expect(isNewerVersion('1.0.0', '2.0.0'), isFalse);
    });

    test('tolerates a leading v and missing components', () {
      expect(isNewerVersion('v1.2.0', '1.1.0'), isTrue);
      expect(isNewerVersion('1.2', '1.2.0'), isFalse); // 1.2 == 1.2.0
      expect(isNewerVersion('2', '1.9.9'), isTrue);
    });

    test('ignores pre-release/build suffixes on the numeric core', () {
      expect(isNewerVersion('1.3.0-beta.1', '1.2.0'), isTrue);
      expect(isNewerVersion('1.2.0-rc.1', '1.2.0'), isFalse);
    });

    test('never nags on unparseable input', () {
      expect(isNewerVersion('nightly', '1.2.3'), isFalse);
      expect(isNewerVersion('1.2.3', 'unknown'), isFalse);
    });
  });

  group('isUpdateCheckDue', () {
    final now = DateTime(2026, 7, 4, 12);

    test('is due when never checked', () {
      expect(isUpdateCheckDue(null, now), isTrue);
    });

    test('is not due within the interval', () {
      expect(
        isUpdateCheckDue(now.subtract(const Duration(hours: 1)), now),
        isFalse,
      );
    });

    test('is due once the interval has elapsed', () {
      expect(
        isUpdateCheckDue(now.subtract(const Duration(hours: 25)), now),
        isTrue,
      );
    });
  });

  group('fetchLatestUpdate', () {
    MockClient jsonClient(int status, String body) =>
        MockClient((_) async => http.Response(body, status));

    test('returns an UpdateInfo when the release is newer', () async {
      final client = jsonClient(
        200,
        '{"tag_name": "v1.4.0", '
        '"html_url": "https://github.com/nielsfranke/Cullimingo/releases/tag/v1.4.0"}',
      );
      final update = await fetchLatestUpdate(
        currentVersion: '1.3.0',
        client: client,
      );
      expect(update, isNotNull);
      expect(update!.version, '1.4.0'); // leading v stripped
      expect(
        update.releaseUrl.toString(),
        'https://github.com/nielsfranke/Cullimingo/releases/tag/v1.4.0',
      );
    });

    test('returns null when up to date', () async {
      final update = await fetchLatestUpdate(
        currentVersion: '1.4.0',
        client: jsonClient(200, '{"tag_name": "1.4.0"}'),
      );
      expect(update, isNull);
    });

    test('falls back to the releases page when html_url is absent', () async {
      final update = await fetchLatestUpdate(
        currentVersion: '1.0.0',
        client: jsonClient(200, '{"tag_name": "1.1.0"}'),
      );
      expect(
        update!.releaseUrl.toString(),
        'https://github.com/nielsfranke/Cullimingo/releases/latest',
      );
    });

    test('returns null on a non-200 response', () async {
      final update = await fetchLatestUpdate(
        currentVersion: '1.0.0',
        client: jsonClient(404, 'Not Found'),
      );
      expect(update, isNull);
    });

    test('returns null on a malformed body', () async {
      final update = await fetchLatestUpdate(
        currentVersion: '1.0.0',
        client: jsonClient(200, 'not json'),
      );
      expect(update, isNull);
    });

    test('returns null when tag_name is missing', () async {
      final update = await fetchLatestUpdate(
        currentVersion: '1.0.0',
        client: jsonClient(200, '{"name": "Release 1.1.0"}'),
      );
      expect(update, isNull);
    });

    test('sends a User-Agent (GitHub rejects requests without one)', () async {
      String? seenUa;
      final client = MockClient((req) async {
        seenUa = req.headers['User-Agent'];
        return http.Response('{"tag_name": "1.0.0"}', 200);
      });
      await fetchLatestUpdate(currentVersion: '1.0.0', client: client);
      expect(seenUa, 'Cullimingo');
    });
  });
}
