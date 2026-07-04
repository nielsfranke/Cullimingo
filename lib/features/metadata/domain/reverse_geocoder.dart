/// A resolved place for a GPS position — the IPTC location fields reverse
/// geocoding can fill (city, state/province, country + ISO code).
class GeoPlace {
  /// Creates a resolved place.
  const GeoPlace({
    required this.city,
    required this.state,
    required this.country,
    required this.countryCode,
  });

  /// Nearest city/town/village name.
  final String city;

  /// State / province (admin1) name; may be empty.
  final String state;

  /// Country name.
  final String country;

  /// ISO 3166-1 alpha-2 country code (e.g. `DE`).
  final String countryCode;
}

/// Resolves a GPS position to a [GeoPlace]. The shipped implementation is the
/// offline GeoNames gazetteer (`GazetteerGeocoder`); the interface keeps an
/// online provider pluggable later without touching the editor wiring.
// ignore: one_member_abstracts — deliberate seam (offline now, online later).
abstract interface class ReverseGeocoder {
  /// The nearest known place, or null when nothing sensible is close enough.
  Future<GeoPlace?> lookup(double latitude, double longitude);
}
