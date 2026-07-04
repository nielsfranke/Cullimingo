import 'package:cullimingo/features/metadata/data/xmp_codec.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/features/metadata/domain/iptc_structured.dart';
import 'package:cullimingo/features/metadata/domain/xmp_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IptcCore structured tables', () {
    const core = IptcCore(
      locationsShown: [
        IptcLocation(city: 'Oslo', country: 'Norway', worldRegion: 'Europe'),
        IptcLocation(sublocation: 'Bryggen', city: 'Bergen'),
      ],
      artwork: [
        IptcArtwork(
          title: 'The Scream',
          creator: 'Edvard Munch',
          source: 'National Museum',
          copyrightNotice: 'Public domain',
        ),
      ],
      imageCreators: [
        IptcEntity(name: 'Jane Doe', identifier: 'https://orcid.org/0000'),
      ],
      copyrightOwners: [IptcEntity(name: 'Cullimingo Wire')],
    );

    test('JSON round-trips the tables and drops blank rows', () {
      final back = IptcCore.fromJson(core.toJson());
      expect(back.locationsShown.length, 2);
      expect(back.locationsShown.first.city, 'Oslo');
      expect(back.locationsShown[1].sublocation, 'Bryggen');
      expect(back.artwork.single.title, 'The Scream');
      expect(back.imageCreators.single.identifier, 'https://orcid.org/0000');
      expect(back.copyrightOwners.single.name, 'Cullimingo Wire');

      // A wholly-blank row is dropped on parse.
      final withBlank = IptcCore.fromJson({
        'copyrightOwners': [
          {'name': 'Real'},
          <String, dynamic>{},
        ],
      });
      expect(withBlank.copyrightOwners.length, 1);
    });

    test('withOverrides preserves the structured tables', () {
      final edited = core.withOverrides({IptcField.headline: 'New'});
      expect(edited.headline, 'New');
      expect(edited.locationsShown.length, 2);
      expect(edited.artwork.single.title, 'The Scream');
    });

    test('empty tables leave isEmpty true', () {
      expect(const IptcCore().isEmpty, isTrue);
      expect(core.isEmpty, isFalse);
    });
  });

  group('XMP struct-array round-trip', () {
    test('round-trips LocationShown, Artwork, and PLUS entities', () {
      const data = XmpData(
        iptc: IptcCore(
          locationsShown: [
            IptcLocation(
              city: 'Oslo',
              state: 'Oslo',
              country: 'Norway',
              countryCode: 'NO',
              worldRegion: 'Europe',
              locationId: 'GEO-1',
            ),
            IptcLocation(sublocation: 'Bryggen', city: 'Bergen'),
          ],
          artwork: [
            IptcArtwork(
              title: 'The Scream',
              creator: 'Edvard Munch',
              source: 'National Museum',
              copyrightNotice: 'Public domain',
            ),
          ],
          imageCreators: [
            IptcEntity(name: 'Jane Doe', identifier: 'orcid:0000'),
          ],
          copyrightOwners: [IptcEntity(name: 'Wire', identifier: 'plus:1')],
        ),
      );

      final xml = encodeXmp(data);
      expect(xml, contains('<Iptc4xmpExt:LocationShown>'));
      expect(xml, contains('<Iptc4xmpExt:ArtworkOrObject>'));
      expect(xml, contains('<plus:ImageCreator>'));
      expect(xml, contains('<plus:CopyrightOwner>'));

      final back = decodeXmp(xml).iptc;
      expect(back.locationsShown.length, 2);
      final first = back.locationsShown.first;
      expect(first.city, 'Oslo');
      expect(first.countryCode, 'NO');
      expect(first.worldRegion, 'Europe');
      expect(first.locationId, 'GEO-1');
      expect(back.locationsShown[1].sublocation, 'Bryggen');

      expect(back.artwork.single.title, 'The Scream');
      expect(back.artwork.single.creator, 'Edvard Munch');
      expect(back.imageCreators.single.name, 'Jane Doe');
      expect(back.imageCreators.single.identifier, 'orcid:0000');
      expect(back.copyrightOwners.single.name, 'Wire');
      expect(back.copyrightOwners.single.identifier, 'plus:1');
    });

    test('a LocationShown WorldRegion never leaks into the flat field', () {
      const data = XmpData(
        iptc: IptcCore(
          locationsShown: [IptcLocation(city: 'X', worldRegion: 'Asia')],
        ),
      );
      final back = decodeXmp(encodeXmp(data)).iptc;
      expect(back.worldRegion, isEmpty); // flat created-location stays empty
      expect(back.locationsShown.single.worldRegion, 'Asia');
    });

    test('empty tables emit nothing', () {
      final xml = encodeXmp(const XmpData(iptc: IptcCore(caption: 'x')));
      expect(xml, isNot(contains('LocationShown')));
      expect(xml, isNot(contains('ArtworkOrObject')));
      expect(xml, isNot(contains('ImageCreator')));
      expect(xml, isNot(contains('CopyrightOwner')));
    });
  });
}
