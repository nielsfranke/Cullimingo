import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/filter/data/selection_source.dart';
import 'package:cullimingo/features/filter/domain/filename_match.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter_test/flutter_test.dart';

Photo _photo(int id, String path) => Photo(
  id: id,
  importId: 1,
  path: path,
  mtime: DateTime(2026),
  orientation: 1,
  userRotation: 0,
  hasCrop: false,
  rating: 0,
  flag: PickFlag.none,
  colorLabel: ColorLabel.none,
  keywords: const [],
  iptc: const IptcCore(),
  hasXmp: false,
  xmpConflict: false,
  previewCached: false,
  isRaw: path.toLowerCase().endsWith('.arw'),
);

void main() {
  group('matchPhotoIds', () {
    final photos = [
      _photo(1, '/cards/DSC_0001.ARW'),
      _photo(2, '/cards/DSC_0002.ARW'),
      _photo(3, '/cards/DSC_0003.ARW'),
    ];

    test('matches RAWs from a JPEG-named, case/path-varied list', () {
      final ids = matchPhotoIds(
        ['dsc_0001.jpg', '/other/DSC_0003.JPEG'],
        photos,
      );
      expect(ids, {1, 3});
    });

    test('a name with both a RAW and JPEG sibling selects both', () {
      final withJpeg = [...photos, _photo(4, '/cards/DSC_0001.JPG')];
      expect(matchPhotoIds(['DSC_0001.tif'], withJpeg), {1, 4});
    });

    test('unmatched names are ignored', () {
      expect(matchPhotoIds(['nope.jpg'], photos), isEmpty);
    });

    test('matches RAWs from a bare, extension-less list', () {
      // A ContactSheet "exclude extensions" / Photo-Mechanic paste.
      final ids = matchPhotoIds(['DSC_0001', 'DSC_0003'], photos);
      expect(ids, {1, 3});
    });
  });

  group('parseNameTokens', () {
    test('splits a bare space-separated Photo-Mechanic paste', () {
      expect(parseNameTokens('_AIV9551 _AIV9555 _AIV9562'), [
        '_AIV9551',
        '_AIV9555',
        '_AIV9562',
      ]);
    });

    test('splits across newlines, commas, semicolons and pipes', () {
      expect(parseNameTokens('a1\nb2, c3; d4 | e5'), [
        'a1',
        'b2',
        'c3',
        'd4',
        'e5',
      ]);
    });

    test('prefers extension-bearing tokens and drops other columns', () {
      // A CSV row: filename + rating + comment. Only the filename has an ext,
      // so the noisy columns are ignored.
      expect(parseNameTokens('DSC_0001.JPG, 5, keeper shot'), ['DSC_0001.JPG']);
    });

    test('falls back to all tokens when none carry an extension', () {
      expect(parseNameTokens('_AIV9551 _AIV9552'), ['_AIV9551', '_AIV9552']);
    });

    test('de-duplicates by normalised name, first kept', () {
      expect(parseNameTokens('a.jpg A.JPG a.arw'), ['a.jpg']);
    });

    test('skips single-character noise in bare lists', () {
      expect(parseNameTokens('x , _AIV9551'), ['_AIV9551']);
    });
  });

  group('CsvSelectionSource', () {
    test(
      'extracts filenames from a Picdrop-style CSV with header + paths',
      () async {
        const csv = '''
"Filename","Rating","Note"
"DSC_0001.JPG","5","keeper"
/export/web/DSC_0003.jpeg,3,
not-a-file,,
''';
        final list = await const CsvSelectionSource(
          name: 'list.csv',
          content: csv,
        ).load();
        expect(list.filenames, contains('DSC_0001.JPG'));
        expect(list.filenames, contains('DSC_0003.jpeg'));
        expect(list.filenames, hasLength(2));
      },
    );

    test('dedupes case-insensitively', () async {
      final list = await const CsvSelectionSource(
        name: 'list.csv',
        content: 'a.jpg, A.JPG, b.png',
      ).load();
      expect(list.filenames, hasLength(2));
    });

    test('reads a bare, extension-less name list', () async {
      final list = await const CsvSelectionSource(
        name: 'picks.txt',
        content: '_AIV9551 _AIV9555\n_AIV9562',
      ).load();
      expect(list.filenames, ['_AIV9551', '_AIV9555', '_AIV9562']);
    });
  });
}
