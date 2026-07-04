import 'package:cullimingo/features/cull/domain/thumbnail_decode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rounds the physical width up to the next 64px bucket', () {
    // 192 logical * 2.0 dpr = 384 physical -> exactly a bucket boundary.
    expect(
      thumbnailDecodeWidth(displayWidth: 192, devicePixelRatio: 2),
      384,
    );
    // 193 * 2 = 386 -> rounds up to the next bucket (448).
    expect(
      thumbnailDecodeWidth(displayWidth: 193, devicePixelRatio: 2),
      448,
    );
  });

  test('a resize sweep collapses many widths into a few stable keys', () {
    // Cell widths crawling from 300 to 320px during a drag must not each key a
    // new decode: they all land in the same 64px bucket at 2x dpr.
    final keys = {
      for (var w = 300.0; w <= 320.0; w += 1.0)
        thumbnailDecodeWidth(displayWidth: w, devicePixelRatio: 2),
    };
    expect(keys, hasLength(1));
  });

  test('caps at the 1024px cached source resolution', () {
    expect(
      thumbnailDecodeWidth(displayWidth: 900, devicePixelRatio: 2),
      1024,
    );
  });

  test('never returns a non-positive decode width', () {
    expect(thumbnailDecodeWidth(displayWidth: 0, devicePixelRatio: 2), 1);
    expect(thumbnailDecodeWidth(displayWidth: 100, devicePixelRatio: 0), 1);
  });
}
