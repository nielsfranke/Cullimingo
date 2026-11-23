import 'dart:ui';

import 'package:cullimingo/app/window_size.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps the default on a roomy display', () {
    expect(firstRunWindowSize(const Size(1920, 1080)), kDefaultWindowSize);
  });

  test('fits a 1280×800 laptop with the title bar on screen', () {
    final size = firstRunWindowSize(const Size(1280, 800));
    expect(size.width, lessThan(1280));
    expect(size.height, lessThanOrEqualTo(800 - 100));
  });

  test('never goes below the minimum window size', () {
    expect(firstRunWindowSize(const Size(1024, 600)), const Size(992, 640));
  });

  test('an unknown display keeps the default', () {
    expect(firstRunWindowSize(null), kDefaultWindowSize);
    expect(firstRunWindowSize(Size.zero), kDefaultWindowSize);
  });
}
