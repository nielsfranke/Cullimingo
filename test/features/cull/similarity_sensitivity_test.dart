import 'package:cullimingo/features/cull/domain/similarity_sensitivity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('presets map to ascending dHash distances', () {
    expect(SimilaritySensitivity.strict.maxDistance, 5);
    expect(SimilaritySensitivity.balanced.maxDistance, 10);
    expect(SimilaritySensitivity.loose.maxDistance, 16);
    expect(
      SimilaritySensitivity.strict.maxDistance,
      lessThan(SimilaritySensitivity.loose.maxDistance),
    );
  });

  test('fromName round-trips and falls back to balanced', () {
    for (final s in SimilaritySensitivity.values) {
      expect(SimilaritySensitivity.fromName(s.name), s);
    }
    expect(
      SimilaritySensitivity.fromName(null),
      SimilaritySensitivity.balanced,
    );
    expect(
      SimilaritySensitivity.fromName('nonsense'),
      SimilaritySensitivity.balanced,
    );
    expect(SimilaritySensitivity.fallback, SimilaritySensitivity.balanced);
  });
}
