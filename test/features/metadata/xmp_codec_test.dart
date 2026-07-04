import 'package:cullimingo/features/metadata/data/xmp_codec.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/features/metadata/domain/iptc_structured.dart';
import 'package:cullimingo/features/metadata/domain/xmp_data.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('encodeXmp', () {
    test('emits the fields C1/LR read, plus the private flag', () {
      final xml = encodeXmp(
        const XmpData(
          rating: 4,
          color: ColorLabel.blue,
          flag: PickFlag.pick,
          keywords: ['portrait', 'beach'],
        ),
      );

      expect(xml, contains('xmp:Rating="4"'));
      expect(xml, contains('xmp:Label="Blue"'));
      expect(xml, contains('cullimingo:flag="pick"'));
      expect(xml, contains('<rdf:li>portrait</rdf:li>'));
      expect(xml, contains('<rdf:li>beach</rdf:li>'));
    });

    test('omits unset fields (rating 0, no label, no flag, no keywords)', () {
      final xml = encodeXmp(const XmpData());
      expect(xml, isNot(contains('xmp:Rating')));
      expect(xml, isNot(contains('xmp:Label')));
      expect(xml, isNot(contains('cullimingo:flag')));
      expect(xml, isNot(contains('dc:subject')));
    });

    test('escapes keyword text', () {
      final xml = encodeXmp(const XmpData(keywords: ['a & b <c>']));
      expect(xml, contains('<rdf:li>a &amp; b &lt;c&gt;</rdf:li>'));
    });

    test('writes photoshop:DateCreated as naive local ISO 8601', () {
      final xml = encodeXmp(
        XmpData(dateCreated: DateTime(2026, 7, 2, 9, 5, 3)),
      );
      expect(xml, contains('photoshop:DateCreated="2026-07-02T09:05:03"'));
    });

    test('omits DateCreated when null', () {
      expect(encodeXmp(const XmpData()), isNot(contains('DateCreated')));
    });

    test('writes tiff:Orientation only for a non-normal orientation', () {
      expect(
        encodeXmp(const XmpData(orientation: 6)),
        contains('tiff:Orientation="6"'),
      );
      // Normal (1) and null stay silent so untouched sidecars don't change.
      expect(
        encodeXmp(const XmpData(orientation: 1)),
        isNot(contains('tiff:Orientation')),
      );
      expect(encodeXmp(const XmpData()), isNot(contains('tiff:Orientation')));
    });
  });

  group('decodeXmp', () {
    test('round-trips through encode', () {
      const data = XmpData(
        rating: 3,
        color: ColorLabel.green,
        flag: PickFlag.reject,
        keywords: ['x', 'y'],
      );
      final back = decodeXmp(encodeXmp(data));

      expect(back.rating, 3);
      expect(back.color, ColorLabel.green);
      expect(back.flag, PickFlag.reject);
      expect(back.keywords, ['x', 'y']);
    });

    test('round-trips subject codes as an Iptc4xmpCore:SubjectCode bag', () {
      const data = XmpData(
        iptc: IptcCore(subjectCodes: 'medtop:20001065, medtop:15000000'),
      );
      final xml = encodeXmp(data);
      expect(xml, contains('<Iptc4xmpCore:SubjectCode>'));
      expect(xml, contains('<rdf:li>medtop:20001065</rdf:li>'));
      expect(xml, contains('<rdf:li>medtop:15000000</rdf:li>'));
      expect(
        decodeXmp(xml).iptc.subjectCodes,
        'medtop:20001065, medtop:15000000',
      );
      // Absent stays absent.
      expect(encodeXmp(const XmpData()), isNot(contains('SubjectCode')));
    });

    test('round-trips DateCreated', () {
      final data = XmpData(dateCreated: DateTime(2026, 7, 2, 9, 5, 3));
      expect(decodeXmp(encodeXmp(data)).dateCreated, data.dateCreated);
      expect(decodeXmp(encodeXmp(const XmpData())).dateCreated, isNull);
    });

    test('round-trips tiff:Orientation', () {
      expect(
        decodeXmp(encodeXmp(const XmpData(orientation: 8))).orientation,
        8,
      );
      expect(decodeXmp(encodeXmp(const XmpData())).orientation, isNull);
    });

    test('reads a Lightroom crs: crop', () {
      const lr = '''
<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
    crs:HasCrop="True" crs:CropTop="0.1" crs:CropLeft="0.05"
    crs:CropBottom="0.9" crs:CropRight="0.95" crs:CropAngle="2"/>
 </rdf:RDF>
</x:xmpmeta>''';
      final crop = decodeXmp(lr).crop;
      expect(crop, isNotNull);
      expect(crop!.left, closeTo(0.05, 1e-9));
      expect(crop.right, closeTo(0.95, 1e-9));
      expect(crop.width, closeTo(0.9, 1e-9));
      expect(crop.angle, closeTo(2, 1e-9));
      expect(crop.isMeaningful, isTrue);
    });

    test('no crop without crs:HasCrop', () {
      expect(decodeXmp(encodeXmp(const XmpData())).crop, isNull);
      const notCropped = '''
<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
    crs:HasCrop="False"/>
 </rdf:RDF>
</x:xmpmeta>''';
      expect(decodeXmp(notCropped).crop, isNull);
    });

    test('no crop when crs:AlreadyApplied — pixels are already cropped', () {
      // A Lightroom-exported JPEG carries the develop record (HasCrop + the
      // crop rect relative to the *original*) but its pixels are already
      // cropped; AlreadyApplied="True" flags that, so we don't re-overlay it.
      const exported = '''
<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
    crs:HasCrop="True" crs:CropTop="0.11" crs:CropLeft="0"
    crs:CropBottom="0.93" crs:CropRight="0.82" crs:CropAngle="0"
    crs:AlreadyApplied="True"/>
 </rdf:RDF>
</x:xmpmeta>''';
      expect(decodeXmp(exported).crop, isNull);
    });

    test('reads a Lightroom-style sidecar', () {
      const lr = '''
<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:xmp="http://ns.adobe.com/xap/1.0/"
    xmlns:dc="http://purl.org/dc/elements/1.1/"
    xmp:Rating="5" xmp:Label="Red">
   <dc:subject><rdf:Bag><rdf:li>sunset</rdf:li></rdf:Bag></dc:subject>
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>''';

      final data = decodeXmp(lr);
      expect(data.rating, 5);
      expect(data.color, ColorLabel.red);
      expect(data.keywords, ['sunset']);
      expect(data.flag, PickFlag.none);
    });

    test('defaults for an empty/odd packet', () {
      final data = decodeXmp('<x:xmpmeta xmlns:x="adobe:ns:meta/"/>');
      expect(data.rating, 0);
      expect(data.color, ColorLabel.none);
      expect(data.flag, PickFlag.none);
      expect(data.keywords, isEmpty);
      expect(data.iptc.isEmpty, isTrue);
    });
  });

  group('IPTC Core', () {
    const captioned = XmpData(
      keywords: ['news'],
      iptc: IptcCore(
        caption: 'A protester waves a flag.',
        headline: 'March downtown',
        creator: 'Jane Doe',
        authorTitle: 'Staff Photographer',
        copyright: '© 2026 Jane Doe',
        credit: 'AP',
        source: 'Associated Press',
        instructions: 'Editorial use only',
        location: 'Marienplatz',
        city: 'Munich',
        state: 'Bavaria',
        country: 'Germany',
        countryCode: 'DE',
        altText: 'A person holding a large flag above a crowd.',
      ),
    );

    test(
      'encodes plain fields as attributes and structured ones as elements',
      () {
        final xml = encodeXmp(captioned);
        // plain -> attributes
        expect(xml, contains('photoshop:Headline="March downtown"'));
        expect(xml, contains('photoshop:Credit="AP"'));
        expect(xml, contains('photoshop:City="Munich"'));
        expect(xml, contains('Iptc4xmpCore:CountryCode="DE"'));
        // language-alternatives -> rdf:Alt
        expect(xml, contains('<dc:description>'));
        expect(xml, contains('xml:lang="x-default">A protester waves a flag.'));
        expect(xml, contains('<Iptc4xmpCore:AltTextAccessibility>'));
        // creator -> rdf:Seq
        expect(xml, contains('<dc:creator>'));
        expect(xml, contains('<rdf:Seq>'));
      },
    );

    test('round-trips every field through encode', () {
      final back = decodeXmp(encodeXmp(captioned)).iptc;
      expect(back.caption, 'A protester waves a flag.');
      expect(back.headline, 'March downtown');
      expect(back.creator, 'Jane Doe');
      expect(back.authorTitle, 'Staff Photographer');
      expect(back.copyright, '© 2026 Jane Doe');
      expect(back.credit, 'AP');
      expect(back.source, 'Associated Press');
      expect(back.instructions, 'Editorial use only');
      expect(back.location, 'Marienplatz');
      expect(back.city, 'Munich');
      expect(back.state, 'Bavaria');
      expect(back.country, 'Germany');
      expect(back.countryCode, 'DE');
      expect(back.altText, 'A person holding a large flag above a crowd.');
    });

    test('round-trips the rights / contact / wire fields', () {
      const data = XmpData(
        iptc: IptcCore(
          title: 'SCB-FCZ story',
          creatorEmail: 'hello@example.com',
          creatorWebsite: 'example.com',
          copyrightStatus: 'copyrighted',
          usageTerms: 'Editorial use only. Credit required.',
          webStatement: 'https://example.com/rights',
          jobId: 'SCB-FCZ-20260308',
        ),
      );
      final xml = encodeXmp(data);
      // Marked boolean + wire attribute.
      expect(xml, contains('xmpRights:Marked="True"'));
      expect(
        xml,
        contains('photoshop:TransmissionReference="SCB-FCZ-20260308"'),
      );
      expect(xml, contains('xmpRights:WebStatement='));
      // Nested contact block.
      expect(xml, contains('<Iptc4xmpCore:CreatorContactInfo'));
      expect(xml, contains('hello@example.com'));

      final back = decodeXmp(xml).iptc;
      expect(back.title, 'SCB-FCZ story');
      expect(back.creatorEmail, 'hello@example.com');
      expect(back.creatorWebsite, 'example.com');
      expect(back.copyrightStatus, 'copyrighted');
      expect(back.usageTerms, 'Editorial use only. Credit required.');
      expect(back.webStatement, 'https://example.com/rights');
      expect(back.jobId, 'SCB-FCZ-20260308');
    });

    test('round-trips the creator contact block, model + date fields', () {
      const data = XmpData(
        iptc: IptcCore(
          creatorAddress: '1 Wire St',
          creatorCity: 'Munich',
          creatorRegion: 'Bavaria',
          creatorPostalCode: '80331',
          creatorCountry: 'Germany',
          creatorPhone: '+49 89 000000',
          additionalModelInfo: 'Wearing team kit',
          modelAge: '24, 27',
          dateCreated: '2026-06-25T10:01:26',
        ),
      );
      final xml = encodeXmp(data);
      expect(xml, contains('<Iptc4xmpCore:CiAdrCity>Munich'));
      expect(xml, contains('<Iptc4xmpCore:CiTelWork>+49 89 000000'));
      expect(xml, contains('Iptc4xmpExt:AddlModelInfo="Wearing team kit"'));
      expect(xml, contains('<Iptc4xmpExt:ModelAge>'));
      // The editable Date Created is written even with no XmpData.dateCreated.
      expect(xml, contains('photoshop:DateCreated="2026-06-25T10:01:26"'));

      final back = decodeXmp(xml).iptc;
      expect(back.creatorAddress, '1 Wire St');
      expect(back.creatorCity, 'Munich');
      expect(back.creatorRegion, 'Bavaria');
      expect(back.creatorPostalCode, '80331');
      expect(back.creatorCountry, 'Germany');
      expect(back.creatorPhone, '+49 89 000000');
      expect(back.additionalModelInfo, 'Wearing team kit');
      expect(back.modelAge, '24, 27');
      expect(back.dateCreated, '2026-06-25T10:01:26');
    });

    test('round-trips the supplier / GUID / minor-age fields', () {
      const data = XmpData(
        iptc: IptcCore(
          imageSupplierName: 'Cullimingo Wire',
          imageSupplierId: 'CW-01',
          imageSupplierImageId: 'IMG-9912',
          minorModelAgeDisclosure: 'Age 25 or over',
          digImageGuid: 'urn:uuid:1234',
        ),
      );
      final xml = encodeXmp(data);
      expect(xml, contains('<plus:ImageSupplierName>Cullimingo Wire'));
      expect(xml, contains('<plus:ImageSupplierID>CW-01'));
      expect(xml, contains('plus:ImageSupplierImageID="IMG-9912"'));
      expect(
        xml,
        contains('plus:MinorModelAgeDisclosure="Age 25 or over"'),
      );
      expect(xml, contains('Iptc4xmpExt:DigImageGUID="urn:uuid:1234"'));

      final back = decodeXmp(xml).iptc;
      expect(back.imageSupplierName, 'Cullimingo Wire');
      expect(back.imageSupplierId, 'CW-01');
      expect(back.imageSupplierImageId, 'IMG-9912');
      expect(back.minorModelAgeDisclosure, 'Age 25 or over');
      expect(back.digImageGuid, 'urn:uuid:1234');
    });

    test('round-trips the licensor and registry tables', () {
      const data = XmpData(
        iptc: IptcCore(
          licensors: [
            IptcLicensor(
              name: 'Cullimingo Wire',
              id: 'CW-01',
              phone: '+49 89 000000',
              email: 'license@cullimingo.app',
              url: 'https://cullimingo.app',
            ),
          ],
          registryEntries: [
            IptcRegistryEntry(itemId: 'IMG-42', organisationId: 'urn:org:cw'),
          ],
        ),
      );
      final xml = encodeXmp(data);
      expect(xml, contains('<plus:Licensor>'));
      expect(xml, contains('<plus:LicensorEmail>license@cullimingo.app'));
      expect(xml, contains('<Iptc4xmpExt:RegistryId>'));
      expect(xml, contains('<Iptc4xmpExt:RegItemId>IMG-42'));

      final back = decodeXmp(xml).iptc;
      expect(back.licensors.single.name, 'Cullimingo Wire');
      expect(back.licensors.single.email, 'license@cullimingo.app');
      expect(back.licensors.single.url, 'https://cullimingo.app');
      expect(back.registryEntries.single.itemId, 'IMG-42');
      expect(back.registryEntries.single.organisationId, 'urn:org:cw');
    });

    test('editable Date Created wins over the EXIF capture time', () {
      final xml = encodeXmp(
        XmpData(
          dateCreated: DateTime(2020), // EXIF capture time
          iptc: const IptcCore(dateCreated: '2026-06-25T10:01:26'),
        ),
      );
      expect(xml, contains('photoshop:DateCreated="2026-06-25T10:01:26"'));
      expect(xml, isNot(contains('2020')));
    });

    test('empty Date Created falls back to the capture time', () {
      final xml = encodeXmp(
        XmpData(dateCreated: DateTime(2026, 7, 2, 9, 5, 3)),
      );
      expect(xml, contains('photoshop:DateCreated="2026-07-02T09:05:03"'));
    });

    test('copyright status maps to xmpRights:Marked both ways', () {
      String marked(String status) =>
          encodeXmp(XmpData(iptc: IptcCore(copyrightStatus: status)));
      expect(marked('copyrighted'), contains('Marked="True"'));
      expect(marked('public domain'), contains('Marked="False"'));
      // "unknown" asserts nothing.
      expect(marked('unknown'), isNot(contains('Marked=')));

      expect(
        decodeXmp(marked('public domain')).iptc.copyrightStatus,
        'public domain',
      );
    });

    test('round-trips the AI / provenance fields (2025.1)', () {
      const data = XmpData(
        iptc: IptcCore(
          digitalSourceType: 'ai-generated',
          aiSystemUsed: 'DALL-E',
          aiSystemVersion: '3',
          aiPromptInfo: 'a flamingo culling photos',
          aiPromptWriter: 'Niels Franke',
        ),
      );
      final xml = encodeXmp(data);
      // Friendly value expands to the IPTC controlled-vocabulary URI.
      expect(
        xml,
        contains(
          'Iptc4xmpExt:DigitalSourceType='
          '"http://cv.iptc.org/newscodes/digitalsourcetype/'
          'trainedAlgorithmicMedia"',
        ),
      );
      expect(xml, contains('Iptc4xmpExt:AISystemUsed="DALL-E"'));
      expect(xml, contains('xmlns:Iptc4xmpExt='));

      final back = decodeXmp(xml).iptc;
      expect(back.digitalSourceType, 'ai-generated'); // URI mapped back
      expect(back.aiSystemUsed, 'DALL-E');
      expect(back.aiSystemVersion, '3');
      expect(back.aiPromptInfo, 'a flamingo culling photos');
      expect(back.aiPromptWriter, 'Niels Franke');
    });

    test(
      'round-trips the extended description / status fields (PM parity)',
      () {
        const data = XmpData(
          iptc: IptcCore(
            descriptionWriters: 'Sam Editor',
            personsShown: 'Alice, Bob',
            featuredOrgName: 'FC Bayern, DFB',
            featuredOrgCode: 'FCB',
            intellectualGenre: 'Actuality',
            iptcScene: '011900, 012600',
            event: 'Bundesliga matchday 26',
            category: 'SPO',
            supplementalCategories: 'Soccer, Bundesliga',
            urgency: '2',
            editStatus: 'Final',
          ),
        );
        final xml = encodeXmp(data);
        // Simple attributes.
        expect(xml, contains('photoshop:CaptionWriter="Sam Editor"'));
        expect(xml, contains('Iptc4xmpCore:IntellectualGenre="Actuality"'));
        expect(xml, contains('photoshop:Category="SPO"'));
        expect(xml, contains('photoshop:Urgency="2"'));
        expect(xml, contains('cullimingo:EditStatus="Final"'));
        // Bags.
        expect(xml, contains('<Iptc4xmpExt:PersonInImage>'));
        expect(xml, contains('<rdf:li>Alice</rdf:li>'));
        expect(xml, contains('<Iptc4xmpExt:OrganisationInImageName>'));
        expect(xml, contains('<Iptc4xmpCore:Scene>'));
        expect(xml, contains('<photoshop:SupplementalCategories>'));
        // Language-alternative.
        expect(xml, contains('<Iptc4xmpExt:Event>'));

        final back = decodeXmp(xml).iptc;
        expect(back.descriptionWriters, 'Sam Editor');
        expect(back.personsShown, 'Alice, Bob');
        expect(back.featuredOrgName, 'FC Bayern, DFB');
        expect(back.featuredOrgCode, 'FCB');
        expect(back.intellectualGenre, 'Actuality');
        expect(back.iptcScene, '011900, 012600');
        expect(back.event, 'Bundesliga matchday 26');
        expect(back.category, 'SPO');
        expect(back.supplementalCategories, 'Soccer, Bundesliga');
        expect(back.urgency, '2');
        expect(back.editStatus, 'Final');
      },
    );

    test('round-trips World Region / Location ID via LocationCreated', () {
      const data = XmpData(
        iptc: IptcCore(
          city: 'Lillehammer',
          country: 'Norway',
          worldRegion: 'Europe',
          locationId: 'GEO-123',
        ),
      );
      final xml = encodeXmp(data);
      expect(xml, contains('<Iptc4xmpExt:LocationCreated'));
      expect(xml, contains('<Iptc4xmpExt:WorldRegion>Europe'));
      expect(xml, contains('<Iptc4xmpExt:LocationId>'));
      expect(xml, contains('<rdf:li>GEO-123</rdf:li>'));

      final back = decodeXmp(xml).iptc;
      expect(back.worldRegion, 'Europe');
      expect(back.locationId, 'GEO-123');
      // Absent when neither is set.
      expect(
        encodeXmp(const XmpData(iptc: IptcCore(city: 'X'))),
        isNot(contains('LocationCreated')),
      );
    });

    test('round-trips the model/property release fields (PLUS)', () {
      const data = XmpData(
        iptc: IptcCore(
          modelReleaseStatus: 'Limited model releases',
          modelReleaseIds: 'MR-1, MR-2',
          propertyReleaseStatus: 'Not applicable',
          propertyReleaseIds: 'PR-9',
        ),
      );
      final xml = encodeXmp(data);
      expect(xml, contains('xmlns:plus='));
      expect(
        xml,
        contains('plus:ModelReleaseStatus="Limited model releases"'),
      );
      expect(xml, contains('<plus:ModelReleaseID>'));
      expect(xml, contains('<rdf:li>MR-1</rdf:li>'));

      final back = decodeXmp(xml).iptc;
      expect(back.modelReleaseStatus, 'Limited model releases');
      expect(back.modelReleaseIds, 'MR-1, MR-2');
      expect(back.propertyReleaseStatus, 'Not applicable');
      expect(back.propertyReleaseIds, 'PR-9');
    });

    test('a raw digital-source URI passes through unchanged', () {
      const uri =
          'http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture';
      final back = decodeXmp(
        encodeXmp(const XmpData(iptc: IptcCore(digitalSourceType: uri))),
      ).iptc;
      expect(back.digitalSourceType, 'photo'); // canonical URI → friendly label
    });

    test('escapes special characters in caption and credit', () {
      const data = XmpData(
        iptc: IptcCore(caption: 'a & b <c>', credit: 'AP "wire"'),
      );
      final back = decodeXmp(encodeXmp(data)).iptc;
      expect(back.caption, 'a & b <c>');
      expect(back.credit, 'AP "wire"');
    });

    test('emits no IPTC content when the payload is empty', () {
      final xml = encodeXmp(const XmpData(rating: 2));
      expect(xml, isNot(contains('dc:description')));
      expect(xml, isNot(contains('dc:creator')));
      expect(xml, isNot(contains('photoshop:Headline')));
    });

    test('reads Lightroom element-form fields (not just our attributes)', () {
      const lr = '''
<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:dc="http://purl.org/dc/elements/1.1/"
    xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/">
   <dc:description><rdf:Alt><rdf:li xml:lang="x-default">Hello caption</rdf:li></rdf:Alt></dc:description>
   <dc:creator><rdf:Seq><rdf:li>Ansel Adams</rdf:li></rdf:Seq></dc:creator>
   <photoshop:City>Yosemite</photoshop:City>
   <photoshop:Credit>National Park Service</photoshop:Credit>
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>''';

      final iptc = decodeXmp(lr).iptc;
      expect(iptc.caption, 'Hello caption');
      expect(iptc.creator, 'Ansel Adams');
      expect(iptc.city, 'Yosemite');
      expect(iptc.credit, 'National Park Service');
    });

    test('keyword extraction is not confused by creator/description li', () {
      final xml = encodeXmp(captioned);
      // captioned has one keyword ("news") plus a creator Seq li and a
      // description Alt li — only the subject bag should count as keywords.
      expect(decodeXmp(xml).keywords, ['news']);
    });

    test('a LocationShown-only city never leaks into the flat City', () {
      // A payload whose ONLY location data is a LocationShown row: reading it
      // back must not invent a flat city (the element fallback used to grab
      // the struct's City). LocationCreated stays a valid flat fallback.
      final xml = encodeXmp(
        const XmpData(
          iptc: IptcCore(
            locationsShown: [IptcLocation(city: 'Bremen', countryCode: 'DE')],
          ),
        ),
      );
      final iptc = decodeXmp(xml).iptc;
      expect(iptc.city, isEmpty);
      expect(iptc.countryCode, isEmpty);
      expect(iptc.locationsShown.single.city, 'Bremen');
    });
  });
}
