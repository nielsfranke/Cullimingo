import 'dart:io';

import 'package:cullimingo/features/metadata/data/template_file.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/features/metadata/domain/iptc_structured.dart';
import 'package:cullimingo/features/metadata/domain/iptc_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('templateFromIptc', () {
    test('non-empty fields become active Replace fields', () {
      final iptc = const IptcCore().withOverrides({
        IptcField.caption: 'Match report',
        IptcField.credit: 'AP',
      });
      final template = templateFromIptc(iptc, keywords: ['sport']);
      expect(template.fields, {
        IptcField.caption: 'Match report',
        IptcField.credit: 'AP',
      });
      expect(template.modeFor(IptcField.caption), TextApplyMode.replace);
      expect(template.keywords, ['sport']);
    });

    test('empty keywords leave the template keyword-neutral', () {
      final template = templateFromIptc(
        const IptcCore().withOverrides({IptcField.creator: 'Niels'}),
      );
      expect(template.keywords, isNull);
    });

    test('Date Created never becomes a template field', () {
      final iptc = const IptcCore().withOverrides({
        IptcField.dateCreated: '2026-05-01T10:00:00',
        IptcField.city: 'Bremen',
      });
      final template = templateFromIptc(iptc);
      expect(template.fields.keys, [IptcField.city]);
    });

    test('structured tables are copied', () {
      final iptc = const IptcCore().withStructured(
        locationsShown: [const IptcLocation(city: 'Bremen')],
        licensors: [const IptcLicensor(name: 'Agency')],
      );
      final template = templateFromIptc(iptc);
      expect(template.locationsShown.single.city, 'Bremen');
      expect(template.licensors.single.name, 'Agency');
      expect(template.hasStructured, isTrue);
    });
  });

  group('XMP template files', () {
    test('template → XMP → template round-trips values', () {
      const template = IptcTemplate(
        fields: {
          IptcField.caption: '{year} Cup final',
          IptcField.creator: 'Niels Franke',
          IptcField.credit: 'AP',
          IptcField.city: 'Bremen',
          IptcField.subjectCodes: 'medtop:15000000',
        },
        keywords: ['sport', 'bremen'],
        locationsShown: [
          IptcLocation(city: 'Bremen', country: 'Germany'),
        ],
        licensors: [IptcLicensor(name: 'Agency', email: 'a@b.c')],
      );

      final out = templateFromXmpSource(templateToXmpSource(template));

      expect(out.fields, template.fields);
      expect(out.keywords, template.keywords);
      expect(out.keywordMode, KeywordApplyMode.replace);
      expect(
        [for (final l in out.locationsShown) l.toJson()],
        [for (final l in template.locationsShown) l.toJson()],
      );
      expect(
        [for (final l in out.licensors) l.toJson()],
        [for (final l in template.licensors) l.toJson()],
      );
    });

    test('a template without keywords stays keyword-neutral through XMP', () {
      const template = IptcTemplate(fields: {IptcField.credit: 'AP'});
      final out = templateFromXmpSource(templateToXmpSource(template));
      expect(out.keywords, isNull);
    });

    test('the XMP carries no cull marks', () {
      const template = IptcTemplate(fields: {IptcField.credit: 'AP'});
      final xml = templateToXmpSource(template);
      expect(xml, isNot(contains('xmp:Rating')));
      expect(xml, isNot(contains('cullimingo:flag')));
    });

    test('reads a Photo Mechanic / Bridge style element-form template', () {
      // The shape PM's "Save…" and Bridge's metadata templates produce:
      // attribute-form photoshop:* plus element-form dc:* alt/seq/bag.
      const source = '''
<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/"
    xmlns:dc="http://purl.org/dc/elements/1.1/"
    photoshop:Credit="AP"
    photoshop:City="Bremen"
    photoshop:DateCreated="2026-05-01T10:00:00">
   <dc:description>
    <rdf:Alt><rdf:li xml:lang="x-default">Match report</rdf:li></rdf:Alt>
   </dc:description>
   <dc:creator>
    <rdf:Seq><rdf:li>Niels Franke</rdf:li></rdf:Seq>
   </dc:creator>
   <dc:subject>
    <rdf:Bag><rdf:li>sport</rdf:li><rdf:li>bremen</rdf:li></rdf:Bag>
   </dc:subject>
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>
''';
      final template = templateFromXmpSource(source);
      expect(template.fields[IptcField.caption], 'Match report');
      expect(template.fields[IptcField.creator], 'Niels Franke');
      expect(template.fields[IptcField.credit], 'AP');
      expect(template.fields[IptcField.city], 'Bremen');
      expect(template.fields.containsKey(IptcField.dateCreated), isFalse);
      expect(template.keywords, ['sport', 'bremen']);
    });

    test('Photo Mechanic {variables} arrive translated to our tokens', () {
      // A PM stationery pad saved with variables in its values: they must
      // load as our tokens so apply-time expansion works, not stamp literals.
      const source = '''
<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/"
    xmlns:dc="http://purl.org/dc/elements/1.1/"
    photoshop:TransmissionReference="{fbas}"
    photoshop:Instructions="File {filename} at {time}">
   <dc:description>
    <rdf:Alt><rdf:li xml:lang="x-default">{datesort} on {model}</rdf:li></rdf:Alt>
   </dc:description>
   <dc:rights>
    <rdf:Alt><rdf:li xml:lang="x-default">© {year4} Niels</rdf:li></rdf:Alt>
   </dc:rights>
   <dc:subject>
    <rdf:Bag><rdf:li>{lenstype}</rdf:li></rdf:Bag>
   </dc:subject>
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>
''';
      final template = templateFromXmpSource(source);
      expect(
        template.fields[IptcField.caption],
        '{year}{month}{day} on {camera}',
      );
      expect(template.fields[IptcField.copyright], '© {year} Niels');
      expect(template.fields[IptcField.jobId], '{name}');
      // Same-named variables ({filename}, {time}) pass through; unknown PM
      // names would too. Keywords are translated like any other value.
      expect(
        template.fields[IptcField.instructions],
        'File {filename} at {time}',
      );
      expect(template.keywords, ['{lens}']);
    });

    test('malformed XML throws a FormatException from the pure codec', () {
      expect(() => templateFromXmpSource('not xml'), throwsFormatException);
    });

    test('file problems surface as user-presentable messages', () async {
      // Missing file → "could not be opened".
      await expectLater(
        readTemplateXmpFile('/nonexistent/template.xmp'),
        throwsA(
          isA<TemplateFileException>().having(
            (e) => e.message,
            'message',
            contains('could not be opened'),
          ),
        ),
      );

      final dir = await Directory.systemTemp.createTemp('cullimingo_tpl');
      addTearDown(() => dir.delete(recursive: true));

      // Garbage content → "not an XMP template".
      final garbage = '${dir.path}/garbage.xmp';
      File(garbage).writeAsStringSync('this is not xml');
      await expectLater(
        readTemplateXmpFile(garbage),
        throwsA(
          isA<TemplateFileException>().having(
            (e) => e.message,
            'message',
            contains('not an XMP template'),
          ),
        ),
      );

      // Valid XMP with no IPTC values → "no template fields" (loading it
      // would only clear the form).
      final empty = '${dir.path}/empty.xmp';
      File(empty).writeAsStringSync('''
<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/"
    xmp:Rating="3"/>
 </rdf:RDF>
</x:xmpmeta>
''');
      await expectLater(
        readTemplateXmpFile(empty),
        throwsA(
          isA<TemplateFileException>().having(
            (e) => e.message,
            'message',
            contains('no template fields'),
          ),
        ),
      );
    });

    test('file round-trip via read/write helpers', () async {
      final dir = await Directory.systemTemp.createTemp('cullimingo_tpl');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/template.xmp';
      const template = IptcTemplate(
        fields: {IptcField.caption: 'Hello', IptcField.credit: 'AP'},
        keywords: ['a'],
      );
      await writeTemplateXmpFile(path, template);
      final out = await readTemplateXmpFile(path);
      expect(out.fields, template.fields);
      expect(out.keywords, template.keywords);
    });
  });
}
