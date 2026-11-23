import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cullimingo/core/update/install_target.dart';
import 'package:cullimingo/core/update/update_installer.dart';
import 'package:cullimingo/core/update/update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A throwaway key pair (not the release key): the package below was signed
/// with its private half by `tool/update_manifest.py make`, so these tests
/// prove the Python/OpenSSL signer and the Dart verifier agree.
const _testPublicKey = 'Er0EF08sy8FFoVPLvdpMBf5j0vXqlqs6gKpqtjUIFtI=';
const _packageBody = 'cullimingo test package\n';
const _packageSha =
    'a79091d608fe85710c38e24b9c4505cfd16b070b8b7bc41082a406c6a7096020';
const _signature =
    '86k056u0OR4uNfiyMZIll6KgrYogtzfuKupcBMmn/6zq5OI6OAjMrsKy5JUGC/3G3tRI1yXJ'
    '0REjP1baa2N8AA==';

const _target = InstallTarget(
  method: InstallMethod.linuxAppImage,
  path: '/opt/Cullimingo.AppImage',
  manifestKey: 'linux-x64-appimage',
);

Map<String, Object> _manifest(String baseUrl, {String version = '9.9.9'}) => {
  'format': 1,
  'version': version,
  'packages': {
    'linux-x64-appimage': {
      'name': 'Cullimingo-x86_64.AppImage',
      'size': _packageBody.length,
      'sha256': _packageSha,
      // https only in real manifests; the test server is plain http, so the
      // tests patch the parsed URL (see _serve).
      'url': 'https://example.invalid/Cullimingo-x86_64.AppImage',
      'signature': _signature,
    },
  },
};

void main() {
  group('signature', () {
    test('accepts the signer tool output, refuses any change', () {
      String statement({
        String version = '9.9.9',
        String key = 'linux-x64-appimage',
        String name = 'Cullimingo-x86_64.AppImage',
        String sha = _packageSha,
      }) =>
          updateStatement(version: version, key: key, name: name, sha256: sha);

      bool ok(String s) => verifyUpdateSignature(
        statement: s,
        signature: _signature,
        publicKey: _testPublicKey,
      );

      expect(ok(statement()), isTrue);
      expect(ok(statement(version: '9.9.8')), isFalse, reason: 'replay');
      expect(ok(statement(key: 'windows-x64-nsis')), isFalse);
      expect(ok(statement(name: 'other.AppImage')), isFalse);
      expect(ok(statement(sha: '0' * 64)), isFalse);
      // The real release key didn't sign it.
      expect(
        verifyUpdateSignature(statement: statement(), signature: _signature),
        isFalse,
      );
      expect(
        verifyUpdateSignature(
          statement: statement(),
          signature: 'not base64!',
          publicKey: _testPublicKey,
        ),
        isFalse,
      );
    });

    test('the shipped public key is a 32-byte key', () {
      expect(base64.decode(kUpdatePublicKey), hasLength(32));
    });
  });

  group('manifest', () {
    test('parses packages and drops non-https or malformed entries', () {
      final json = _manifest('');
      (json['packages']! as Map<String, Object>)['windows-x64-nsis'] = {
        'name': 'x.exe',
        'size': 1,
        'sha256': 'ab',
        'url': 'http://insecure.example/x.exe',
        'signature': 'AA==',
      };
      final m = UpdateManifest.parse(jsonEncode(json));
      expect(m.version, '9.9.9');
      expect(m.packages.keys, ['linux-x64-appimage']);
      expect(
        () => UpdateManifest.parse('{"format": 2}'),
        throwsFormatException,
      );
    });
  });

  group('downloadUpdate', () {
    late Directory tmp;
    late HttpServer server;
    var body = _packageBody;
    var manifestVersion = '9.9.9';

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('cm_update');
      body = _packageBody;
      manifestVersion = '9.9.9';
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        final base = 'http://127.0.0.1:${server.port}';
        if (req.uri.path == '/latest.json') {
          final m = _manifest(base, version: manifestVersion);
          // Point the package at this server (real manifests are https).
          ((m['packages']! as Map)['linux-x64-appimage'] as Map)['url'] =
              '$base/pkg';
          req.response.write(jsonEncode(m));
        } else if (req.uri.path == '/pkg') {
          req.response.write(body);
        } else {
          req.response.statusCode = 404;
        }
        unawaited(req.response.close());
      });
    });

    tearDown(() async {
      await server.close(force: true);
      tmp.deleteSync(recursive: true);
    });

    Future<StagedUpdate> run() => downloadUpdate(
      version: '9.9.9',
      target: _target,
      workDir: Directory(p.join(tmp.path, 'work')),
      manifestUrl: Uri.parse('http://127.0.0.1:${server.port}/latest.json'),
      publicKey: _testPublicKey,
      allowInsecureForTests: true,
    );

    test('downloads and verifies a signed package', () async {
      final ticks = <int>[];
      final staged = await downloadUpdate(
        version: '9.9.9',
        target: _target,
        workDir: Directory(p.join(tmp.path, 'work')),
        manifestUrl: Uri.parse('http://127.0.0.1:${server.port}/latest.json'),
        publicKey: _testPublicKey,
        allowInsecureForTests: true,
        onProgress: (received, _) => ticks.add(received),
      );
      expect(staged.file.readAsStringSync(), _packageBody);
      expect(staged.version, '9.9.9');
      expect(ticks.last, _packageBody.length);
    });

    test('refuses a tampered download', () async {
      body = 'cullimingo test packagE\n'; // same size, other bytes
      await expectLater(
        run(),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.signature,
          ),
        ),
      );
    });

    test('refuses a manifest for another version', () async {
      manifestVersion = '9.9.8';
      await expectLater(
        run(),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.manifest,
          ),
        ),
      );
    });

    test('refuses a release without this package kind', () async {
      await expectLater(
        downloadUpdate(
          version: '9.9.9',
          target: const InstallTarget(
            method: InstallMethod.windowsNsis,
            path: r'C:\x',
            manifestKey: 'windows-x64-nsis',
          ),
          workDir: Directory(p.join(tmp.path, 'work')),
          manifestUrl: Uri.parse('http://127.0.0.1:${server.port}/latest.json'),
          publicKey: _testPublicKey,
          allowInsecureForTests: true,
        ),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.noPackage,
          ),
        ),
      );
    });
  });
}
