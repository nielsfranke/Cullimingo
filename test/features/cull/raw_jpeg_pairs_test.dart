import 'package:cullimingo/features/cull/domain/raw_jpeg_pairs.dart';
import 'package:flutter_test/flutter_test.dart';

PairablePhoto _p(int id, String path, {required bool isRaw}) =>
    (id: id, path: path, isRaw: isRaw);

void main() {
  test('pairs a RAW with its same-name JPEG and hides the JPEG side', () {
    final pairs = RawJpegPairs([
      _p(1, '/cards/_AIV1234.ARW', isRaw: true),
      _p(2, '/cards/_AIV1234.JPG', isRaw: false),
    ]);

    expect(pairs.pairCount, 1);
    expect(pairs.isPaired(1), isTrue);
    expect(pairs.isPaired(2), isTrue);
    expect(pairs.isHiddenJpeg(2), isTrue); // the JPEG is hidden
    expect(pairs.isHiddenJpeg(1), isFalse); // the RAW stays
  });

  test('matches case-insensitively and ignores the directory', () {
    final pairs = RawJpegPairs([
      _p(1, '/a/IMG_1.raf', isRaw: true),
      _p(2, '/b/img_1.JPEG', isRaw: false),
    ]);

    expect(pairs.pairCount, 1);
    expect(pairs.hiddenJpegIds, {2});
  });

  test('all-RAW or all-JPEG basename groups are not pairs', () {
    final pairs = RawJpegPairs([
      _p(1, '/x/solo.ARW', isRaw: true),
      _p(2, '/x/onlyjpg.JPG', isRaw: false),
      _p(3, '/x/another.jpg', isRaw: false),
    ]);

    expect(pairs.pairCount, 0);
    expect(pairs.pairedIds, isEmpty);
    expect(pairs.hiddenJpegIds, isEmpty);
  });

  test('hides every non-RAW variant when several share the RAW basename', () {
    final pairs = RawJpegPairs([
      _p(1, '/c/shot.ARW', isRaw: true),
      _p(2, '/c/shot.JPG', isRaw: false),
      _p(3, '/c/shot.HEIC', isRaw: false),
    ]);

    expect(pairs.pairCount, 1);
    expect(pairs.pairedIds, {1, 2, 3});
    expect(pairs.hiddenJpegIds, {2, 3}); // both non-RAW variants hidden
  });

  test('independent pairs are counted separately', () {
    final pairs = RawJpegPairs([
      _p(1, '/d/a.ARW', isRaw: true),
      _p(2, '/d/a.JPG', isRaw: false),
      _p(3, '/d/b.ARW', isRaw: true),
      _p(4, '/d/b.JPG', isRaw: false),
      _p(5, '/d/c.ARW', isRaw: true), // unpaired RAW
    ]);

    expect(pairs.pairCount, 2);
    expect(pairs.hiddenJpegIds, {2, 4});
    expect(pairs.isPaired(5), isFalse);
  });
}
