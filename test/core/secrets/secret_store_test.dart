import 'package:cullimingo/core/secrets/secret_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deliveryPasswordKey is stable per server id', () {
    expect(deliveryPasswordKey('abc-1'), 'delivery.abc-1.password');
  });

  test('InMemorySecretStore round-trips and deletes', () async {
    final store = InMemorySecretStore();
    expect(await store.read('k'), isNull);
    await store.write('k', 'hunter2');
    expect(await store.read('k'), 'hunter2');
    await store.write('k', 'hunter3');
    expect(await store.read('k'), 'hunter3');
    await store.delete('k');
    expect(await store.read('k'), isNull);
    // Deleting a missing key is not an error.
    await store.delete('k');
  });
}
