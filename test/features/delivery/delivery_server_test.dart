import 'package:cullimingo/features/delivery/domain/delivery_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const server = DeliveryServer(
    id: 'abc-1',
    name: 'AP wire',
    protocol: DeliveryProtocol.ftps,
    host: 'ftp.example.com',
    port: 21,
    username: 'niels',
    remoteDir: 'incoming/photos',
  );

  group('DeliveryServer JSON', () {
    test('round-trips all fields', () {
      final parsed = DeliveryServer.fromJson(server.toJson());
      expect(parsed, server);
    });

    test('defaults remoteDir to empty when missing', () {
      final json = server.toJson()..remove('remoteDir');
      expect(DeliveryServer.fromJson(json)?.remoteDir, '');
    });

    test('rejects malformed maps instead of throwing', () {
      expect(DeliveryServer.fromJson({}), isNull);
      expect(
        DeliveryServer.fromJson(server.toJson()..['protocol'] = 'gopher'),
        isNull,
      );
      expect(DeliveryServer.fromJson(server.toJson()..['host'] = ''), isNull);
      expect(DeliveryServer.fromJson(server.toJson()..remove('id')), isNull);
      expect(
        DeliveryServer.fromJson(server.toJson()..['port'] = 'twenty-one'),
        isNull,
      );
    });

    test('accepts an anonymous (empty) username', () {
      final json = server.toJson()..['username'] = '';
      expect(DeliveryServer.fromJson(json)?.username, '');
    });

    test('round-trips allowSelfSigned and keyFilePath', () {
      final tuned = server.copyWith(
        allowSelfSigned: true,
        keyFilePath: '/home/niels/.ssh/id_ed25519',
      );
      expect(DeliveryServer.fromJson(tuned.toJson()), tuned);
    });

    test('pre-existing JSON without the new keys gets safe defaults', () {
      final json = server.toJson()
        ..remove('allowSelfSigned')
        ..remove('keyFilePath');
      final parsed = DeliveryServer.fromJson(json)!;
      expect(parsed.allowSelfSigned, isFalse);
      expect(parsed.keyFilePath, '');
    });
  });

  group('DeliveryProtocol', () {
    test('default ports follow convention', () {
      expect(DeliveryProtocol.ftp.defaultPort, 21);
      expect(DeliveryProtocol.ftps.defaultPort, 21);
      expect(DeliveryProtocol.sftp.defaultPort, 22);
    });

    test('fromName parses all values and rejects unknowns', () {
      for (final p in DeliveryProtocol.values) {
        expect(DeliveryProtocol.fromName(p.name), p);
      }
      expect(DeliveryProtocol.fromName('gopher'), isNull);
      expect(DeliveryProtocol.fromName(null), isNull);
    });
  });

  test('copyWith keeps the id so the stored password stays attached', () {
    final renamed = server.copyWith(name: 'Reuters');
    expect(renamed.id, server.id);
    expect(renamed.name, 'Reuters');
    expect(renamed.host, server.host);
  });

  test('newId generates distinct ids', () {
    final ids = {for (var i = 0; i < 100; i++) DeliveryServer.newId()};
    expect(ids.length, 100);
  });
}
