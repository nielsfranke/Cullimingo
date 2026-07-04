import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cullimingo/features/metadata/domain/reverse_geocoder.dart';

/// Offline reverse geocoder over the bundled GeoNames gazetteer
/// (`assets/geo/cities.tsv.gz`, built by `tool/build_gazetteer.sh`,
/// CC-BY 4.0). Finds the nearest of ~170k places (population ≥ 1000) with a
/// linear scan — a few ms over parallel coordinate arrays, no index needed.
///
/// Construct via [GazetteerGeocoder.fromGzippedTsv] *inside an isolate*
/// (parsing ~8 MB of text is not UI-isolate work); `Isolate.run` moves the
/// result back without copying.
class GazetteerGeocoder implements ReverseGeocoder {
  GazetteerGeocoder._(this._lats, this._lons, this._places);

  /// Parses the gzipped TSV produced by the gazetteer build script
  /// (`lat\tlon\tcity\tstate\tcountry\tcc` per line).
  factory GazetteerGeocoder.fromGzippedTsv(List<int> gzBytes) {
    final lines = const LineSplitter().convert(
      utf8.decode(gzip.decode(gzBytes)),
    );
    final lats = Float64List(lines.length);
    final lons = Float64List(lines.length);
    final places = List<String>.filled(lines.length, '');
    var n = 0;
    for (final line in lines) {
      final tab1 = line.indexOf('\t');
      final tab2 = line.indexOf('\t', tab1 + 1);
      if (tab1 < 0 || tab2 < 0) continue;
      final lat = double.tryParse(line.substring(0, tab1));
      final lon = double.tryParse(line.substring(tab1 + 1, tab2));
      if (lat == null || lon == null) continue;
      lats[n] = lat;
      lons[n] = lon;
      places[n] = line.substring(tab2 + 1);
      n++;
    }
    return GazetteerGeocoder._(
      lats.sublist(0, n),
      lons.sublist(0, n),
      places.sublist(0, n),
    );
  }

  final Float64List _lats;
  final Float64List _lons;

  /// `city\tstate\tcountry\tcc` per row, split lazily on lookup.
  final List<String> _places;

  /// Positions farther than this from every known place return null — the
  /// middle of an ocean shouldn't caption as a coastal town.
  static const double maxDistanceKm = 150;

  /// How many places are loaded.
  int get length => _places.length;

  @override
  Future<GeoPlace?> lookup(double latitude, double longitude) async {
    if (_places.isEmpty) return null;
    // Equirectangular approximation: exact enough for nearest-neighbour at
    // city scale and much cheaper than haversine in the hot loop.
    final cosLat = cos(latitude * pi / 180);
    var best = -1;
    var bestSq = double.infinity;
    for (var i = 0; i < _lats.length; i++) {
      final dLat = _lats[i] - latitude;
      var dLon = (_lons[i] - longitude).abs();
      if (dLon > 180) dLon = 360 - dLon; // shortest way around the date line
      final dx = dLon * cosLat;
      final sq = dLat * dLat + dx * dx;
      if (sq < bestSq) {
        bestSq = sq;
        best = i;
      }
    }
    // Degrees → km (1° of latitude ≈ 111.32 km).
    if (sqrt(bestSq) * 111.32 > maxDistanceKm) return null;
    final parts = _places[best].split('\t');
    if (parts.length < 4) return null;
    return GeoPlace(
      city: parts[0],
      state: parts[1],
      country: parts[2],
      countryCode: parts[3],
    );
  }
}
