import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/features/metadata/domain/iptc_structured.dart';
import 'package:cullimingo/features/metadata/domain/iptc_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('applyTemplate fields', () {
    test('writes active fields and preserves the rest', () {
      const existing = IptcCore(caption: 'Old', creator: 'Jane');
      const template = IptcTemplate(
        fields: {IptcField.credit: 'AP', IptcField.city: 'Munich'},
      );

      final out = applyTemplate(existing, const [], template);
      expect(out.iptc.credit, 'AP'); // written
      expect(out.iptc.city, 'Munich'); // written
      expect(out.iptc.caption, 'Old'); // untouched
      expect(out.iptc.creator, 'Jane'); // untouched
    });

    test('an empty template changes nothing', () {
      const existing = IptcCore(caption: 'Keep', credit: 'AP');
      const template = IptcTemplate();
      expect(template.isEmpty, isTrue);

      final out = applyTemplate(existing, const ['a'], template);
      expect(out.iptc.caption, 'Keep');
      expect(out.iptc.credit, 'AP');
      expect(out.keywords, ['a']);
    });
  });

  group('applyTemplate caption modes', () {
    const template = IptcTemplate(fields: {IptcField.caption: 'NEW'});

    test('replace overwrites', () {
      final out = applyTemplate(
        const IptcCore(caption: 'OLD'),
        const [],
        template,
      );
      expect(out.iptc.caption, 'NEW');
    });

    test('prefix puts template text first', () {
      final out = applyTemplate(
        const IptcCore(caption: 'OLD'),
        const [],
        const IptcTemplate(
          fields: {IptcField.caption: 'NEW'},
          textModes: {IptcField.caption: TextApplyMode.prefix},
        ),
      );
      expect(out.iptc.caption, 'NEW OLD');
    });

    test('append puts template text last', () {
      final out = applyTemplate(
        const IptcCore(caption: 'OLD'),
        const [],
        const IptcTemplate(
          fields: {IptcField.caption: 'NEW'},
          textModes: {IptcField.caption: TextApplyMode.append},
        ),
      );
      expect(out.iptc.caption, 'OLD NEW');
    });

    test('append onto an empty caption has no leading space', () {
      final out = applyTemplate(
        const IptcCore(),
        const [],
        const IptcTemplate(
          fields: {IptcField.caption: 'NEW'},
          textModes: {IptcField.caption: TextApplyMode.append},
        ),
      );
      expect(out.iptc.caption, 'NEW');
    });
  });

  group('applyTemplate per-field modes', () {
    test('append works on a non-caption text field (headline)', () {
      final out = applyTemplate(
        const IptcCore(headline: 'OLD'),
        const [],
        const IptcTemplate(
          fields: {IptcField.headline: 'NEW'},
          textModes: {IptcField.headline: TextApplyMode.append},
        ),
      );
      expect(out.iptc.headline, 'OLD NEW');
    });

    test('a non-mergeable field (media topics) ignores append, replaces', () {
      final out = applyTemplate(
        const IptcCore(subjectCodes: 'medtop:1'),
        const [],
        const IptcTemplate(
          fields: {IptcField.subjectCodes: 'medtop:2'},
          textModes: {IptcField.subjectCodes: TextApplyMode.append},
        ),
      );
      // No space-splicing that would corrupt the comma list — just replaced.
      expect(out.iptc.subjectCodes, 'medtop:2');
    });
  });

  group('applyTemplate tables', () {
    test('a template table replaces the photo table when non-empty', () {
      final out = applyTemplate(
        const IptcCore(
          copyrightOwners: [IptcEntity(name: 'Old Owner')],
        ),
        const [],
        const IptcTemplate(
          copyrightOwners: [IptcEntity(name: 'New Owner', identifier: 'x')],
        ),
      );
      expect(out.iptc.copyrightOwners.single.name, 'New Owner');
    });

    test('an empty template table leaves the photo table untouched', () {
      final out = applyTemplate(
        const IptcCore(
          locationsShown: [IptcLocation(city: 'Keep')],
        ),
        const [],
        const IptcTemplate(fields: {IptcField.credit: 'AP'}),
      );
      expect(out.iptc.locationsShown.single.city, 'Keep');
    });
  });

  group('applyTemplate keywords', () {
    test('null keywords leave the existing list untouched', () {
      final out = applyTemplate(
        const IptcCore(),
        const ['sport', 'munich'],
        const IptcTemplate(fields: {IptcField.credit: 'AP'}),
      );
      expect(out.keywords, ['sport', 'munich']);
    });

    test('replace swaps the whole list', () {
      final out = applyTemplate(
        const IptcCore(),
        const ['old'],
        const IptcTemplate(keywords: ['a', 'b']),
      );
      expect(out.keywords, ['a', 'b']);
    });

    test('append merges and de-dupes case-insensitively, keeping order', () {
      final out = applyTemplate(
        const IptcCore(),
        const ['Sport', 'munich'],
        const IptcTemplate(
          keywords: ['munich', 'Final', 'SPORT'],
          keywordMode: KeywordApplyMode.append,
        ),
      );
      expect(out.keywords, ['Sport', 'munich', 'Final']);
    });
  });

  group('IptcTemplate JSON', () {
    test('round-trips fields, modes and keywords', () {
      const template = IptcTemplate(
        fields: {IptcField.credit: 'AP', IptcField.caption: 'Cap'},
        textModes: {IptcField.caption: TextApplyMode.append},
        keywords: ['a', 'b'],
        keywordMode: KeywordApplyMode.append,
      );

      final back = IptcTemplate.fromJson(template.toJson());
      expect(back.fields, {IptcField.credit: 'AP', IptcField.caption: 'Cap'});
      expect(back.captionMode, TextApplyMode.append);
      expect(back.keywords, ['a', 'b']);
      expect(back.keywordMode, KeywordApplyMode.append);
    });

    test('omits keywords when null and reads back as null', () {
      const template = IptcTemplate(fields: {IptcField.city: 'Munich'});
      final json = template.toJson();
      expect(json.containsKey('keywords'), isFalse);
      expect(IptcTemplate.fromJson(json).keywords, isNull);
    });

    test('tolerates unknown field and mode names', () {
      final back = IptcTemplate.fromJson({
        'fields': {'credit': 'AP', 'bogusField': 'x'},
        'captionMode': 'nonsense',
      });
      expect(back.fields, {IptcField.credit: 'AP'});
      expect(back.captionMode, TextApplyMode.replace); // fell back
    });
  });
}
