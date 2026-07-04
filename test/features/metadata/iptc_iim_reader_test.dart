import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cullimingo/features/metadata/data/iptc_iim.dart';
import 'package:cullimingo/features/metadata/data/iptc_iim_reader.dart';
import 'package:cullimingo/features/metadata/data/marks_reader.dart';
import 'package:cullimingo/features/metadata/data/xmp_codec.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/features/metadata/domain/xmp_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  // A minimal JPEG SOI/EOI so `embedIptcIimInJpeg` splices its segment in.
  final jpegStub = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

  group('decodeIptcIim', () {
    test('round-trips the classic editorial fields written by the writer', () {
      const source = XmpData(
        keywords: ['Berlin', 'Protest'],
        iptc: IptcCore(
          caption: 'Members of parliament during the session.',
          headline: 'Chancellor addresses parliament',
          title: 'bundestag-session',
          creator: 'Jane Doe',
          authorTitle: 'Staff Photographer',
          credit: 'Cullimingo Wire',
          source: 'Cullimingo News',
          copyright: '(c) 2026 Jane Doe',
          instructions: 'Embargoed until 18:00',
          location: 'Reichstag',
          city: 'Berlin',
          state: 'Berlin',
          country: 'Germany',
          countryCode: 'DE',
          jobId: 'WIRE-42',
        ),
      );

      final jpeg = embedIptcIimInJpeg(jpegStub, source);
      final out = decodeIptcIim(jpeg);

      expect(out, isNotNull);
      expect(out!.keywords, ['Berlin', 'Protest']);
      final iptc = out.iptc;
      expect(iptc.caption, 'Members of parliament during the session.');
      expect(iptc.headline, 'Chancellor addresses parliament');
      expect(iptc.title, 'bundestag-session');
      expect(iptc.creator, 'Jane Doe');
      expect(iptc.authorTitle, 'Staff Photographer');
      expect(iptc.credit, 'Cullimingo Wire');
      expect(iptc.source, 'Cullimingo News');
      expect(iptc.copyright, '(c) 2026 Jane Doe');
      expect(iptc.instructions, 'Embargoed until 18:00');
      expect(iptc.location, 'Reichstag');
      expect(iptc.city, 'Berlin');
      expect(iptc.state, 'Berlin');
      expect(iptc.country, 'Germany');
      expect(iptc.countryCode, 'DE');
      expect(iptc.jobId, 'WIRE-42');
    });

    test(
      'round-trips the status fields, incl. repeatable supp. categories',
      () {
        const source = XmpData(
          iptc: IptcCore(
            editStatus: 'Final',
            urgency: '2',
            category: 'SPO',
            supplementalCategories: 'Soccer, Bundesliga',
            descriptionWriters: 'Sam Editor',
          ),
        );

        final jpeg = embedIptcIimInJpeg(jpegStub, source);
        final iptc = decodeIptcIim(jpeg)!.iptc;
        expect(iptc.editStatus, 'Final');
        expect(iptc.urgency, '2');
        expect(iptc.category, 'SPO');
        expect(iptc.supplementalCategories, 'Soccer, Bundesliga');
        expect(iptc.descriptionWriters, 'Sam Editor');
      },
    );

    test('decodes UTF-8 accented text via the coded-charset marker', () {
      const source = XmpData(
        iptc: IptcCore(
          caption: 'Manifestación en Málaga — Über',
          city: 'Zürich',
        ),
      );
      final jpeg = embedIptcIimInJpeg(jpegStub, source);
      final out = decodeIptcIim(jpeg);
      expect(out!.iptc.caption, 'Manifestación en Málaga — Über');
      expect(out.iptc.city, 'Zürich');
    });

    test('reconstructs Date Created from 2:55 / 2:60', () {
      final source = XmpData(
        iptc: const IptcCore(caption: 'x'),
        dateCreated: DateTime(2026, 6, 11, 15, 1, 30),
      );
      final jpeg = embedIptcIimInJpeg(jpegStub, source);
      final out = decodeIptcIim(jpeg);
      expect(out!.dateCreated, DateTime(2026, 6, 11, 15, 1, 30));
    });

    test('returns null when there is no IPTC resource', () {
      expect(decodeIptcIim(jpegStub), isNull);
      expect(
        decodeIptcIim(Uint8List.fromList(utf8.encode('no iptc here'))),
        isNull,
      );
    });
  });

  group('readEmbeddedIim', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('cm_iim_reader');
    });
    tearDown(() => dir.delete(recursive: true));

    test('reads the IIM block from a real file', () async {
      final jpeg = embedIptcIimInJpeg(
        jpegStub,
        const XmpData(
          keywords: ['a', 'b'],
          iptc: IptcCore(caption: 'hello world'),
        ),
      );
      final file = File(p.join(dir.path, 'iim.jpg'));
      await file.writeAsBytes(jpeg);

      final data = await readEmbeddedIim(file.path);
      expect(data!.iptc.caption, 'hello world');
      expect(data.keywords, ['a', 'b']);
    });
  });

  group('readMarks IIM fallback', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('cm_marks_iim');
    });
    tearDown(() => dir.delete(recursive: true));

    test('reads IIM when there is no sidecar and no XMP packet', () async {
      final jpeg = embedIptcIimInJpeg(
        jpegStub,
        const XmpData(
          keywords: ['breaking'],
          iptc: IptcCore(caption: 'Test caption'),
        ),
      );
      final file = File(p.join(dir.path, 'photo.jpg'));
      await file.writeAsBytes(jpeg);

      final data = await readMarks(file.path);
      expect(data, isNotNull);
      expect(data!.iptc.caption, 'Test caption');
      expect(data.keywords, ['breaking']);
    });

    test('prefers embedded XMP over IIM when both are present', () async {
      // Photo-Mechanic-style: both blocks present, XMP is authoritative.
      var jpeg = embedIptcIimInJpeg(
        jpegStub,
        const XmpData(iptc: IptcCore(caption: 'from IIM')),
      );
      final packet = encodeXmp(
        const XmpData(rating: 5, iptc: IptcCore(caption: 'from XMP')),
      );
      jpeg = Uint8List.fromList([...jpeg, ...utf8.encode(packet)]);
      final file = File(p.join(dir.path, 'both.jpg'));
      await file.writeAsBytes(jpeg);

      final data = await readMarks(file.path);
      expect(data!.rating, 5);
      expect(data.iptc.caption, 'from XMP');
    });
  });
}
