import 'package:cullimingo/features/handoff/domain/cs_models.dart';
import 'package:cullimingo/features/handoff/domain/pull_marks.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter_test/flutter_test.dart';

CsImageMark _mark(
  String filename, {
  int rating = 0,
  String color = 'none',
  int likes = 0,
}) => CsImageMark(
  id: filename,
  filename: filename,
  rating: rating,
  colorFlag: color,
  likes: likes,
);

void main() {
  const photos = [
    (id: 1, path: '/shoot/_AIV9551.ARW'),
    (id: 2, path: '/shoot/_AIV9552.ARW'),
    (id: 3, path: '/shoot/_AIV9553.ARW'),
  ];

  group('csColorToLabel', () {
    test('maps the four client colours', () {
      expect(csColorToLabel('red'), ColorLabel.red);
      expect(csColorToLabel('yellow'), ColorLabel.yellow);
      expect(csColorToLabel('green'), ColorLabel.green);
      expect(csColorToLabel('blue'), ColorLabel.blue);
    });
    test('none/unknown → null', () {
      expect(csColorToLabel('none'), isNull);
      expect(csColorToLabel('purple'), isNull);
    });
  });

  group('resolvePulledMarks', () {
    test('matches by basename ignoring extension (JPEG proof → RAW)', () {
      final out = resolvePulledMarks([
        _mark('_AIV9551.jpg', rating: 5),
      ], photos);
      expect(out, hasLength(1));
      expect(out.single.photoId, 1);
      expect(out.single.rating, 5);
      expect(out.single.color, isNull);
    });

    test('rating 0 does not clobber (null), colour maps', () {
      final out = resolvePulledMarks([
        _mark('_AIV9552.ARW', color: 'green'),
      ], photos);
      expect(out.single.photoId, 2);
      expect(out.single.rating, isNull);
      expect(out.single.color, ColorLabel.green);
    });

    test('a like alone still resolves (for selection) with no marks', () {
      final out = resolvePulledMarks([_mark('_AIV9553.ARW', likes: 1)], photos);
      expect(out.single.photoId, 3);
      expect(out.single.rating, isNull);
      expect(out.single.color, isNull);
    });

    test('untouched photos (no rating/colour/like) are skipped', () {
      final out = resolvePulledMarks([_mark('_AIV9551.ARW')], photos);
      expect(out, isEmpty);
    });

    test('unmatched filenames are ignored', () {
      final out = resolvePulledMarks([
        _mark('_OTHER0001.jpg', rating: 4),
      ], photos);
      expect(out, isEmpty);
    });

    test('clamps an out-of-range rating', () {
      final out = resolvePulledMarks([
        _mark('_AIV9551.ARW', rating: 9),
      ], photos);
      expect(out.single.rating, 5);
    });
  });
}
