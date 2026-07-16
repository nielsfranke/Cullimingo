import 'package:cullimingo/features/metadata/data/xmp_codec.dart';
import 'package:cullimingo/features/metadata/data/xmp_merge.dart';
import 'package:cullimingo/features/metadata/domain/xmp_data.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Lightroom-style sidecar: develop settings + crop (`crs:*`), GPS, and
/// hierarchical keywords — all foreign to Cullimingo — plus an old rating.
const _lightroomSidecar = '''
<?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:xmp="http://ns.adobe.com/xap/1.0/"
    xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
    xmlns:exif="http://ns.adobe.com/exif/1.0/"
    xmlns:lr="http://ns.adobe.com/lightroom/1.0/"
    xmp:Rating="2"
    crs:Version="15.0"
    crs:Exposure2012="+0.55"
    crs:HasCrop="True"
    crs:CropLeft="0.1"
    crs:CropTop="0.1"
    crs:CropRight="0.9"
    crs:CropBottom="0.9"
    exif:GPSLatitude="47,22.56N"
    exif:GPSLongitude="8,32.87E">
   <lr:hierarchicalSubject>
    <rdf:Bag>
     <rdf:li>places|zurich</rdf:li>
    </rdf:Bag>
   </lr:hierarchicalSubject>
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>
<?xpacket end="w"?>''';

/// exiftool-style: one rdf:Description per namespace, marks in element form.
const _exiftoolSidecar = '''
<?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/">
   <xmp:Rating>5</xmp:Rating>
   <xmp:Label>Red</xmp:Label>
  </rdf:Description>
  <rdf:Description rdf:about="" xmlns:aux="http://ns.adobe.com/exif/1.0/aux/">
   <aux:Lens>FE 35mm F1.4 GM</aux:Lens>
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>
<?xpacket end="w"?>''';

void main() {
  group('mergeXmp', () {
    test('preserves foreign properties across a mark write', () {
      final merged = mergeXmp(
        _lightroomSidecar,
        const XmpData(rating: 4, keywords: ['beach']),
      );

      // Foreign tags survive untouched.
      expect(merged, contains('crs:Exposure2012="+0.55"'));
      expect(merged, contains('crs:HasCrop="True"'));
      expect(merged, contains('exif:GPSLatitude="47,22.56N"'));
      expect(merged, contains('places|zurich'));

      // The owned properties carry the new values (old rating replaced).
      final decoded = decodeXmp(merged);
      expect(decoded.rating, 4);
      expect(decoded.keywords, ['beach']);
      expect(merged, isNot(contains('xmp:Rating="2"')));
      // The LR crop still round-trips through the foreign crs attributes.
      expect(decoded.crop, isNotNull);
    });

    test(
      'clearing a mark removes the property instead of keeping the old one',
      () {
        final merged = mergeXmp(_lightroomSidecar, const XmpData());
        final decoded = decodeXmp(merged);
        expect(decoded.rating, 0);
        expect(merged, isNot(contains('xmp:Rating')));
        // Foreign content still there.
        expect(merged, contains('crs:Version="15.0"'));
      },
    );

    test('replaces element-form marks across split descriptions', () {
      final merged = mergeXmp(
        _exiftoolSidecar,
        const XmpData(rating: 3, color: ColorLabel.blue),
      );
      final decoded = decodeXmp(merged);
      expect(decoded.rating, 3);
      expect(decoded.color, ColorLabel.blue);
      // The old element-form values are gone, not merely shadowed.
      expect(merged, isNot(contains('<xmp:Rating>5</xmp:Rating>')));
      expect(merged, isNot(contains('Red')));
      // The foreign aux description survives.
      expect(merged, contains('FE 35mm F1.4 GM'));
    });

    test('re-merging its own output stays stable (no duplication)', () {
      const data = XmpData(rating: 4, flag: PickFlag.pick, keywords: ['a']);
      final once = mergeXmp(_lightroomSidecar, data);
      final twice = mergeXmp(once, data);
      expect(
        'xmp:Rating'.allMatches(twice).length,
        'xmp:Rating'.allMatches(once).length,
      );
      expect(decodeXmp(twice).rating, 4);
      expect(decodeXmp(twice).keywords, ['a']);
      expect(twice, contains('crs:Version="15.0"'));
    });

    test('declares missing namespaces instead of writing unbound prefixes', () {
      // The LR packet has no cullimingo/tiff/dc bindings; a merge that adds a
      // flag + keywords must introduce them (parse would throw otherwise).
      final merged = mergeXmp(
        _lightroomSidecar,
        const XmpData(flag: PickFlag.reject, keywords: ['x'], orientation: 6),
      );
      final decoded = decodeXmp(merged);
      expect(decoded.flag, PickFlag.reject);
      expect(decoded.keywords, ['x']);
      expect(decoded.orientation, 6);
    });

    test('round-trips a fresh packet unchanged in meaning', () {
      const data = XmpData(rating: 1, color: ColorLabel.green);
      final merged = mergeXmp(encodeXmp(data), const XmpData(rating: 5));
      final decoded = decodeXmp(merged);
      expect(decoded.rating, 5);
      expect(decoded.color, ColorLabel.none);
    });

    test('throws on a packet without rdf:Description', () {
      expect(
        () =>
            mergeXmp('<x:xmpmeta xmlns:x="adobe:ns:meta/"/>', const XmpData()),
        throwsFormatException,
      );
    });
  });
}
