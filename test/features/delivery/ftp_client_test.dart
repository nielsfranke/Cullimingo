import 'dart:convert';
import 'dart:io';

import 'package:cullimingo/features/delivery/data/delivery_client.dart';
import 'package:cullimingo/features/delivery/data/ftp_client.dart';
import 'package:cullimingo/features/delivery/domain/delivery_server.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ftp_server.dart';

void main() {
  late FakeFtpServer server;

  FtpClient client({String password = 'secret', bool secure = false}) =>
      FtpClient(
        host: '127.0.0.1',
        port: server.port,
        username: 'niels',
        password: password,
        secure: secure,
        timeout: const Duration(seconds: 5),
        onBadCertificate: (_) => true,
      );

  SecurityContext testTls() => SecurityContext()
    ..useCertificateChain('test/features/delivery/fixtures/test_cert.pem')
    ..usePrivateKey('test/features/delivery/fixtures/test_key.pem');

  tearDown(() => server.stop());

  group('plain FTP', () {
    setUp(() async {
      server = FakeFtpServer();
      await server.start();
    });

    test('logs in, creates the remote dir and uploads', () async {
      final ftp = client();
      await ftp.connect();
      await ftp.ensureRemoteDir('incoming/photos');
      await ftp.upload(
        Stream.value(utf8.encode('jpeg bytes')),
        'IMG_0001.jpg',
      );
      await ftp.close();

      expect(server.uploads.keys, ['/incoming/photos/IMG_0001.jpg']);
      expect(utf8.decode(server.uploads.values.single), 'jpeg bytes');
      expect(server.log, contains('TYPE I'));
      expect(server.log, contains('QUIT'));
    });

    test('reuses an existing remote dir without MKD', () async {
      server.dirs.add('/incoming');
      final ftp = client();
      await ftp.connect();
      await ftp.ensureRemoteDir('incoming');
      await ftp.close();
      expect(server.log.where((l) => l.startsWith('MKD')), isEmpty);
    });

    test('uploads several files over one connection', () async {
      final ftp = client();
      await ftp.connect();
      await ftp.upload(Stream.value(utf8.encode('one')), 'a.jpg');
      await ftp.upload(Stream.value(utf8.encode('two')), 'b.jpg');
      await ftp.close();
      expect(server.uploads.keys, containsAll(['/a.jpg', '/b.jpg']));
    });

    test('falls back to PASV when EPSV is not implemented', () async {
      await server.stop();
      server = FakeFtpServer(supportsEpsv: false);
      await server.start();

      final ftp = client();
      await ftp.connect();
      await ftp.upload(Stream.value(utf8.encode('x')), 'pasv.jpg');
      await ftp.close();
      expect(server.uploads.keys, ['/pasv.jpg']);
      expect(server.log, contains('PASV'));
    });

    test('wrong password surfaces as FtpException with the reply', () async {
      final ftp = client(password: 'wrong');
      await expectLater(
        ftp.connect(),
        throwsA(
          isA<FtpException>().having((e) => e.reply?.code, 'reply code', 530),
        ),
      );
      await ftp.close();
    });

    test('a refused STOR throws and leaves no upload behind', () async {
      server.storFailuresRemaining = 1;
      final ftp = client();
      await ftp.connect();
      await expectLater(
        ftp.upload(Stream.value(utf8.encode('x')), 'fail.jpg'),
        throwsA(isA<FtpException>()),
      );
      expect(server.uploads, isEmpty);
      await ftp.close();
    });

    test('connection refused reads as a clear FtpException', () async {
      final dead = FtpClient(
        host: '127.0.0.1',
        // An ephemeral port nothing listens on.
        port: server.port + 1,
        username: 'u',
        password: 'p',
        timeout: const Duration(seconds: 5),
      );
      await expectLater(dead.connect(), throwsA(isA<FtpException>()));
    });
  });

  group('explicit FTPS', () {
    setUp(() async {
      server = FakeFtpServer(tlsContext: testTls());
      await server.start();
    });

    test('upgrades control + data channels and uploads', () async {
      final ftp = client(secure: true);
      await ftp.connect();
      await ftp.ensureRemoteDir('wire');
      await ftp.upload(Stream.value(utf8.encode('secure bytes')), 'tls.jpg');
      await ftp.close();

      expect(server.log, contains('AUTH TLS'));
      expect(server.log, contains('PROT P'));
      expect(utf8.decode(server.uploads['/wire/tls.jpg']!), 'secure bytes');
      // Credentials must only travel after the upgrade — the fake logs every
      // line it *parsed*, and it parses USER/PASS through the TLS reader, so
      // reaching 230 already proves it. Belt and braces: order in the log.
      expect(
        server.log.indexOf('AUTH TLS'),
        lessThan(server.log.indexOf('PASS secret')),
      );
    });

    DeliveryServer config({required bool allowSelfSigned}) => DeliveryServer(
      id: 's1',
      name: 'wire',
      protocol: DeliveryProtocol.ftps,
      host: '127.0.0.1',
      port: server.port,
      username: 'niels',
      allowSelfSigned: allowSelfSigned,
    );

    test(
      'allowSelfSigned accepts the fixture cert without test hooks',
      () async {
        final ftp = createDeliveryClient(
          config(allowSelfSigned: true),
          'secret',
          timeout: const Duration(seconds: 5),
        );
        await ftp.connect();
        await ftp.ensureRemoteDir('wire');
        await ftp.close();
        expect(server.log, contains('AUTH TLS'));
      },
    );

    test('without allowSelfSigned a self-signed cert is rejected', () async {
      final ftp = createDeliveryClient(
        config(allowSelfSigned: false),
        'secret',
        timeout: const Duration(seconds: 5),
      );
      await expectLater(
        ftp.connect(),
        throwsA(
          isA<FtpException>().having(
            (e) => e.message,
            'message',
            contains('TLS handshake'),
          ),
        ),
      );
      await ftp.close();
    });

    test('server without TLS refuses AUTH TLS → clear error', () async {
      await server.stop();
      server = FakeFtpServer();
      await server.start();
      final ftp = client(secure: true);
      await expectLater(
        ftp.connect(),
        throwsA(
          isA<FtpException>().having(
            (e) => e.message,
            'message',
            contains('AUTH TLS'),
          ),
        ),
      );
    });
  });
}
