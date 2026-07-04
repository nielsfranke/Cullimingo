import 'package:cullimingo/features/handoff/domain/cs_models.dart';
import 'package:cullimingo/features/handoff/domain/pull_collections.dart';
import 'package:flutter_test/flutter_test.dart';

CsImageMark _img(String id, String filename) => CsImageMark(
  id: id,
  filename: filename,
  rating: 0,
  colorFlag: 'none',
  likes: 0,
);

void main() {
  const photos = [
    (id: 1, path: '/shoot/_AIV9551.ARW'),
    (id: 2, path: '/shoot/_AIV9552.ARW'),
    (id: 3, path: '/shoot/_AIV9553.ARW'),
  ];

  // ContactSheet holds downscaled JPEGs; ids link collection members to names.
  final images = [
    _img('a', '_AIV9551.JPG'),
    _img('b', '_AIV9552.JPG'),
    _img('c', '_AIV9553.JPG'),
  ];

  test('maps a collection to local photo ids (JPEG proof → RAW)', () {
    final sels = resolveCollectionSelections(
      [
        const CsCollection(id: 'c1', name: 'Favourites', imageIds: ['a', 'c']),
      ],
      images,
      photos,
    );
    expect(sels.single.name, 'Favourites');
    expect(sels.single.photoIds, [1, 3]);
  });

  test('de-dupes and skips unknown image ids', () {
    final sels = resolveCollectionSelections(
      [
        const CsCollection(
          id: 'c1',
          name: 'Dup',
          imageIds: ['a', 'a', 'zzz'],
        ),
      ],
      images,
      photos,
    );
    expect(sels.single.photoIds, [1]);
  });

  test('skips a collection with no local match', () {
    final sels = resolveCollectionSelections(
      [
        const CsCollection(id: 'c1', name: 'Empty', imageIds: ['nope']),
      ],
      images,
      photos,
    );
    expect(sels, isEmpty);
  });
}
