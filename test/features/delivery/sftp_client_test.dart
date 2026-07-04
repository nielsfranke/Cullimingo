import 'package:cullimingo/features/delivery/data/delivery_client.dart';
import 'package:cullimingo/features/delivery/data/sftp_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A real SFTP round-trip needs an sshd; these cover the failure edges the
  // fake FTP server can't.

  test('a missing key file fails fast with a clear message', () async {
    final client = SftpDeliveryClient(
      host: '127.0.0.1',
      port: 22,
      username: 'niels',
      password: '',
      keyFilePath: '/nonexistent/id_ed25519',
      timeout: const Duration(seconds: 2),
    );
    await expectLater(
      client.connect(),
      throwsA(
        isA<DeliveryException>().having(
          (e) => e.message,
          'message',
          contains('Could not read the key'),
        ),
      ),
    );
  });

  test('methods before connect throw DeliveryException, not a null error', () {
    final client = SftpDeliveryClient(
      host: 'h',
      port: 22,
      username: 'u',
      password: 'p',
    );
    expect(
      () => client.uploadFile('/tmp/x.jpg', 'x.jpg'),
      throwsA(isA<DeliveryException>()),
    );
  });
}
