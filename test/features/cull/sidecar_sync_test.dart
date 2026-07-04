import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  test('starts idle at zero', () {
    expect(makeContainer().read(sidecarSyncProvider), 0);
  });

  test('add increments and decrements, clamped at zero', () {
    final container = makeContainer();
    final sync = container.read(sidecarSyncProvider.notifier)..add(3);

    expect(container.read(sidecarSyncProvider), 3);
    sync.add(-1);
    expect(container.read(sidecarSyncProvider), 2);
    // A stray over-decrement can't drive it negative (would wedge drain).
    sync.add(-5);
    expect(container.read(sidecarSyncProvider), 0);
  });

  test('drain returns immediately when idle', () async {
    final container = makeContainer();
    await container.read(sidecarSyncProvider.notifier).drain();
    expect(container.read(sidecarSyncProvider), 0);
  });

  test('drain completes once the pending writes finish', () async {
    final container = makeContainer();
    final sync = container.read(sidecarSyncProvider.notifier)..add(2);

    // Finish the writes shortly after the drain starts polling.
    Future<void>.delayed(
      const Duration(milliseconds: 20),
      () => sync.add(-2),
    );
    await sync.drain(pollInterval: const Duration(milliseconds: 5));

    expect(container.read(sidecarSyncProvider), 0);
  });

  test('drain gives up after the timeout when writes never finish', () async {
    final container = makeContainer();
    container.read(sidecarSyncProvider.notifier).add(1);

    final sw = Stopwatch()..start();
    await container
        .read(sidecarSyncProvider.notifier)
        .drain(
          timeout: const Duration(milliseconds: 40),
          pollInterval: const Duration(milliseconds: 5),
        );
    sw.stop();

    expect(container.read(sidecarSyncProvider), 1); // still pending
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(30));
  });
}
