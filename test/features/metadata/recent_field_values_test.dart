import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/features/metadata/domain/recent_field_values.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RecentFieldValues', () {
    test('records newest-first and de-dupes', () {
      final r = const RecentFieldValues()
          .record(IptcField.credit, 'AP')
          .record(IptcField.credit, 'Reuters')
          .record(IptcField.credit, 'AP'); // moves AP back to front
      expect(r.forField(IptcField.credit), ['AP', 'Reuters']);
    });

    test('ignores blank values', () {
      final r = const RecentFieldValues().record(IptcField.credit, '   ');
      expect(r.forField(IptcField.credit), isEmpty);
    });

    test('caps per field at RecentFieldValues.cap', () {
      var r = const RecentFieldValues();
      for (var i = 0; i < RecentFieldValues.cap + 5; i++) {
        r = r.record(IptcField.city, 'v$i');
      }
      final values = r.forField(IptcField.city);
      expect(values.length, RecentFieldValues.cap);
      expect(values.first, 'v${RecentFieldValues.cap + 4}'); // newest
      expect(values.contains('v0'), isFalse); // oldest evicted
    });

    test('recordAll folds a template field map', () {
      final r = const RecentFieldValues().recordAll({
        IptcField.credit: 'AP',
        IptcField.city: 'Munich',
        IptcField.headline: '', // blank skipped
      });
      expect(r.forField(IptcField.credit), ['AP']);
      expect(r.forField(IptcField.city), ['Munich']);
      expect(r.forField(IptcField.headline), isEmpty);
    });

    test('JSON round-trips and tolerates junk', () {
      final r = const RecentFieldValues()
          .record(IptcField.credit, 'AP')
          .record(IptcField.city, 'Munich');
      final back = RecentFieldValues.fromJson(r.toJson());
      expect(back.forField(IptcField.credit), ['AP']);
      expect(back.forField(IptcField.city), ['Munich']);

      final junk = RecentFieldValues.fromJson({
        'credit': ['AP', 42, ''],
        'nope': ['x'],
        'city': 'not-a-list',
      });
      expect(junk.forField(IptcField.credit), ['AP']); // non-strings dropped
      expect(junk.forField(IptcField.city), isEmpty);
    });
  });
}
