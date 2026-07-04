import 'package:cullimingo/features/filter/domain/filter_preset.dart';
import 'package:cullimingo/features/filter/domain/photo_filter.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PhotoFilter JSON', () {
    test('round-trips every persistable constraint', () {
      const filter = PhotoFilter(
        minRating: 4,
        flag: PickFlag.pick,
        color: ColorLabel.green,
        hasKeyword: true,
        needsCaption: true,
        burstsOnly: true,
        hideJpegPairs: true,
      );
      final restored = PhotoFilter.fromJson(filter.toJson());
      expect(restored.minRating, 4);
      expect(restored.flag, PickFlag.pick);
      expect(restored.color, ColorLabel.green);
      expect(restored.hasKeyword, isTrue);
      expect(restored.needsCaption, isTrue);
      expect(restored.burstsOnly, isTrue);
      expect(restored.hideJpegPairs, isTrue);
    });

    test('does not persist the transient selectedOnly constraint', () {
      const filter = PhotoFilter(selectedOnly: true, minRating: 2);
      expect(filter.toJson().containsKey('selectedOnly'), isFalse);
      expect(PhotoFilter.fromJson(filter.toJson()).selectedOnly, isFalse);
    });

    test('null flag/colour are simply absent (any)', () {
      const filter = PhotoFilter(minRating: 1);
      final json = filter.toJson();
      expect(json.containsKey('flag'), isFalse);
      expect(json.containsKey('color'), isFalse);
      final restored = PhotoFilter.fromJson(json);
      expect(restored.flag, isNull);
      expect(restored.color, isNull);
    });

    test('tolerates missing keys and unknown enum names', () {
      final restored = PhotoFilter.fromJson(const {
        'flag': 'nonsense',
        'color': 42,
      });
      expect(restored.minRating, 0);
      expect(restored.flag, isNull);
      expect(restored.color, isNull);
      expect(restored.isActive, isFalse);
    });
  });

  group('FilterPreset list encode/decode', () {
    test('round-trips a list of presets', () {
      final presets = [
        const FilterPreset(
          name: 'Keepers',
          filter: PhotoFilter(minRating: 4, flag: PickFlag.pick),
        ),
        const FilterPreset(
          name: 'Rejects',
          filter: PhotoFilter(flag: PickFlag.reject),
        ),
      ];
      final decoded = FilterPreset.decodeList(FilterPreset.encodeList(presets));
      expect(decoded.map((p) => p.name), ['Keepers', 'Rejects']);
      expect(decoded.first.filter.minRating, 4);
      expect(decoded.first.filter.flag, PickFlag.pick);
      expect(decoded.last.filter.flag, PickFlag.reject);
    });

    test('null / malformed / unnamed entries are dropped', () {
      expect(FilterPreset.decodeList(null), isEmpty);
      final decoded = FilterPreset.decodeList([
        'not a map',
        const {'filter': <String, dynamic>{}}, // no name → dropped
        const {
          'name': 'Good',
          'filter': {'minRating': 3},
        },
      ]);
      expect(decoded, hasLength(1));
      expect(decoded.single.name, 'Good');
      expect(decoded.single.filter.minRating, 3);
    });
  });
}
