import 'dart:ui';

import 'package:cullimingo/core/cache/display_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('loupeLongEdgeForDisplays', () {
    test('falls back to the floor when no display is reported', () {
      expect(loupeLongEdgeForDisplays(const []), 2048);
    });

    test('a ≤1080p display stays at the floor (no regression)', () {
      expect(loupeLongEdgeForDisplays(const [Size(1920, 1080)]), 2048);
    });

    test('scales up to a 4K/5K display long edge', () {
      expect(loupeLongEdgeForDisplays(const [Size(3840, 2160)]), 3840);
      expect(loupeLongEdgeForDisplays(const [Size(5120, 2880)]), 5120);
    });

    test('uses the largest of several connected displays', () {
      expect(
        loupeLongEdgeForDisplays(const [
          Size(1920, 1080),
          Size(3840, 2160),
          Size(2560, 1440),
        ]),
        3840,
      );
    });

    test('honours a portrait orientation via the long edge', () {
      expect(loupeLongEdgeForDisplays(const [Size(2160, 3840)]), 3840);
    });

    test('clamps an enormous canvas to the ceiling', () {
      expect(loupeLongEdgeForDisplays(const [Size(7680, 4320)]), 6016);
    });
  });
}
