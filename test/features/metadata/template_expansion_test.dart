import 'package:cullimingo/features/metadata/domain/code_replacements.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/features/metadata/domain/iptc_structured.dart';
import 'package:cullimingo/features/metadata/domain/iptc_template.dart';
import 'package:cullimingo/features/metadata/domain/template_expansion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('expandTemplateText', () {
    test('expands codes then variables', () {
      final out = expandTemplateText(
        '=copy=',
        vars: {'year': '2026'},
        codes: const CodeReplacements(
          codes: {
            'copy': ['© {year} Jane Doe'],
          },
        ),
      );
      // code → "© {year} Jane Doe", then {year} → 2026.
      expect(out, '© 2026 Jane Doe');
    });
  });

  group('expandTemplate', () {
    test('expands every field value and keyword', () {
      const template = IptcTemplate(
        fields: {
          IptcField.caption: '{name} shot by =ff=',
          IptcField.copyright: '© {year}',
        },
        keywords: ['{camera}', 'sport'],
      );

      final out = expandTemplate(
        template,
        vars: {
          'name': 'DSC_0042',
          'year': '2026',
          'camera': 'A7 IV',
        },
        codes: const CodeReplacements(
          codes: {
            'ff': ['staff'],
          },
        ),
      );

      expect(out.fields[IptcField.caption], 'DSC_0042 shot by staff');
      expect(out.fields[IptcField.copyright], '© 2026');
      expect(out.keywords, ['A7 IV', 'sport']);
      // Modes are preserved.
      expect(out.captionMode, template.captionMode);
    });

    test('null keywords stay null after expansion', () {
      const template = IptcTemplate(fields: {IptcField.city: 'Munich'});
      final out = expandTemplate(
        template,
        vars: const {},
        codes: const CodeReplacements(),
      );
      expect(out.keywords, isNull);
      expect(out.fields[IptcField.city], 'Munich');
    });

    test('expands variables and codes inside structured table cells', () {
      const template = IptcTemplate(
        locationsShown: [IptcLocation(city: '{city}', country: '=cc=')],
        artwork: [IptcArtwork(title: '{event} {year}')],
      );

      final out = expandTemplate(
        template,
        vars: {'city': 'Munich', 'event': 'Marathon', 'year': '2026'},
        codes: const CodeReplacements(
          codes: {
            'cc': ['Germany'],
          },
        ),
      );

      expect(out.locationsShown.single.city, 'Munich');
      expect(out.locationsShown.single.country, 'Germany');
      expect(out.artwork.single.title, 'Marathon 2026');
    });
  });
}
