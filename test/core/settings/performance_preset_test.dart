import 'package:cullimingo/core/settings/performance_preset.dart';
import 'package:flutter_test/flutter_test.dart';

const int _gb = 1024 * 1024 * 1024;
const int _mb = 1024 * 1024;

void main() {
  group('resolvePerformance', () {
    test('lean uses 768px and caps RAM at ~96MB on a roomy machine', () {
      final s = resolvePerformance(
        PerformancePreset.lean,
        totalBytes: 32 * _gb,
      );
      expect(s.thumbLongEdge, 768);
      expect(s.ramBudgetBytes, 96 * _mb);
    });

    test('lean RAM follows the auto budget when that is below the cap', () {
      // 4 GB → auto 64 MB (the floor) < 96 MB cap.
      final s = resolvePerformance(PerformancePreset.lean, totalBytes: 4 * _gb);
      expect(s.ramBudgetBytes, 64 * _mb);
    });

    test('balanced uses 1024px and the auto RAM budget', () {
      final s = resolvePerformance(
        PerformancePreset.balanced,
        totalBytes: 8 * _gb,
      );
      expect(s.thumbLongEdge, 1024);
      expect(s.ramBudgetBytes, 128 * _mb); // 8GB / 64
    });

    test('max uses 1024px and the 256MB cap regardless of RAM', () {
      final s = resolvePerformance(PerformancePreset.max, totalBytes: 8 * _gb);
      expect(s.thumbLongEdge, 1024);
      expect(s.ramBudgetBytes, 256 * _mb);
    });
  });

  group('recommendedPreset', () {
    test('<8GB → lean', () {
      expect(recommendedPreset(totalBytes: 4 * _gb), PerformancePreset.lean);
    });
    test('8–16GB → balanced', () {
      expect(
        recommendedPreset(totalBytes: 12 * _gb),
        PerformancePreset.balanced,
      );
    });
    test('≥16GB → max', () {
      expect(recommendedPreset(totalBytes: 24 * _gb), PerformancePreset.max);
    });
    test('unknown RAM → lean (conservative)', () {
      expect(recommendedPreset(), PerformancePreset.lean);
    });
  });

  group('availablePresets', () {
    test('hides Max under 12GB', () {
      expect(availablePresets(totalBytes: 8 * _gb), [
        PerformancePreset.lean,
        PerformancePreset.balanced,
      ]);
    });
    test('offers all three at 12GB+', () {
      expect(
        availablePresets(totalBytes: 16 * _gb),
        PerformancePreset.values,
      );
    });
    test('unknown RAM hides Max', () {
      expect(availablePresets(), isNot(contains(PerformancePreset.max)));
    });
    test('the recommended preset is always offered', () {
      for (final ram in [4, 8, 12, 16, 24, 64]) {
        final bytes = ram * _gb;
        expect(
          availablePresets(totalBytes: bytes),
          contains(recommendedPreset(totalBytes: bytes)),
        );
      }
    });
  });

  test('fromName round-trips and rejects junk', () {
    expect(PerformancePreset.fromName('balanced'), PerformancePreset.balanced);
    expect(PerformancePreset.fromName('nope'), isNull);
    expect(PerformancePreset.fromName(null), isNull);
  });
}
