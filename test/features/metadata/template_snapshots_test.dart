import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/features/metadata/domain/iptc_template.dart';
import 'package:cullimingo/features/metadata/domain/template_snapshots.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const reuters = IptcTemplate(fields: {IptcField.credit: 'Reuters'});
  const dpa = IptcTemplate(fields: {IptcField.credit: 'dpa'});

  group('json round-trip', () {
    test('preserves snapshots, order and the active name', () {
      const snapshots = TemplateSnapshots(
        snapshots: [
          TemplateSnapshot(name: 'Wire', template: reuters),
          TemplateSnapshot(name: 'Agency', template: dpa),
        ],
        activeName: 'Agency',
      );

      final back = TemplateSnapshots.fromJson(snapshots.toJson());

      expect(back.snapshots.map((s) => s.name), ['Wire', 'Agency']);
      expect(back.activeName, 'Agency');
      expect(back.active.fields[IptcField.credit], 'dpa');
    });

    test('skips malformed entries instead of crashing', () {
      final back = TemplateSnapshots.fromJson({
        'active': 42,
        'templates': [
          'nonsense',
          {'name': '', 'template': <String, dynamic>{}},
          {'name': 'Good', 'template': reuters.toJson()},
          {'name': 'NoTemplate'},
        ],
      });

      expect(back.snapshots.map((s) => s.name), ['Good']);
      expect(back.activeName, '');
    });
  });

  group('legacy migration', () {
    test('wraps the old single template as an active Default snapshot', () {
      final migrated = TemplateSnapshots.fromLegacy(reuters.toJson());

      expect(migrated.snapshots, hasLength(1));
      expect(migrated.snapshots.single.name, TemplateSnapshots.legacyName);
      expect(migrated.activeName, TemplateSnapshots.legacyName);
      expect(migrated.active.fields[IptcField.credit], 'Reuters');
    });

    test('an empty legacy template migrates to no snapshots', () {
      final migrated = TemplateSnapshots.fromLegacy(
        const IptcTemplate().toJson(),
      );

      expect(migrated.isEmpty, isTrue);
    });
  });

  group('active resolution', () {
    test('falls back to the first snapshot when the name matches nothing', () {
      const snapshots = TemplateSnapshots(
        snapshots: [TemplateSnapshot(name: 'Wire', template: reuters)],
        activeName: 'gone',
      );

      expect(snapshots.activeSnapshot?.name, 'Wire');
    });

    test('is an empty template when nothing is saved', () {
      expect(const TemplateSnapshots().active.isEmpty, isTrue);
      expect(const TemplateSnapshots().activeSnapshot, isNull);
    });
  });

  group('operations', () {
    const two = TemplateSnapshots(
      snapshots: [
        TemplateSnapshot(name: 'Wire', template: reuters),
        TemplateSnapshot(name: 'Agency', template: dpa),
      ],
      activeName: 'Wire',
    );

    test('setActive switches the active snapshot', () {
      expect(two.setActive('Agency').active.fields[IptcField.credit], 'dpa');
    });

    test('upsert of a new name appends and makes it active', () {
      final next = two.upsert('Stock', const IptcTemplate());

      expect(next.snapshots.map((s) => s.name), ['Wire', 'Agency', 'Stock']);
      expect(next.activeName, 'Stock');
    });

    test('upsert of an existing name replaces in place, keeps active', () {
      final next = two.upsert('Agency', reuters);

      expect(next.snapshots.map((s) => s.name), ['Wire', 'Agency']);
      expect(next.activeName, 'Wire');
      expect(next.snapshots[1].template.fields[IptcField.credit], 'Reuters');
    });

    test('rename keeps the template and follows the active name', () {
      final next = two.rename('Wire', 'AP');

      expect(next.snapshots.map((s) => s.name), ['AP', 'Agency']);
      expect(next.activeName, 'AP');
      expect(next.snapshots.first.template.fields[IptcField.credit], 'Reuters');
    });

    test('remove of the active snapshot activates the first remaining', () {
      final next = two.remove('Wire');

      expect(next.snapshots.map((s) => s.name), ['Agency']);
      expect(next.activeName, 'Agency');
    });

    test('remove of the last snapshot leaves an empty list', () {
      final next = two.remove('Wire').remove('Agency');

      expect(next.isEmpty, isTrue);
      expect(next.activeName, '');
    });
  });
}
