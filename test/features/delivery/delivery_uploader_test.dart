import 'dart:convert';
import 'dart:io';

import 'package:cullimingo/features/delivery/data/delivery_client.dart';
import 'package:cullimingo/features/delivery/data/delivery_uploader.dart';
import 'package:cullimingo/features/delivery/data/ftp_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ftp_server.dart';

void main() {
  late FakeFtpServer server;
  late Directory tmp;

  setUp(() async {
    server = FakeFtpServer();
    await server.start();
    tmp = Directory.systemTemp.createTempSync('cullimingo_delivery_test');
  });

  tearDown(() async {
    await server.stop();
    tmp.deleteSync(recursive: true);
  });

  DeliveryItem file(String name, String content) {
    final f = File('${tmp.path}/$name')..writeAsStringSync(content);
    return DeliveryItem(localPath: f.path, remoteName: name);
  }

  DeliveryClient client({String password = 'secret'}) => FtpClient(
    host: '127.0.0.1',
    port: server.port,
    username: 'niels',
    password: password,
    timeout: const Duration(seconds: 5),
  );

  test('delivers all files over one connection with progress ticks', () async {
    final items = [file('a.jpg', 'aaa'), file('b.jpg', 'bbb')];
    final ticks = await runDelivery(
      items: items,
      connectClient: client,
      remoteDir: 'incoming',
      retryDelay: Duration.zero,
    ).toList();

    expect(ticks.map((t) => t.done), [1, 2]);
    expect(ticks.every((t) => t.last.ok), isTrue);
    expect(utf8.decode(server.uploads['/incoming/a.jpg']!), 'aaa');
    expect(utf8.decode(server.uploads['/incoming/b.jpg']!), 'bbb');
    // One connection: exactly one login for two files.
    expect(server.log.where((l) => l.startsWith('PASS')).length, 1);
  });

  test('a transient STOR failure is retried on a fresh connection', () async {
    server.storFailuresRemaining = 1;
    final ticks = await runDelivery(
      items: [file('a.jpg', 'aaa')],
      connectClient: client,
      remoteDir: '',
      retryDelay: Duration.zero,
    ).toList();

    expect(ticks.single.last.ok, isTrue);
    expect(server.uploads.keys, ['/a.jpg']);
    // Failed try + successful retry = two logins.
    expect(server.log.where((l) => l.startsWith('PASS')).length, 2);
  });

  test(
    'a file failing every attempt is recorded, the next still runs',
    () async {
      server.storFailuresRemaining = 2;
      final ticks = await runDelivery(
        items: [file('a.jpg', 'aaa'), file('b.jpg', 'bbb')],
        connectClient: client,
        remoteDir: '',
        attemptsPerFile: 2,
        retryDelay: Duration.zero,
      ).toList();

      final summary = DeliverySummary([for (final t in ticks) t.last]);
      expect(summary.delivered, 1);
      expect(summary.failures.single.item.remoteName, 'a.jpg');
      expect(summary.failures.single.error, contains('refused'));
      expect(server.uploads.keys, ['/b.jpg']);
    },
  );

  test('an unreachable server fails everything fast (abort-all)', () async {
    final items = [file('a.jpg', 'a'), file('b.jpg', 'b'), file('c.jpg', 'c')];
    final ticks = await runDelivery(
      items: items,
      connectClient: () => client(password: 'wrong'),
      remoteDir: '',
      attemptsPerFile: 2,
      retryDelay: Duration.zero,
    ).toList();

    final summary = DeliverySummary([for (final t in ticks) t.last]);
    expect(summary.allOk, isFalse);
    expect(summary.delivered, 0);
    expect(summary.failures.length, 3);
    // Only the first file burned real attempts; the rest failed immediately
    // with the same connection error.
    expect(server.log.where((l) => l.startsWith('PASS')).length, 2);
  });

  group('deliveryItemsFor', () {
    test('flattens nested export paths to basenames', () {
      final items = deliveryItemsFor(
        localRoot: '/tmp/x',
        relPaths: ['2026/2026-07-02/a.jpg', 'b.jpg'],
      );
      expect(items.map((i) => i.remoteName), ['a.jpg', 'b.jpg']);
      expect(items.first.localPath, '/tmp/x/2026/2026-07-02/a.jpg');
    });

    test('colliding basenames keep their path, / flattened to _', () {
      final items = deliveryItemsFor(
        localRoot: '/tmp/x',
        relPaths: ['2025/a.jpg', '2026/a.jpg', 'b.jpg'],
      );
      expect(items.map((i) => i.remoteName), [
        '2025_a.jpg',
        '2026_a.jpg',
        'b.jpg',
      ]);
    });
  });

  group('testDeliveryConnection', () {
    test('returns null on success', () async {
      expect(await testDeliveryConnection(client(), 'incoming'), isNull);
    });

    test('returns the refusal message on bad credentials', () async {
      final message = await testDeliveryConnection(
        client(password: 'wrong'),
        '',
      );
      expect(message, contains('login'));
    });
  });
}
