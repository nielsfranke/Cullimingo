import 'package:cullimingo/core/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('appTalker records logs in its shared history', () {
    final marker = 'log-test-${DateTime.now().microsecondsSinceEpoch}';
    appTalker.warning(marker);

    expect(
      appTalker.history.any((e) => e.message?.contains(marker) ?? false),
      isTrue,
    );
  });
}
