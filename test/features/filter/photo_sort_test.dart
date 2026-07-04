import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/filter/domain/photo_sort.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter_test/flutter_test.dart';

Photo _photo({
  required int id,
  String? path,
  DateTime? capturedAt,
  DateTime? mtime,
  int rating = 0,
  ColorLabel color = ColorLabel.none,
  String? camera,
  String? lens,
  int? width,
  int? height,
}) {
  return Photo(
    id: id,
    importId: 1,
    path: path ?? '/x/$id.jpg',
    mtime: mtime ?? DateTime(2026),
    capturedAt: capturedAt,
    camera: camera,
    lens: lens,
    width: width,
    height: height,
    orientation: 1,
    userRotation: 0,
    hasCrop: false,
    rating: rating,
    flag: PickFlag.none,
    colorLabel: color,
    keywords: const [],
    iptc: const IptcCore(),
    hasXmp: false,
    xmpConflict: false,
    previewCached: false,
    isRaw: false,
  );
}

/// The photo ids in sorted order — the compact shape the assertions read.
List<int> _ids(PhotoSort sort, List<Photo> photos) => [
  for (final p in sort.sort(photos)) p.id,
];

void main() {
  group('PhotoSort', () {
    test('the default is capture time ascending', () {
      const sort = PhotoSort();
      expect(sort.key, PhotoSortKey.captureTime);
      expect(sort.ascending, isTrue);
      expect(sort.isDefault, isTrue);
    });

    test('setKey keeps the direction; toggled flips it', () {
      const sort = PhotoSort();
      final byName = sort.withKey(PhotoSortKey.filename);
      expect(byName.key, PhotoSortKey.filename);
      expect(byName.ascending, isTrue);
      expect(byName.isDefault, isFalse);
      expect(sort.toggled().ascending, isFalse);
      // Capture time descending is not the default.
      expect(sort.toggled().isDefault, isFalse);
    });

    test('capture time ascending, descending flips it', () {
      final photos = [
        _photo(id: 1, capturedAt: DateTime(2026, 1, 4)),
        _photo(id: 2, capturedAt: DateTime(2026, 1, 2)),
        _photo(id: 3, capturedAt: DateTime(2026, 1, 3)),
      ];
      expect(_ids(const PhotoSort(), photos), [2, 3, 1]);
      expect(
        _ids(const PhotoSort(ascending: false), photos),
        [1, 3, 2],
      );
    });

    test('missing capture time sinks to the end in both directions', () {
      final photos = [
        _photo(id: 1, capturedAt: DateTime(2026, 1, 3)),
        _photo(id: 2), // no capture time
        _photo(id: 3, capturedAt: DateTime(2026, 1, 2)),
      ];
      expect(_ids(const PhotoSort(), photos), [3, 1, 2]);
      // Descending flips the dated frames but the undated one still trails.
      expect(_ids(const PhotoSort(ascending: false), photos), [1, 3, 2]);
    });

    test('filename sorts naturally (IMG_2 before IMG_10)', () {
      final photos = [
        _photo(id: 1, path: '/x/IMG_10.jpg'),
        _photo(id: 2, path: '/x/IMG_2.jpg'),
        _photo(id: 3, path: '/x/IMG_1.jpg'),
      ];
      const sort = PhotoSort(key: PhotoSortKey.filename);
      expect(_ids(sort, photos), [3, 2, 1]);
    });

    test('rating orders low→high, ties break by capture time', () {
      final photos = [
        _photo(id: 1, rating: 5, capturedAt: DateTime(2026, 1, 3)),
        _photo(id: 2, rating: 3, capturedAt: DateTime(2026, 1, 2)),
        _photo(id: 3, rating: 3, capturedAt: DateTime(2026, 1, 4)),
      ];
      const sort = PhotoSort(key: PhotoSortKey.rating);
      // Both 3-star frames come first, ordered by capture time (2 then 3).
      expect(_ids(sort, photos), [2, 3, 1]);
    });

    test('width sorts numerically; missing width sinks to the end', () {
      final photos = [
        _photo(id: 1, width: 6000),
        _photo(id: 2), // no width
        _photo(id: 3, width: 4000),
      ];
      const sort = PhotoSort(key: PhotoSortKey.width);
      expect(_ids(sort, photos), [3, 1, 2]);
    });

    test('camera sorts case-insensitively; blanks sink to the end', () {
      final photos = [
        _photo(id: 1, camera: 'Sony A7'),
        _photo(id: 2, camera: ''),
        _photo(id: 3, camera: 'canon R5'),
      ];
      const sort = PhotoSort(key: PhotoSortKey.camera);
      expect(_ids(sort, photos), [3, 1, 2]);
    });

    test('sort returns a new list, leaving the input untouched', () {
      final photos = [
        _photo(id: 1, capturedAt: DateTime(2026, 1, 3)),
        _photo(id: 2, capturedAt: DateTime(2026, 1, 2)),
      ];
      final sorted = const PhotoSort().sort(photos);
      expect([for (final p in photos) p.id], [1, 2]);
      expect([for (final p in sorted) p.id], [2, 1]);
    });
  });
}
