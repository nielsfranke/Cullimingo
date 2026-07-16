// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'filter_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Holds the active grid filter and toggles for the quick-filter chips.

@ProviderFor(PhotoFilterController)
final photoFilterControllerProvider = PhotoFilterControllerProvider._();

/// Holds the active grid filter and toggles for the quick-filter chips.
final class PhotoFilterControllerProvider
    extends $NotifierProvider<PhotoFilterController, PhotoFilter> {
  /// Holds the active grid filter and toggles for the quick-filter chips.
  PhotoFilterControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'photoFilterControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$photoFilterControllerHash();

  @$internal
  @override
  PhotoFilterController create() => PhotoFilterController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PhotoFilter value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PhotoFilter>(value),
    );
  }
}

String _$photoFilterControllerHash() =>
    r'ef905686db47f5b999ca05b3926e3b098c479dbb';

/// Holds the active grid filter and toggles for the quick-filter chips.

abstract class _$PhotoFilterController extends $Notifier<PhotoFilter> {
  PhotoFilter build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PhotoFilter, PhotoFilter>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PhotoFilter, PhotoFilter>,
              PhotoFilter,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Startup seed for [FilterPresets] — the presets persisted last session,
/// overridden in `main()` (empty on first run / tests).

@ProviderFor(filterPresetsSeed)
final filterPresetsSeedProvider = FilterPresetsSeedProvider._();

/// Startup seed for [FilterPresets] — the presets persisted last session,
/// overridden in `main()` (empty on first run / tests).

final class FilterPresetsSeedProvider
    extends
        $FunctionalProvider<
          List<FilterPreset>,
          List<FilterPreset>,
          List<FilterPreset>
        >
    with $Provider<List<FilterPreset>> {
  /// Startup seed for [FilterPresets] — the presets persisted last session,
  /// overridden in `main()` (empty on first run / tests).
  FilterPresetsSeedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'filterPresetsSeedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$filterPresetsSeedHash();

  @$internal
  @override
  $ProviderElement<List<FilterPreset>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<FilterPreset> create(Ref ref) {
    return filterPresetsSeed(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<FilterPreset> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<FilterPreset>>(value),
    );
  }
}

String _$filterPresetsSeedHash() => r'e6e6cd2041d7d7ef821935b0d417ba542885aa57';

/// The user's saved, named grid-filter presets (`BUILD_PLAN.md` §5). Global —
/// a filter carries no import-specific data — so a preset is offered on every
/// shoot. Applied via [PhotoFilterController.restore]; persisted to settings.

@ProviderFor(FilterPresets)
final filterPresetsProvider = FilterPresetsProvider._();

/// The user's saved, named grid-filter presets (`BUILD_PLAN.md` §5). Global —
/// a filter carries no import-specific data — so a preset is offered on every
/// shoot. Applied via [PhotoFilterController.restore]; persisted to settings.
final class FilterPresetsProvider
    extends $NotifierProvider<FilterPresets, List<FilterPreset>> {
  /// The user's saved, named grid-filter presets (`BUILD_PLAN.md` §5). Global —
  /// a filter carries no import-specific data — so a preset is offered on every
  /// shoot. Applied via [PhotoFilterController.restore]; persisted to settings.
  FilterPresetsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'filterPresetsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$filterPresetsHash();

  @$internal
  @override
  FilterPresets create() => FilterPresets();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<FilterPreset> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<FilterPreset>>(value),
    );
  }
}

String _$filterPresetsHash() => r'4a72bc3ce7870447e8a1a1f1a37e7035fa04e387';

/// The user's saved, named grid-filter presets (`BUILD_PLAN.md` §5). Global —
/// a filter carries no import-specific data — so a preset is offered on every
/// shoot. Applied via [PhotoFilterController.restore]; persisted to settings.

abstract class _$FilterPresets extends $Notifier<List<FilterPreset>> {
  List<FilterPreset> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<FilterPreset>, List<FilterPreset>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<FilterPreset>, List<FilterPreset>>,
              List<FilterPreset>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Holds the active grid sort order (top-bar sort control, `BUILD_PLAN.md` §7).

@ProviderFor(PhotoSortController)
final photoSortControllerProvider = PhotoSortControllerProvider._();

/// Holds the active grid sort order (top-bar sort control, `BUILD_PLAN.md` §7).
final class PhotoSortControllerProvider
    extends $NotifierProvider<PhotoSortController, PhotoSort> {
  /// Holds the active grid sort order (top-bar sort control, `BUILD_PLAN.md` §7).
  PhotoSortControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'photoSortControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$photoSortControllerHash();

  @$internal
  @override
  PhotoSortController create() => PhotoSortController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PhotoSort value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PhotoSort>(value),
    );
  }
}

String _$photoSortControllerHash() =>
    r'6913daba7c412e28401fc9229b43b003045f8032';

/// Holds the active grid sort order (top-bar sort control, `BUILD_PLAN.md` §7).

abstract class _$PhotoSortController extends $Notifier<PhotoSort> {
  PhotoSort build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PhotoSort, PhotoSort>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PhotoSort, PhotoSort>,
              PhotoSort,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// On-demand perceptual-hash similarity groups (§8), **per import** so running
/// "Find similar" in one folder doesn't switch every other tab to similarity
/// mode. Empty until the user runs the pass for a folder.

@ProviderFor(SimilarGroups)
final similarGroupsProvider = SimilarGroupsProvider._();

/// On-demand perceptual-hash similarity groups (§8), **per import** so running
/// "Find similar" in one folder doesn't switch every other tab to similarity
/// mode. Empty until the user runs the pass for a folder.
final class SimilarGroupsProvider
    extends $NotifierProvider<SimilarGroups, Map<int, BurstGroups>> {
  /// On-demand perceptual-hash similarity groups (§8), **per import** so running
  /// "Find similar" in one folder doesn't switch every other tab to similarity
  /// mode. Empty until the user runs the pass for a folder.
  SimilarGroupsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'similarGroupsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$similarGroupsHash();

  @$internal
  @override
  SimilarGroups create() => SimilarGroups();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<int, BurstGroups> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<int, BurstGroups>>(value),
    );
  }
}

String _$similarGroupsHash() => r'f010c86a9ad683e4e0e466d89143ebb7479728e7';

/// On-demand perceptual-hash similarity groups (§8), **per import** so running
/// "Find similar" in one folder doesn't switch every other tab to similarity
/// mode. Empty until the user runs the pass for a folder.

abstract class _$SimilarGroups extends $Notifier<Map<int, BurstGroups>> {
  Map<int, BurstGroups> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Map<int, BurstGroups>, Map<int, BurstGroups>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Map<int, BurstGroups>, Map<int, BurstGroups>>,
              Map<int, BurstGroups>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
