import 'package:cullimingo/features/metadata/domain/template_variables.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('templateVariables', () {
    test('derives date parts and filename tokens from a photo', () {
      final vars = templateVariables(
        path: '/cards/shootA/DSC_0042.ARW',
        capturedAt: DateTime(2026, 3, 7, 9, 5, 2),
        camera: 'Sony ILCE-7M4',
        sequence: 3,
      );
      expect(vars['year'], '2026');
      expect(vars['month'], '03');
      expect(vars['day'], '07');
      expect(vars['date'], '2026-03-07');
      expect(vars['time'], '09:05:02');
      expect(vars['filename'], 'DSC_0042.ARW');
      expect(vars['name'], 'DSC_0042');
      expect(vars['ext'], 'ARW');
      expect(vars['camera'], 'Sony ILCE-7M4');
      expect(vars['seq'], '3');
      // No lens given → token omitted.
      expect(vars.containsKey('lens'), isFalse);
    });

    test(
      'date tokens fall back to today when the photo has no capture time',
      () {
        final vars = templateVariables(path: '/x/a.jpg');
        final now = DateTime.now();
        expect(vars['year'], '${now.year}');
      },
    );
  });

  group('expandVariables', () {
    final vars = {'year': '2026', 'name': 'DSC_0042', 'camera': 'A7 IV'};

    test('replaces known tokens', () {
      expect(expandVariables('© {year} Jane Doe', vars), '© 2026 Jane Doe');
      expect(
        expandVariables('{name} on {camera}', vars),
        'DSC_0042 on A7 IV',
      );
    });

    test('leaves unknown tokens untouched', () {
      expect(expandVariables('a {bogus} b', vars), 'a {bogus} b');
    });

    test('no tokens is a passthrough', () {
      expect(expandVariables('plain caption', vars), 'plain caption');
    });
  });

  group('translatePmVariables', () {
    test('maps long and short Photo Mechanic names to our tokens', () {
      expect(
        translatePmVariables('{filenamebase} shot on {model}'),
        '{name} shot on {camera}',
      );
      expect(
        translatePmVariables('{fbas}-{yr4}-{seqn}'),
        '{name}-{year}-{seq}',
      );
      expect(
        translatePmVariables('© {year4} · {lenstype}'),
        '© {year} · {lens}',
      );
    });

    test('datesort becomes the YYYYMMDD composite', () {
      expect(translatePmVariables('{datesort}_A'), '{year}{month}{day}_A');
      expect(translatePmVariables('{dats}'), '{year}{month}{day}');
    });

    test('matches case-insensitively, like Photo Mechanic', () {
      expect(translatePmVariables('{Model} {YEAR4}'), '{camera} {year}');
    });

    test('unknown PM variables stay literal (visible, not blanked)', () {
      expect(translatePmVariables('{hour24}{iptccity}'), '{hour24}{iptccity}');
    });

    test('our own tokens pass through untouched', () {
      const ours = '© {year} {name} on {camera}, {lens} — {seq}/{date}';
      expect(translatePmVariables(ours), ours);
    });

    test('translated output expands with photo variables', () {
      final vars = templateVariables(
        path: '/cards/DSC_0042.ARW',
        capturedAt: DateTime(2026, 3, 7),
        camera: 'Sony ILCE-7M4',
      );
      expect(
        expandVariables(translatePmVariables('{fbas} {datesort}'), vars),
        'DSC_0042 20260307',
      );
    });
  });
}
