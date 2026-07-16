// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The result of the startup update check: a newer GitHub release than the
/// running build, or null when up to date / disabled / offline.
///
/// It **defaults to null** (a no-op) so widget tests never touch the network.
/// `main()` overrides it with the real, throttled [checkForUpdatesOnStartup]
/// when the user hasn't opted out — mirroring the `previewRetryEnabled`
/// production-opt-in pattern. `CullPage` listens to it and flashes an
/// "update available" notice when it resolves to a non-null value.

@ProviderFor(availableUpdate)
final availableUpdateProvider = AvailableUpdateProvider._();

/// The result of the startup update check: a newer GitHub release than the
/// running build, or null when up to date / disabled / offline.
///
/// It **defaults to null** (a no-op) so widget tests never touch the network.
/// `main()` overrides it with the real, throttled [checkForUpdatesOnStartup]
/// when the user hasn't opted out — mirroring the `previewRetryEnabled`
/// production-opt-in pattern. `CullPage` listens to it and flashes an
/// "update available" notice when it resolves to a non-null value.

final class AvailableUpdateProvider
    extends
        $FunctionalProvider<
          AsyncValue<UpdateInfo?>,
          UpdateInfo?,
          FutureOr<UpdateInfo?>
        >
    with $FutureModifier<UpdateInfo?>, $FutureProvider<UpdateInfo?> {
  /// The result of the startup update check: a newer GitHub release than the
  /// running build, or null when up to date / disabled / offline.
  ///
  /// It **defaults to null** (a no-op) so widget tests never touch the network.
  /// `main()` overrides it with the real, throttled [checkForUpdatesOnStartup]
  /// when the user hasn't opted out — mirroring the `previewRetryEnabled`
  /// production-opt-in pattern. `CullPage` listens to it and flashes an
  /// "update available" notice when it resolves to a non-null value.
  AvailableUpdateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'availableUpdateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$availableUpdateHash();

  @$internal
  @override
  $FutureProviderElement<UpdateInfo?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<UpdateInfo?> create(Ref ref) {
    return availableUpdate(ref);
  }
}

String _$availableUpdateHash() => r'028761635f7ff8ef4bf4cbabd43a4d28e9a86bd4';
