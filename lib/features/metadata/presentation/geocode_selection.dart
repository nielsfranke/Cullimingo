import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/filter/presentation/filter_providers.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/features/metadata/presentation/geocoding_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How a batch reverse-geocode run went, for the UI notice: how many photos
/// got location fields, and how many were skipped (no GPS position, or no
/// known place near it).
typedef GeocodeOutcome = ({int filled, int noGps, int noPlace});

/// Reverse-geocodes the current cull targets (the Space-selection if any,
/// else the focused photo) and stamps city / state / country / ISO code onto
/// each photo that has a GPS position — the batch counterpart of the editor's
/// "From GPS" button. Existing location values are overwritten (like a
/// template stamp); untouched photos keep theirs.
Future<GeocodeOutcome> geocodeSelection(WidgetRef ref) async {
  final photos = ref.read(filteredPhotosProvider);
  final byId = {for (final p in photos) p.id: p};
  final targets = ref.read(cullControllerProvider).markTargets;
  final controller = ref.read(cullControllerProvider.notifier);
  final geocoder = await ref.read(reverseGeocoderProvider.future);

  var filled = 0;
  var noGps = 0;
  var noPlace = 0;
  for (final id in targets) {
    final photo = byId[id];
    if (photo == null) continue;
    final (lat, lon) = (photo.latitude, photo.longitude);
    if (lat == null || lon == null) {
      noGps++;
      continue;
    }
    final place = await geocoder.lookup(lat, lon);
    if (place == null) {
      noPlace++;
      continue;
    }
    await controller.setIptc(
      photo.id,
      photo.iptc.withOverrides({
        IptcField.city: place.city,
        IptcField.state: place.state,
        IptcField.country: place.country,
        IptcField.countryCode: place.countryCode,
      }),
    );
    filled++;
  }
  return (filled: filled, noGps: noGps, noPlace: noPlace);
}
