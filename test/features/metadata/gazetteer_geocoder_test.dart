import 'dart:convert';
import 'dart:io';

import 'package:cullimingo/features/metadata/data/gazetteer_geocoder.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gzips a small hand-written gazetteer TSV.
List<int> gz(String tsv) => gzip.encode(utf8.encode(tsv));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sample =
      '52.52\t13.405\tBerlin\tBerlin\tGermany\tDE\n'
      '48.8566\t2.3522\tParis\tÎle-de-France\tFrance\tFR\n'
      '-33.8679\t151.2073\tSydney\tNew South Wales\tAustralia\tAU\n';

  test('finds the nearest place and returns its IPTC fields', () async {
    final geo = GazetteerGeocoder.fromGzippedTsv(gz(sample));
    expect(geo.length, 3);

    // A stadium in the north of Berlin: Berlin, not Paris.
    final place = await geo.lookup(52.55, 13.30);
    expect(place!.city, 'Berlin');
    expect(place.state, 'Berlin');
    expect(place.country, 'Germany');
    expect(place.countryCode, 'DE');

    // Southern hemisphere works too.
    final syd = await geo.lookup(-33.9, 151.1);
    expect(syd!.city, 'Sydney');
    expect(syd.countryCode, 'AU');
  });

  test('the middle of an ocean resolves to nothing', () async {
    final geo = GazetteerGeocoder.fromGzippedTsv(gz(sample));
    expect(await geo.lookup(0, -140), isNull); // Pacific
  });

  test('malformed lines are skipped, not fatal', () async {
    final geo = GazetteerGeocoder.fromGzippedTsv(
      gz('garbage line\n$sample\tnot-a-number\tx\ty\n'),
    );
    expect(geo.length, 3);
  });

  test('the bundled asset loads and geocodes real-world positions', () async {
    final data = await rootBundle.load('assets/geo/cities.tsv.gz');
    final geo = GazetteerGeocoder.fromGzippedTsv(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    expect(geo.length, greaterThan(100000));

    // Brandenburg Gate.
    final berlin = await geo.lookup(52.5163, 13.3777);
    expect(berlin!.country, 'Germany');
    expect(berlin.countryCode, 'DE');
    expect(berlin.state, isNotEmpty);

    // Sydney Opera House.
    final sydney = await geo.lookup(-33.8568, 151.2153);
    expect(sydney!.city, 'Sydney');
    expect(sydney.countryCode, 'AU');
  });
}
