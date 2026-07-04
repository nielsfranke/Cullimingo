import 'dart:isolate';

import 'package:cullimingo/features/metadata/data/gazetteer_geocoder.dart';
import 'package:cullimingo/features/metadata/domain/media_topics.dart';
import 'package:cullimingo/features/metadata/domain/reverse_geocoder.dart';
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'geocoding_providers.g.dart';

/// The app's reverse geocoder: the bundled GeoNames gazetteer, loaded once and
/// kept alive. The asset read happens here (rootBundle needs the main
/// isolate); the ~8 MB gunzip + parse runs on a background isolate and the
/// result moves back without copying (`Isolate.run` → `Isolate.exit`).
@Riverpod(keepAlive: true)
Future<ReverseGeocoder> reverseGeocoder(Ref ref) async {
  final data = await rootBundle.load('assets/geo/cities.tsv.gz');
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  return Isolate.run(() => GazetteerGeocoder.fromGzippedTsv(bytes));
}

/// The bundled IPTC Media Topics vocabulary for the Subject-codes
/// autocomplete, loaded once and kept alive. Parsed inline — the asset is
/// ~10 KB / 1100 lines, far below isolate territory, and `Isolate.run` never
/// completes under a widget test's FakeAsync zone (the M-editor awaits this).
@Riverpod(keepAlive: true)
Future<MediaTopics> mediaTopics(Ref ref) async {
  final data = await rootBundle.load('assets/iptc/mediatopics.tsv.gz');
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  return MediaTopics.fromGzippedTsv(bytes);
}
