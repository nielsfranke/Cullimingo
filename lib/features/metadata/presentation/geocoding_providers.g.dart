// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'geocoding_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The app's reverse geocoder: the bundled GeoNames gazetteer, loaded once and
/// kept alive. The asset read happens here (rootBundle needs the main
/// isolate); the ~8 MB gunzip + parse runs on a background isolate and the
/// result moves back without copying (`Isolate.run` → `Isolate.exit`).

@ProviderFor(reverseGeocoder)
final reverseGeocoderProvider = ReverseGeocoderProvider._();

/// The app's reverse geocoder: the bundled GeoNames gazetteer, loaded once and
/// kept alive. The asset read happens here (rootBundle needs the main
/// isolate); the ~8 MB gunzip + parse runs on a background isolate and the
/// result moves back without copying (`Isolate.run` → `Isolate.exit`).

final class ReverseGeocoderProvider
    extends
        $FunctionalProvider<
          AsyncValue<ReverseGeocoder>,
          ReverseGeocoder,
          FutureOr<ReverseGeocoder>
        >
    with $FutureModifier<ReverseGeocoder>, $FutureProvider<ReverseGeocoder> {
  /// The app's reverse geocoder: the bundled GeoNames gazetteer, loaded once and
  /// kept alive. The asset read happens here (rootBundle needs the main
  /// isolate); the ~8 MB gunzip + parse runs on a background isolate and the
  /// result moves back without copying (`Isolate.run` → `Isolate.exit`).
  ReverseGeocoderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reverseGeocoderProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reverseGeocoderHash();

  @$internal
  @override
  $FutureProviderElement<ReverseGeocoder> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ReverseGeocoder> create(Ref ref) {
    return reverseGeocoder(ref);
  }
}

String _$reverseGeocoderHash() => r'37124a16a812fe3a8baf8bb77048c111426cc835';

/// The bundled IPTC Media Topics vocabulary for the Subject-codes
/// autocomplete, loaded once and kept alive. Parsed inline — the asset is
/// ~10 KB / 1100 lines, far below isolate territory, and `Isolate.run` never
/// completes under a widget test's FakeAsync zone (the M-editor awaits this).

@ProviderFor(mediaTopics)
final mediaTopicsProvider = MediaTopicsProvider._();

/// The bundled IPTC Media Topics vocabulary for the Subject-codes
/// autocomplete, loaded once and kept alive. Parsed inline — the asset is
/// ~10 KB / 1100 lines, far below isolate territory, and `Isolate.run` never
/// completes under a widget test's FakeAsync zone (the M-editor awaits this).

final class MediaTopicsProvider
    extends
        $FunctionalProvider<
          AsyncValue<MediaTopics>,
          MediaTopics,
          FutureOr<MediaTopics>
        >
    with $FutureModifier<MediaTopics>, $FutureProvider<MediaTopics> {
  /// The bundled IPTC Media Topics vocabulary for the Subject-codes
  /// autocomplete, loaded once and kept alive. Parsed inline — the asset is
  /// ~10 KB / 1100 lines, far below isolate territory, and `Isolate.run` never
  /// completes under a widget test's FakeAsync zone (the M-editor awaits this).
  MediaTopicsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mediaTopicsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mediaTopicsHash();

  @$internal
  @override
  $FutureProviderElement<MediaTopics> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<MediaTopics> create(Ref ref) {
    return mediaTopics(ref);
  }
}

String _$mediaTopicsHash() => r'5c15ee513f4e519a70c6f127d6ed87de4352be15';
