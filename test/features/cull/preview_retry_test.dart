import 'dart:typed_data';

import 'package:cullimingo/features/cull/domain/preview_retry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bytes = Uint8List.fromList([1, 2, 3]);
  Future<void> noSleep(Duration _) async {}

  group('retryPreview', () {
    test('returns bytes from the first attempt without retrying', () async {
      var calls = 0;
      final result = await retryPreview(
        () async {
          calls++;
          return bytes;
        },
        isCancelled: () => false,
        sleep: noSleep,
      );
      expect(result, bytes);
      expect(calls, 1);
    });

    test('retries a transient null, then succeeds', () async {
      var calls = 0;
      final result = await retryPreview(
        () async {
          calls++;
          return calls < 3 ? null : bytes; // fail twice, then succeed
        },
        isCancelled: () => false,
        sleep: noSleep,
      );
      expect(result, bytes);
      expect(calls, 3);
    });

    test('gives up after the bounded number of attempts', () async {
      var calls = 0;
      final result = await retryPreview(
        () async {
          calls++;
          return null; // never succeeds
        },
        isCancelled: () => false,
        delays: const [Duration.zero, Duration.zero],
        sleep: noSleep,
      );
      expect(result, isNull);
      expect(calls, 3); // initial + 2 retries
    });

    test('non-retryable null (e.g. a video) is not retried', () async {
      var calls = 0;
      final result = await retryPreview(
        () async {
          calls++;
          return null;
        },
        isCancelled: () => false,
        retryable: false,
        sleep: noSleep,
      );
      expect(result, isNull);
      expect(calls, 1);
    });

    test('stops retrying the moment the request is cancelled', () async {
      var calls = 0;
      var cancelled = false;
      final result = await retryPreview(
        () async {
          calls++;
          cancelled = true; // cell scrolled off after the first miss
          return null;
        },
        isCancelled: () => cancelled,
        sleep: noSleep,
      );
      expect(result, isNull);
      expect(calls, 1); // no further attempts once cancelled
    });
  });
}
