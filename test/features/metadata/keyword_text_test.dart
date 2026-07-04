import 'package:cullimingo/features/metadata/domain/keyword_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseKeywords', () {
    test('splits, trims, and drops blanks', () {
      expect(parseKeywords(' sunset ,  beach , ,portrait'), [
        'sunset',
        'beach',
        'portrait',
      ]);
    });

    test('de-duplicates, keeping first-seen order', () {
      expect(parseKeywords('beach, sunset, beach'), ['beach', 'sunset']);
    });

    test('empty text is no keywords', () {
      expect(parseKeywords('   '), isEmpty);
    });
  });

  test('formatKeywords joins with comma-space and round-trips', () {
    const keywords = ['sunset', 'beach'];
    expect(formatKeywords(keywords), 'sunset, beach');
    expect(parseKeywords(formatKeywords(keywords)), keywords);
  });
}
