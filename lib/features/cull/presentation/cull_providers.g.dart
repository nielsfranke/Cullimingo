// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cull_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The app-wide drift database. Kept alive for the whole session.

@ProviderFor(appDatabase)
final appDatabaseProvider = AppDatabaseProvider._();

/// The app-wide drift database. Kept alive for the whole session.

final class AppDatabaseProvider
    extends $FunctionalProvider<AppDatabase, AppDatabase, AppDatabase>
    with $Provider<AppDatabase> {
  /// The app-wide drift database. Kept alive for the whole session.
  AppDatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appDatabaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appDatabaseHash();

  @$internal
  @override
  $ProviderElement<AppDatabase> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppDatabase create(Ref ref) {
    return appDatabase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppDatabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppDatabase>(value),
    );
  }
}

String _$appDatabaseHash() => r'59cce38d45eeaba199eddd097d8e149d66f9f3e1';

/// Number of photos whose XMP sidecar write is still in flight — drives the
/// toolbar "Syncing N…" indicator and the drain-on-quit guard. Marks hit the DB
/// (and the grid) instantly, then mirror to sidecars in the background; this is
/// the only window in which a mark is applied but not yet on disk.

@ProviderFor(SidecarSync)
final sidecarSyncProvider = SidecarSyncProvider._();

/// Number of photos whose XMP sidecar write is still in flight — drives the
/// toolbar "Syncing N…" indicator and the drain-on-quit guard. Marks hit the DB
/// (and the grid) instantly, then mirror to sidecars in the background; this is
/// the only window in which a mark is applied but not yet on disk.
final class SidecarSyncProvider extends $NotifierProvider<SidecarSync, int> {
  /// Number of photos whose XMP sidecar write is still in flight — drives the
  /// toolbar "Syncing N…" indicator and the drain-on-quit guard. Marks hit the DB
  /// (and the grid) instantly, then mirror to sidecars in the background; this is
  /// the only window in which a mark is applied but not yet on disk.
  SidecarSyncProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sidecarSyncProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sidecarSyncHash();

  @$internal
  @override
  SidecarSync create() => SidecarSync();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$sidecarSyncHash() => r'79a5b2b693c442ec76e075b650e63d1a272f02b4';

/// Number of photos whose XMP sidecar write is still in flight — drives the
/// toolbar "Syncing N…" indicator and the drain-on-quit guard. Marks hit the DB
/// (and the grid) instantly, then mirror to sidecars in the background; this is
/// the only window in which a mark is applied but not yet on disk.

abstract class _$SidecarSync extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The most recent failed sidecar-write batch. A photo's marks hit the DB (and
/// the grid) instantly, then mirror to its `.xmp`; when that write fails (a
/// read-only volume, a full disk, a removed drive) the count surfaces here — a
/// monotonic [seq] so two identical-sized failures each still notify — and the
/// page warns instead of the failure being silently invisible.

@ProviderFor(SidecarWriteError)
final sidecarWriteErrorProvider = SidecarWriteErrorProvider._();

/// The most recent failed sidecar-write batch. A photo's marks hit the DB (and
/// the grid) instantly, then mirror to its `.xmp`; when that write fails (a
/// read-only volume, a full disk, a removed drive) the count surfaces here — a
/// monotonic [seq] so two identical-sized failures each still notify — and the
/// page warns instead of the failure being silently invisible.
final class SidecarWriteErrorProvider
    extends $NotifierProvider<SidecarWriteError, ({int count, int seq})> {
  /// The most recent failed sidecar-write batch. A photo's marks hit the DB (and
  /// the grid) instantly, then mirror to its `.xmp`; when that write fails (a
  /// read-only volume, a full disk, a removed drive) the count surfaces here — a
  /// monotonic [seq] so two identical-sized failures each still notify — and the
  /// page warns instead of the failure being silently invisible.
  SidecarWriteErrorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sidecarWriteErrorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sidecarWriteErrorHash();

  @$internal
  @override
  SidecarWriteError create() => SidecarWriteError();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(({int count, int seq}) value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<({int count, int seq})>(value),
    );
  }
}

String _$sidecarWriteErrorHash() => r'8359363a06f8c338ae7d4578721ea4ef950b6716';

/// The most recent failed sidecar-write batch. A photo's marks hit the DB (and
/// the grid) instantly, then mirror to its `.xmp`; when that write fails (a
/// read-only volume, a full disk, a removed drive) the count surfaces here — a
/// monotonic [seq] so two identical-sized failures each still notify — and the
/// page warns instead of the failure being silently invisible.

abstract class _$SidecarWriteError extends $Notifier<({int count, int seq})> {
  ({int count, int seq}) build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<({int count, int seq}), ({int count, int seq})>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<({int count, int seq}), ({int count, int seq})>,
              ({int count, int seq}),
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Keeps the read model and XMP sidecars in sync (C1/LR interop). Reports write
/// progress to [SidecarSync] so the UI can show "Syncing N…", and write
/// failures to [SidecarWriteError] so the page can warn.

@ProviderFor(metadataRepository)
final metadataRepositoryProvider = MetadataRepositoryProvider._();

/// Keeps the read model and XMP sidecars in sync (C1/LR interop). Reports write
/// progress to [SidecarSync] so the UI can show "Syncing N…", and write
/// failures to [SidecarWriteError] so the page can warn.

final class MetadataRepositoryProvider
    extends
        $FunctionalProvider<
          MetadataRepository,
          MetadataRepository,
          MetadataRepository
        >
    with $Provider<MetadataRepository> {
  /// Keeps the read model and XMP sidecars in sync (C1/LR interop). Reports write
  /// progress to [SidecarSync] so the UI can show "Syncing N…", and write
  /// failures to [SidecarWriteError] so the page can warn.
  MetadataRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'metadataRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$metadataRepositoryHash();

  @$internal
  @override
  $ProviderElement<MetadataRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  MetadataRepository create(Ref ref) {
    return metadataRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MetadataRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MetadataRepository>(value),
    );
  }
}

String _$metadataRepositoryHash() =>
    r'5aaf929ee8e3bfb8aff88693459d5d053a6b2cb4';

/// Repository that imports folders into the read model.

@ProviderFor(libraryRepository)
final libraryRepositoryProvider = LibraryRepositoryProvider._();

/// Repository that imports folders into the read model.

final class LibraryRepositoryProvider
    extends
        $FunctionalProvider<
          LibraryRepository,
          LibraryRepository,
          LibraryRepository
        >
    with $Provider<LibraryRepository> {
  /// Repository that imports folders into the read model.
  LibraryRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'libraryRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libraryRepositoryHash();

  @$internal
  @override
  $ProviderElement<LibraryRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LibraryRepository create(Ref ref) {
    return libraryRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LibraryRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LibraryRepository>(value),
    );
  }
}

String _$libraryRepositoryHash() => r'47d31d54237a58a7d9c1c520251a0c350d9771ba';

/// Persistent isolate pool that extracts thumbnails (RAW + bitmap), keeping
/// libraw loaded once per worker. Disposed with the app.

@ProviderFor(previewPool)
final previewPoolProvider = PreviewPoolProvider._();

/// Persistent isolate pool that extracts thumbnails (RAW + bitmap), keeping
/// libraw loaded once per worker. Disposed with the app.

final class PreviewPoolProvider
    extends $FunctionalProvider<PreviewPool, PreviewPool, PreviewPool>
    with $Provider<PreviewPool> {
  /// Persistent isolate pool that extracts thumbnails (RAW + bitmap), keeping
  /// libraw loaded once per worker. Disposed with the app.
  PreviewPoolProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'previewPoolProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$previewPoolHash();

  @$internal
  @override
  $ProviderElement<PreviewPool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PreviewPool create(Ref ref) {
    return previewPool(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PreviewPool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PreviewPool>(value),
    );
  }
}

String _$previewPoolHash() => r'd6e9d9a3396921497fec6d2a085a43a296cf04fe';

/// Two-tier on-disk preview cache wrapping the pool (decode-once). Pruned to
/// the disk budget on creation (startup) so it can't fill the disk over time.
/// Thumbnail resolution + RAM budget come from the active performance preset.

@ProviderFor(previewCache)
final previewCacheProvider = PreviewCacheProvider._();

/// Two-tier on-disk preview cache wrapping the pool (decode-once). Pruned to
/// the disk budget on creation (startup) so it can't fill the disk over time.
/// Thumbnail resolution + RAM budget come from the active performance preset.

final class PreviewCacheProvider
    extends $FunctionalProvider<PreviewCache, PreviewCache, PreviewCache>
    with $Provider<PreviewCache> {
  /// Two-tier on-disk preview cache wrapping the pool (decode-once). Pruned to
  /// the disk budget on creation (startup) so it can't fill the disk over time.
  /// Thumbnail resolution + RAM budget come from the active performance preset.
  PreviewCacheProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'previewCacheProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$previewCacheHash();

  @$internal
  @override
  $ProviderElement<PreviewCache> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PreviewCache create(Ref ref) {
    return previewCache(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PreviewCache value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PreviewCache>(value),
    );
  }
}

String _$previewCacheHash() => r'b4379ef11657353a4e441e58a7d893d5d2cedb4e';

/// Startup seed for [GridCellWidth] — the value persisted last session,
/// overridden in `main()` (default [GridCellWidth.fallback] on first run).

@ProviderFor(gridCellWidthSeed)
final gridCellWidthSeedProvider = GridCellWidthSeedProvider._();

/// Startup seed for [GridCellWidth] — the value persisted last session,
/// overridden in `main()` (default [GridCellWidth.fallback] on first run).

final class GridCellWidthSeedProvider
    extends $FunctionalProvider<double, double, double>
    with $Provider<double> {
  /// Startup seed for [GridCellWidth] — the value persisted last session,
  /// overridden in `main()` (default [GridCellWidth.fallback] on first run).
  GridCellWidthSeedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'gridCellWidthSeedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$gridCellWidthSeedHash();

  @$internal
  @override
  $ProviderElement<double> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  double create(Ref ref) {
    return gridCellWidthSeed(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(double value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<double>(value),
    );
  }
}

String _$gridCellWidthSeedHash() => r'd596b92b218a599c5dba69c035590776687dea8a';

/// Target grid cell width in logical pixels, driven by the toolbar size slider.
/// Only changes how big thumbnails are *drawn* — the cached source stays 512px,
/// so resizing never re-extracts (Photo-Mechanic-style; §7). The size is
/// remembered globally: seeded from the last session and saved (debounced) on
/// change, so the next launch opens at the same zoom.

@ProviderFor(GridCellWidth)
final gridCellWidthProvider = GridCellWidthProvider._();

/// Target grid cell width in logical pixels, driven by the toolbar size slider.
/// Only changes how big thumbnails are *drawn* — the cached source stays 512px,
/// so resizing never re-extracts (Photo-Mechanic-style; §7). The size is
/// remembered globally: seeded from the last session and saved (debounced) on
/// change, so the next launch opens at the same zoom.
final class GridCellWidthProvider
    extends $NotifierProvider<GridCellWidth, double> {
  /// Target grid cell width in logical pixels, driven by the toolbar size slider.
  /// Only changes how big thumbnails are *drawn* — the cached source stays 512px,
  /// so resizing never re-extracts (Photo-Mechanic-style; §7). The size is
  /// remembered globally: seeded from the last session and saved (debounced) on
  /// change, so the next launch opens at the same zoom.
  GridCellWidthProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'gridCellWidthProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$gridCellWidthHash();

  @$internal
  @override
  GridCellWidth create() => GridCellWidth();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(double value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<double>(value),
    );
  }
}

String _$gridCellWidthHash() => r'24cb2f54aefbf5e9d161fbeec4d7f533b7429105';

/// Target grid cell width in logical pixels, driven by the toolbar size slider.
/// Only changes how big thumbnails are *drawn* — the cached source stays 512px,
/// so resizing never re-extracts (Photo-Mechanic-style; §7). The size is
/// remembered globally: seeded from the last session and saved (debounced) on
/// change, so the next launch opens at the same zoom.

abstract class _$GridCellWidth extends $Notifier<double> {
  double build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<double, double>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<double, double>,
              double,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Startup seed for [TooltipsEnabled] — the value persisted last session,
/// overridden in `main()` (default true on first run / tests).

@ProviderFor(tooltipsEnabledSeed)
final tooltipsEnabledSeedProvider = TooltipsEnabledSeedProvider._();

/// Startup seed for [TooltipsEnabled] — the value persisted last session,
/// overridden in `main()` (default true on first run / tests).

final class TooltipsEnabledSeedProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Startup seed for [TooltipsEnabled] — the value persisted last session,
  /// overridden in `main()` (default true on first run / tests).
  TooltipsEnabledSeedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tooltipsEnabledSeedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tooltipsEnabledSeedHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return tooltipsEnabledSeed(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$tooltipsEnabledSeedHash() =>
    r'f9e97be7b5b6bc886b8e6851caff353526d1d52f';

/// Whether button tooltips are shown app-wide (Settings → Interface). Applies
/// immediately (the app wraps its UI in `TooltipVisibility`) and is persisted.

@ProviderFor(TooltipsEnabled)
final tooltipsEnabledProvider = TooltipsEnabledProvider._();

/// Whether button tooltips are shown app-wide (Settings → Interface). Applies
/// immediately (the app wraps its UI in `TooltipVisibility`) and is persisted.
final class TooltipsEnabledProvider
    extends $NotifierProvider<TooltipsEnabled, bool> {
  /// Whether button tooltips are shown app-wide (Settings → Interface). Applies
  /// immediately (the app wraps its UI in `TooltipVisibility`) and is persisted.
  TooltipsEnabledProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tooltipsEnabledProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tooltipsEnabledHash();

  @$internal
  @override
  TooltipsEnabled create() => TooltipsEnabled();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$tooltipsEnabledHash() => r'16832f26c4980fe51361c45d1fe4a1b76cc3f581';

/// Whether button tooltips are shown app-wide (Settings → Interface). Applies
/// immediately (the app wraps its UI in `TooltipVisibility`) and is persisted.

abstract class _$TooltipsEnabled extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Startup seed for [AutoAdvanceAfterMark] — the value persisted last session,
/// overridden in `main()` (default false on first run / tests).

@ProviderFor(autoAdvanceAfterMarkSeed)
final autoAdvanceAfterMarkSeedProvider = AutoAdvanceAfterMarkSeedProvider._();

/// Startup seed for [AutoAdvanceAfterMark] — the value persisted last session,
/// overridden in `main()` (default false on first run / tests).

final class AutoAdvanceAfterMarkSeedProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Startup seed for [AutoAdvanceAfterMark] — the value persisted last session,
  /// overridden in `main()` (default false on first run / tests).
  AutoAdvanceAfterMarkSeedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'autoAdvanceAfterMarkSeedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$autoAdvanceAfterMarkSeedHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return autoAdvanceAfterMarkSeed(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$autoAdvanceAfterMarkSeedHash() =>
    r'6bc872b1313fd12b2a57aba740b1b3a54723983b';

/// Whether marking a single photo advances focus to the next one,
/// Photo-Mechanic style (Settings → Interface). Read in the keyboard handler;
/// persisted.

@ProviderFor(AutoAdvanceAfterMark)
final autoAdvanceAfterMarkProvider = AutoAdvanceAfterMarkProvider._();

/// Whether marking a single photo advances focus to the next one,
/// Photo-Mechanic style (Settings → Interface). Read in the keyboard handler;
/// persisted.
final class AutoAdvanceAfterMarkProvider
    extends $NotifierProvider<AutoAdvanceAfterMark, bool> {
  /// Whether marking a single photo advances focus to the next one,
  /// Photo-Mechanic style (Settings → Interface). Read in the keyboard handler;
  /// persisted.
  AutoAdvanceAfterMarkProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'autoAdvanceAfterMarkProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$autoAdvanceAfterMarkHash();

  @$internal
  @override
  AutoAdvanceAfterMark create() => AutoAdvanceAfterMark();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$autoAdvanceAfterMarkHash() =>
    r'65cc4f3eb5c14f927ddd5c922abb562878488c84';

/// Whether marking a single photo advances focus to the next one,
/// Photo-Mechanic style (Settings → Interface). Read in the keyboard handler;
/// persisted.

abstract class _$AutoAdvanceAfterMark extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Startup seed for [ShortcutsHintSeen]. **Defaults to true (already seen)** so
/// the first-run cheat sheet only ever fires on a real launch, where `main()`
/// overrides it with the persisted flag — widget tests, which don't override
/// it, never get a surprise dialog popped over the page.

@ProviderFor(shortcutsHintSeenSeed)
final shortcutsHintSeenSeedProvider = ShortcutsHintSeenSeedProvider._();

/// Startup seed for [ShortcutsHintSeen]. **Defaults to true (already seen)** so
/// the first-run cheat sheet only ever fires on a real launch, where `main()`
/// overrides it with the persisted flag — widget tests, which don't override
/// it, never get a surprise dialog popped over the page.

final class ShortcutsHintSeenSeedProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Startup seed for [ShortcutsHintSeen]. **Defaults to true (already seen)** so
  /// the first-run cheat sheet only ever fires on a real launch, where `main()`
  /// overrides it with the persisted flag — widget tests, which don't override
  /// it, never get a surprise dialog popped over the page.
  ShortcutsHintSeenSeedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shortcutsHintSeenSeedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shortcutsHintSeenSeedHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return shortcutsHintSeenSeed(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$shortcutsHintSeenSeedHash() =>
    r'1e650eac4e696051bf632cea89df9a01e4ca6c0f';

/// Whether the first-run keyboard cheat sheet has already been shown. The cull
/// page pops the sheet once when this is false, then calls [ShortcutsHintSeen.
/// markSeen] to persist it so it never shows again.

@ProviderFor(ShortcutsHintSeen)
final shortcutsHintSeenProvider = ShortcutsHintSeenProvider._();

/// Whether the first-run keyboard cheat sheet has already been shown. The cull
/// page pops the sheet once when this is false, then calls [ShortcutsHintSeen.
/// markSeen] to persist it so it never shows again.
final class ShortcutsHintSeenProvider
    extends $NotifierProvider<ShortcutsHintSeen, bool> {
  /// Whether the first-run keyboard cheat sheet has already been shown. The cull
  /// page pops the sheet once when this is false, then calls [ShortcutsHintSeen.
  /// markSeen] to persist it so it never shows again.
  ShortcutsHintSeenProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shortcutsHintSeenProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shortcutsHintSeenHash();

  @$internal
  @override
  ShortcutsHintSeen create() => ShortcutsHintSeen();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$shortcutsHintSeenHash() => r'6aa5ce5d3184ef8f10f6050ff06cfa590a50f310';

/// Whether the first-run keyboard cheat sheet has already been shown. The cull
/// page pops the sheet once when this is false, then calls [ShortcutsHintSeen.
/// markSeen] to persist it so it never shows again.

abstract class _$ShortcutsHintSeen extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Startup seed for [MarkConfirmationEnabled]. **Defaults to false** so the
/// loupe's hide-timer never fires unbidden in widget tests; `main()` overrides
/// it with the persisted flag (true by default), so production is on.

@ProviderFor(markConfirmationEnabledSeed)
final markConfirmationEnabledSeedProvider =
    MarkConfirmationEnabledSeedProvider._();

/// Startup seed for [MarkConfirmationEnabled]. **Defaults to false** so the
/// loupe's hide-timer never fires unbidden in widget tests; `main()` overrides
/// it with the persisted flag (true by default), so production is on.

final class MarkConfirmationEnabledSeedProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Startup seed for [MarkConfirmationEnabled]. **Defaults to false** so the
  /// loupe's hide-timer never fires unbidden in widget tests; `main()` overrides
  /// it with the persisted flag (true by default), so production is on.
  MarkConfirmationEnabledSeedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'markConfirmationEnabledSeedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$markConfirmationEnabledSeedHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return markConfirmationEnabledSeed(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$markConfirmationEnabledSeedHash() =>
    r'cfe812e014c1924d7f6b87fbe1fcaba3f429e1d8';

/// Whether the loupe flashes an ephemeral mark-confirmation HUD (Settings →
/// Interface). Read live by the loupe; persisted.

@ProviderFor(MarkConfirmationEnabled)
final markConfirmationEnabledProvider = MarkConfirmationEnabledProvider._();

/// Whether the loupe flashes an ephemeral mark-confirmation HUD (Settings →
/// Interface). Read live by the loupe; persisted.
final class MarkConfirmationEnabledProvider
    extends $NotifierProvider<MarkConfirmationEnabled, bool> {
  /// Whether the loupe flashes an ephemeral mark-confirmation HUD (Settings →
  /// Interface). Read live by the loupe; persisted.
  MarkConfirmationEnabledProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'markConfirmationEnabledProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$markConfirmationEnabledHash();

  @$internal
  @override
  MarkConfirmationEnabled create() => MarkConfirmationEnabled();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$markConfirmationEnabledHash() =>
    r'782b02216bf7658011afbb8ad1f29a15316fa25e';

/// Whether the loupe flashes an ephemeral mark-confirmation HUD (Settings →
/// Interface). Read live by the loupe; persisted.

abstract class _$MarkConfirmationEnabled extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Startup seed for [FilmstripVisible]. **Defaults to false** so the loupe's
/// filmstrip (and its scroll-into-view animation) never fires unbidden in
/// widget tests; `main()` overrides it with the persisted flag (true by
/// default), so production shows the strip.

@ProviderFor(filmstripVisibleSeed)
final filmstripVisibleSeedProvider = FilmstripVisibleSeedProvider._();

/// Startup seed for [FilmstripVisible]. **Defaults to false** so the loupe's
/// filmstrip (and its scroll-into-view animation) never fires unbidden in
/// widget tests; `main()` overrides it with the persisted flag (true by
/// default), so production shows the strip.

final class FilmstripVisibleSeedProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Startup seed for [FilmstripVisible]. **Defaults to false** so the loupe's
  /// filmstrip (and its scroll-into-view animation) never fires unbidden in
  /// widget tests; `main()` overrides it with the persisted flag (true by
  /// default), so production shows the strip.
  FilmstripVisibleSeedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'filmstripVisibleSeedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$filmstripVisibleSeedHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return filmstripVisibleSeed(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$filmstripVisibleSeedHash() =>
    r'b7aa546798dbb1ae1fd71478ede7af2535fc2e0b';

/// Whether the loupe shows its thumbnail filmstrip. Toggled from the loupe;
/// persisted.

@ProviderFor(FilmstripVisible)
final filmstripVisibleProvider = FilmstripVisibleProvider._();

/// Whether the loupe shows its thumbnail filmstrip. Toggled from the loupe;
/// persisted.
final class FilmstripVisibleProvider
    extends $NotifierProvider<FilmstripVisible, bool> {
  /// Whether the loupe shows its thumbnail filmstrip. Toggled from the loupe;
  /// persisted.
  FilmstripVisibleProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'filmstripVisibleProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$filmstripVisibleHash();

  @$internal
  @override
  FilmstripVisible create() => FilmstripVisible();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$filmstripVisibleHash() => r'8c6c63059b7c1875ea4c4e78404c660642b20d2c';

/// Whether the loupe shows its thumbnail filmstrip. Toggled from the loupe;
/// persisted.

abstract class _$FilmstripVisible extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Whether the loupe shows the RGB histogram panel. Session state — not
/// persisted, a panel toggle need not survive relaunch (mirrors
/// `InspectorOpen`).

@ProviderFor(LoupeHistogramVisible)
final loupeHistogramVisibleProvider = LoupeHistogramVisibleProvider._();

/// Whether the loupe shows the RGB histogram panel. Session state — not
/// persisted, a panel toggle need not survive relaunch (mirrors
/// `InspectorOpen`).
final class LoupeHistogramVisibleProvider
    extends $NotifierProvider<LoupeHistogramVisible, bool> {
  /// Whether the loupe shows the RGB histogram panel. Session state — not
  /// persisted, a panel toggle need not survive relaunch (mirrors
  /// `InspectorOpen`).
  LoupeHistogramVisibleProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'loupeHistogramVisibleProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$loupeHistogramVisibleHash();

  @$internal
  @override
  LoupeHistogramVisible create() => LoupeHistogramVisible();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$loupeHistogramVisibleHash() =>
    r'aebbb000f028590b4fffbeaa1d4a5c0db061c418';

/// Whether the loupe shows the RGB histogram panel. Session state — not
/// persisted, a panel toggle need not survive relaunch (mirrors
/// `InspectorOpen`).

abstract class _$LoupeHistogramVisible extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Whether the loupe tints blown highlights (red) and crushed shadows (blue)
/// over the photo. Session state — not persisted.

@ProviderFor(LoupeClippingVisible)
final loupeClippingVisibleProvider = LoupeClippingVisibleProvider._();

/// Whether the loupe tints blown highlights (red) and crushed shadows (blue)
/// over the photo. Session state — not persisted.
final class LoupeClippingVisibleProvider
    extends $NotifierProvider<LoupeClippingVisible, bool> {
  /// Whether the loupe tints blown highlights (red) and crushed shadows (blue)
  /// over the photo. Session state — not persisted.
  LoupeClippingVisibleProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'loupeClippingVisibleProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$loupeClippingVisibleHash();

  @$internal
  @override
  LoupeClippingVisible create() => LoupeClippingVisible();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$loupeClippingVisibleHash() =>
    r'3e07715906686132c3766c1e5ecb0371043d6272';

/// Whether the loupe tints blown highlights (red) and crushed shadows (blue)
/// over the photo. Session state — not persisted.

abstract class _$LoupeClippingVisible extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Whether the loupe overlays a focus-peaking edge map over the photo (pure
/// gradient-magnitude signal processing, not AI). Session state — not
/// persisted.

@ProviderFor(LoupeFocusPeakingVisible)
final loupeFocusPeakingVisibleProvider = LoupeFocusPeakingVisibleProvider._();

/// Whether the loupe overlays a focus-peaking edge map over the photo (pure
/// gradient-magnitude signal processing, not AI). Session state — not
/// persisted.
final class LoupeFocusPeakingVisibleProvider
    extends $NotifierProvider<LoupeFocusPeakingVisible, bool> {
  /// Whether the loupe overlays a focus-peaking edge map over the photo (pure
  /// gradient-magnitude signal processing, not AI). Session state — not
  /// persisted.
  LoupeFocusPeakingVisibleProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'loupeFocusPeakingVisibleProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$loupeFocusPeakingVisibleHash();

  @$internal
  @override
  LoupeFocusPeakingVisible create() => LoupeFocusPeakingVisible();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$loupeFocusPeakingVisibleHash() =>
    r'86d3c9794a4147073e3ea5b7778dcd97eadd7781';

/// Whether the loupe overlays a focus-peaking edge map over the photo (pure
/// gradient-magnitude signal processing, not AI). Session state — not
/// persisted.

abstract class _$LoupeFocusPeakingVisible extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Startup seed for [RecentFolders] — the paths persisted last session,
/// overridden in `main()` (empty on first run / tests).

@ProviderFor(recentFoldersSeed)
final recentFoldersSeedProvider = RecentFoldersSeedProvider._();

/// Startup seed for [RecentFolders] — the paths persisted last session,
/// overridden in `main()` (empty on first run / tests).

final class RecentFoldersSeedProvider
    extends $FunctionalProvider<List<String>, List<String>, List<String>>
    with $Provider<List<String>> {
  /// Startup seed for [RecentFolders] — the paths persisted last session,
  /// overridden in `main()` (empty on first run / tests).
  RecentFoldersSeedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recentFoldersSeedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recentFoldersSeedHash();

  @$internal
  @override
  $ProviderElement<List<String>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<String> create(Ref ref) {
    return recentFoldersSeed(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<String>>(value),
    );
  }
}

String _$recentFoldersSeedHash() => r'a64400884696bb47ce124194b7b4ae7c68863fb1';

/// The recently-opened folders (most-recent-first) behind the "Open recent"
/// menu. Updated whenever a folder is opened; persisted.

@ProviderFor(RecentFolders)
final recentFoldersProvider = RecentFoldersProvider._();

/// The recently-opened folders (most-recent-first) behind the "Open recent"
/// menu. Updated whenever a folder is opened; persisted.
final class RecentFoldersProvider
    extends $NotifierProvider<RecentFolders, List<String>> {
  /// The recently-opened folders (most-recent-first) behind the "Open recent"
  /// menu. Updated whenever a folder is opened; persisted.
  RecentFoldersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recentFoldersProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recentFoldersHash();

  @$internal
  @override
  RecentFolders create() => RecentFolders();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<String>>(value),
    );
  }
}

String _$recentFoldersHash() => r'b22fa61141edaff451d87eb800c25cdac8f2662b';

/// The recently-opened folders (most-recent-first) behind the "Open recent"
/// menu. Updated whenever a folder is opened; persisted.

abstract class _$RecentFolders extends $Notifier<List<String>> {
  List<String> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<String>, List<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<String>, List<String>>,
              List<String>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Signals the loupe's mark-confirmation HUD. The loupe listens; the keyboard
/// handler and loupe toolbar push here when a mark is applied in the loupe.

@ProviderFor(LoupeMarkFlash)
final loupeMarkFlashProvider = LoupeMarkFlashProvider._();

/// Signals the loupe's mark-confirmation HUD. The loupe listens; the keyboard
/// handler and loupe toolbar push here when a mark is applied in the loupe.
final class LoupeMarkFlashProvider
    extends $NotifierProvider<LoupeMarkFlash, LoupeMarkSignal?> {
  /// Signals the loupe's mark-confirmation HUD. The loupe listens; the keyboard
  /// handler and loupe toolbar push here when a mark is applied in the loupe.
  LoupeMarkFlashProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'loupeMarkFlashProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$loupeMarkFlashHash();

  @$internal
  @override
  LoupeMarkFlash create() => LoupeMarkFlash();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LoupeMarkSignal? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LoupeMarkSignal?>(value),
    );
  }
}

String _$loupeMarkFlashHash() => r'2572774082ba083c389975d5a30f28de89f4051e';

/// Signals the loupe's mark-confirmation HUD. The loupe listens; the keyboard
/// handler and loupe toolbar push here when a mark is applied in the loupe.

abstract class _$LoupeMarkFlash extends $Notifier<LoupeMarkSignal?> {
  LoupeMarkSignal? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<LoupeMarkSignal?, LoupeMarkSignal?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LoupeMarkSignal?, LoupeMarkSignal?>,
              LoupeMarkSignal?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Startup seed for [CullShortcuts] — persisted overrides from last session,
/// overridden in `main()` (empty = all defaults, on first run / tests).

@ProviderFor(cullShortcutsSeed)
final cullShortcutsSeedProvider = CullShortcutsSeedProvider._();

/// Startup seed for [CullShortcuts] — persisted overrides from last session,
/// overridden in `main()` (empty = all defaults, on first run / tests).

final class CullShortcutsSeedProvider
    extends
        $FunctionalProvider<
          Map<String, int>,
          Map<String, int>,
          Map<String, int>
        >
    with $Provider<Map<String, int>> {
  /// Startup seed for [CullShortcuts] — persisted overrides from last session,
  /// overridden in `main()` (empty = all defaults, on first run / tests).
  CullShortcutsSeedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cullShortcutsSeedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cullShortcutsSeedHash();

  @$internal
  @override
  $ProviderElement<Map<String, int>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Map<String, int> create(Ref ref) {
    return cullShortcutsSeed(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, int> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, int>>(value),
    );
  }
}

String _$cullShortcutsSeedHash() => r'99a9ed1321abd73274c6a7512aa5de6d30df5b28';

/// The resolved cull keymap (defaults + user rebindings), used by the grid key
/// handler and the shortcuts UI. Rebinding applies immediately and persists.

@ProviderFor(CullShortcutsController)
final cullShortcutsControllerProvider = CullShortcutsControllerProvider._();

/// The resolved cull keymap (defaults + user rebindings), used by the grid key
/// handler and the shortcuts UI. Rebinding applies immediately and persists.
final class CullShortcutsControllerProvider
    extends $NotifierProvider<CullShortcutsController, CullShortcuts> {
  /// The resolved cull keymap (defaults + user rebindings), used by the grid key
  /// handler and the shortcuts UI. Rebinding applies immediately and persists.
  CullShortcutsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cullShortcutsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cullShortcutsControllerHash();

  @$internal
  @override
  CullShortcutsController create() => CullShortcutsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CullShortcuts value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CullShortcuts>(value),
    );
  }
}

String _$cullShortcutsControllerHash() =>
    r'6708d526630e0d33a5e29d5ce478f41d7d4101f2';

/// The resolved cull keymap (defaults + user rebindings), used by the grid key
/// handler and the shortcuts UI. Rebinding applies immediately and persists.

abstract class _$CullShortcutsController extends $Notifier<CullShortcuts> {
  CullShortcuts build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<CullShortcuts, CullShortcuts>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CullShortcuts, CullShortcuts>,
              CullShortcuts,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Persisted loupe zoom — the *mode* (Fit / 100% / custom) plus the custom
/// scale. Kept alive so the choice carries across photo navigation and loupe
/// close/reopen. We store the mode, not a raw scale, because the absolute scale
/// that means "100%" differs per photo and viewport — restoring the number
/// would land on the wrong zoom (see [LoupeZoom.scaleForMode]).

@ProviderFor(LoupeZoomLevel)
final loupeZoomLevelProvider = LoupeZoomLevelProvider._();

/// Persisted loupe zoom — the *mode* (Fit / 100% / custom) plus the custom
/// scale. Kept alive so the choice carries across photo navigation and loupe
/// close/reopen. We store the mode, not a raw scale, because the absolute scale
/// that means "100%" differs per photo and viewport — restoring the number
/// would land on the wrong zoom (see [LoupeZoom.scaleForMode]).
final class LoupeZoomLevelProvider
    extends
        $NotifierProvider<
          LoupeZoomLevel,
          ({double customScale, LoupeZoomMode mode})
        > {
  /// Persisted loupe zoom — the *mode* (Fit / 100% / custom) plus the custom
  /// scale. Kept alive so the choice carries across photo navigation and loupe
  /// close/reopen. We store the mode, not a raw scale, because the absolute scale
  /// that means "100%" differs per photo and viewport — restoring the number
  /// would land on the wrong zoom (see [LoupeZoom.scaleForMode]).
  LoupeZoomLevelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'loupeZoomLevelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$loupeZoomLevelHash();

  @$internal
  @override
  LoupeZoomLevel create() => LoupeZoomLevel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(({double customScale, LoupeZoomMode mode}) value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<({double customScale, LoupeZoomMode mode})>(value),
    );
  }
}

String _$loupeZoomLevelHash() => r'2f6a6f290f928d57382502f82f9f640b60f41e02';

/// Persisted loupe zoom — the *mode* (Fit / 100% / custom) plus the custom
/// scale. Kept alive so the choice carries across photo navigation and loupe
/// close/reopen. We store the mode, not a raw scale, because the absolute scale
/// that means "100%" differs per photo and viewport — restoring the number
/// would land on the wrong zoom (see [LoupeZoom.scaleForMode]).

abstract class _$LoupeZoomLevel
    extends $Notifier<({double customScale, LoupeZoomMode mode})> {
  ({double customScale, LoupeZoomMode mode}) build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              ({double customScale, LoupeZoomMode mode}),
              ({double customScale, LoupeZoomMode mode})
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                ({double customScale, LoupeZoomMode mode}),
                ({double customScale, LoupeZoomMode mode})
              >,
              ({double customScale, LoupeZoomMode mode}),
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Holds the open folders as tabs. Deliberately "dumb" — it never reaches into
/// the live [CullController]/filter providers; the page orchestrates saving and
/// restoring per-tab view state around [activate]/[openImport]/[close].

@ProviderFor(Workspace)
final workspaceProvider = WorkspaceProvider._();

/// Holds the open folders as tabs. Deliberately "dumb" — it never reaches into
/// the live [CullController]/filter providers; the page orchestrates saving and
/// restoring per-tab view state around [activate]/[openImport]/[close].
final class WorkspaceProvider
    extends $NotifierProvider<Workspace, WorkspaceState> {
  /// Holds the open folders as tabs. Deliberately "dumb" — it never reaches into
  /// the live [CullController]/filter providers; the page orchestrates saving and
  /// restoring per-tab view state around [activate]/[openImport]/[close].
  WorkspaceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspaceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workspaceHash();

  @$internal
  @override
  Workspace create() => Workspace();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkspaceState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkspaceState>(value),
    );
  }
}

String _$workspaceHash() => r'216cf4a47cff3f2d73acc8624def21aa7be386f1';

/// Holds the open folders as tabs. Deliberately "dumb" — it never reaches into
/// the live [CullController]/filter providers; the page orchestrates saving and
/// restoring per-tab view state around [activate]/[openImport]/[close].

abstract class _$Workspace extends $Notifier<WorkspaceState> {
  WorkspaceState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<WorkspaceState, WorkspaceState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<WorkspaceState, WorkspaceState>,
              WorkspaceState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Whether the preview providers retry a transient null. **Defaults to false**
/// so the retry's back-off timers never linger in widget tests (which render
/// the grid with a stub cache that always misses); `main()` overrides it to
/// true so production actually retries. A plain seed provider — there's nothing
/// to toggle at runtime.

@ProviderFor(previewRetryEnabled)
final previewRetryEnabledProvider = PreviewRetryEnabledProvider._();

/// Whether the preview providers retry a transient null. **Defaults to false**
/// so the retry's back-off timers never linger in widget tests (which render
/// the grid with a stub cache that always misses); `main()` overrides it to
/// true so production actually retries. A plain seed provider — there's nothing
/// to toggle at runtime.

final class PreviewRetryEnabledProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Whether the preview providers retry a transient null. **Defaults to false**
  /// so the retry's back-off timers never linger in widget tests (which render
  /// the grid with a stub cache that always misses); `main()` overrides it to
  /// true so production actually retries. A plain seed provider — there's nothing
  /// to toggle at runtime.
  PreviewRetryEnabledProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'previewRetryEnabledProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$previewRetryEnabledHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return previewRetryEnabled(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$previewRetryEnabledHash() =>
    r'aa1cb8c67f79654fbf97c2f1ad1c8072965284eb';

/// Decoded preview bytes for [path]. Auto-dispose: when the cell scrolls
/// off-screen the provider is disposed, which cancels the still-queued pool job
/// so the visible cells jump ahead (`BUILD_PLAN.md` §2).
///
/// Retries a *transient* null (a cold Dropbox/network file that tripped the
/// pool's watchdog before it hydrated) so the cell doesn't stay blank forever
/// after a later pass fills the cache — see [retryPreview].

@ProviderFor(thumbnail)
final thumbnailProvider = ThumbnailFamily._();

/// Decoded preview bytes for [path]. Auto-dispose: when the cell scrolls
/// off-screen the provider is disposed, which cancels the still-queued pool job
/// so the visible cells jump ahead (`BUILD_PLAN.md` §2).
///
/// Retries a *transient* null (a cold Dropbox/network file that tripped the
/// pool's watchdog before it hydrated) so the cell doesn't stay blank forever
/// after a later pass fills the cache — see [retryPreview].

final class ThumbnailProvider
    extends
        $FunctionalProvider<
          AsyncValue<Uint8List?>,
          Uint8List?,
          FutureOr<Uint8List?>
        >
    with $FutureModifier<Uint8List?>, $FutureProvider<Uint8List?> {
  /// Decoded preview bytes for [path]. Auto-dispose: when the cell scrolls
  /// off-screen the provider is disposed, which cancels the still-queued pool job
  /// so the visible cells jump ahead (`BUILD_PLAN.md` §2).
  ///
  /// Retries a *transient* null (a cold Dropbox/network file that tripped the
  /// pool's watchdog before it hydrated) so the cell doesn't stay blank forever
  /// after a later pass fills the cache — see [retryPreview].
  ThumbnailProvider._({
    required ThumbnailFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'thumbnailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$thumbnailHash();

  @override
  String toString() {
    return r'thumbnailProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Uint8List?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Uint8List?> create(Ref ref) {
    final argument = this.argument as String;
    return thumbnail(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ThumbnailProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$thumbnailHash() => r'd329e8f7d4d77d5e17e6717968506c100e75485c';

/// Decoded preview bytes for [path]. Auto-dispose: when the cell scrolls
/// off-screen the provider is disposed, which cancels the still-queued pool job
/// so the visible cells jump ahead (`BUILD_PLAN.md` §2).
///
/// Retries a *transient* null (a cold Dropbox/network file that tripped the
/// pool's watchdog before it hydrated) so the cell doesn't stay blank forever
/// after a later pass fills the cache — see [retryPreview].

final class ThumbnailFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Uint8List?>, String> {
  ThumbnailFamily._()
    : super(
        retry: null,
        name: r'thumbnailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Decoded preview bytes for [path]. Auto-dispose: when the cell scrolls
  /// off-screen the provider is disposed, which cancels the still-queued pool job
  /// so the visible cells jump ahead (`BUILD_PLAN.md` §2).
  ///
  /// Retries a *transient* null (a cold Dropbox/network file that tripped the
  /// pool's watchdog before it hydrated) so the cell doesn't stay blank forever
  /// after a later pass fills the cache — see [retryPreview].

  ThumbnailProvider call(String path) =>
      ThumbnailProvider._(argument: path, from: this);

  @override
  String toString() => r'thumbnailProvider';
}

/// Screen-res loupe preview bytes for [path] (scaled to the display's pixel
/// long edge), for the fullscreen loupe view. Auto-dispose: closing the loupe
/// (or blitting past a neighbour) cancels the still-queued pool job so the
/// photo on screen renders first.

@ProviderFor(loupePreview)
final loupePreviewProvider = LoupePreviewFamily._();

/// Screen-res loupe preview bytes for [path] (scaled to the display's pixel
/// long edge), for the fullscreen loupe view. Auto-dispose: closing the loupe
/// (or blitting past a neighbour) cancels the still-queued pool job so the
/// photo on screen renders first.

final class LoupePreviewProvider
    extends
        $FunctionalProvider<
          AsyncValue<Uint8List?>,
          Uint8List?,
          FutureOr<Uint8List?>
        >
    with $FutureModifier<Uint8List?>, $FutureProvider<Uint8List?> {
  /// Screen-res loupe preview bytes for [path] (scaled to the display's pixel
  /// long edge), for the fullscreen loupe view. Auto-dispose: closing the loupe
  /// (or blitting past a neighbour) cancels the still-queued pool job so the
  /// photo on screen renders first.
  LoupePreviewProvider._({
    required LoupePreviewFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'loupePreviewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$loupePreviewHash();

  @override
  String toString() {
    return r'loupePreviewProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Uint8List?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Uint8List?> create(Ref ref) {
    final argument = this.argument as String;
    return loupePreview(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is LoupePreviewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$loupePreviewHash() => r'5f6fc49f209d5cea247c6b20f209e70b911b59e0';

/// Screen-res loupe preview bytes for [path] (scaled to the display's pixel
/// long edge), for the fullscreen loupe view. Auto-dispose: closing the loupe
/// (or blitting past a neighbour) cancels the still-queued pool job so the
/// photo on screen renders first.

final class LoupePreviewFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Uint8List?>, String> {
  LoupePreviewFamily._()
    : super(
        retry: null,
        name: r'loupePreviewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Screen-res loupe preview bytes for [path] (scaled to the display's pixel
  /// long edge), for the fullscreen loupe view. Auto-dispose: closing the loupe
  /// (or blitting past a neighbour) cancels the still-queued pool job so the
  /// photo on screen renders first.

  LoupePreviewProvider call(String path) =>
      LoupePreviewProvider._(argument: path, from: this);

  @override
  String toString() => r'loupePreviewProvider';
}

/// Full-resolution source bytes for [path] — the original bitmap or a RAW's
/// full embedded JPEG — loaded lazily only when the loupe zooms in, so 100% is
/// true 1:1 pixel-peeping instead of an upscaled preview. Auto-dispose: leaving
/// the photo (or the loupe) cancels the pending decode.

@ProviderFor(loupeFullPreview)
final loupeFullPreviewProvider = LoupeFullPreviewFamily._();

/// Full-resolution source bytes for [path] — the original bitmap or a RAW's
/// full embedded JPEG — loaded lazily only when the loupe zooms in, so 100% is
/// true 1:1 pixel-peeping instead of an upscaled preview. Auto-dispose: leaving
/// the photo (or the loupe) cancels the pending decode.

final class LoupeFullPreviewProvider
    extends
        $FunctionalProvider<
          AsyncValue<Uint8List?>,
          Uint8List?,
          FutureOr<Uint8List?>
        >
    with $FutureModifier<Uint8List?>, $FutureProvider<Uint8List?> {
  /// Full-resolution source bytes for [path] — the original bitmap or a RAW's
  /// full embedded JPEG — loaded lazily only when the loupe zooms in, so 100% is
  /// true 1:1 pixel-peeping instead of an upscaled preview. Auto-dispose: leaving
  /// the photo (or the loupe) cancels the pending decode.
  LoupeFullPreviewProvider._({
    required LoupeFullPreviewFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'loupeFullPreviewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$loupeFullPreviewHash();

  @override
  String toString() {
    return r'loupeFullPreviewProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Uint8List?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Uint8List?> create(Ref ref) {
    final argument = this.argument as String;
    return loupeFullPreview(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is LoupeFullPreviewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$loupeFullPreviewHash() => r'8081e42d44c396896cdd6041028a67d0962f5286';

/// Full-resolution source bytes for [path] — the original bitmap or a RAW's
/// full embedded JPEG — loaded lazily only when the loupe zooms in, so 100% is
/// true 1:1 pixel-peeping instead of an upscaled preview. Auto-dispose: leaving
/// the photo (or the loupe) cancels the pending decode.

final class LoupeFullPreviewFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Uint8List?>, String> {
  LoupeFullPreviewFamily._()
    : super(
        retry: null,
        name: r'loupeFullPreviewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Full-resolution source bytes for [path] — the original bitmap or a RAW's
  /// full embedded JPEG — loaded lazily only when the loupe zooms in, so 100% is
  /// true 1:1 pixel-peeping instead of an upscaled preview. Auto-dispose: leaving
  /// the photo (or the loupe) cancels the pending decode.

  LoupeFullPreviewProvider call(String path) =>
      LoupeFullPreviewProvider._(argument: path, from: this);

  @override
  String toString() => r'loupeFullPreviewProvider';
}

/// Owns grid focus/selection and writes cull marks straight to the read model
/// (the reactive `photos` stream reflects them immediately).
///
/// keepAlive: focus/selection is session state, and it must survive the async
/// gaps inside a mark write (DB + sidecar) without the Ref being disposed.

@ProviderFor(CullController)
final cullControllerProvider = CullControllerProvider._();

/// Owns grid focus/selection and writes cull marks straight to the read model
/// (the reactive `photos` stream reflects them immediately).
///
/// keepAlive: focus/selection is session state, and it must survive the async
/// gaps inside a mark write (DB + sidecar) without the Ref being disposed.
final class CullControllerProvider
    extends $NotifierProvider<CullController, CullSelection> {
  /// Owns grid focus/selection and writes cull marks straight to the read model
  /// (the reactive `photos` stream reflects them immediately).
  ///
  /// keepAlive: focus/selection is session state, and it must survive the async
  /// gaps inside a mark write (DB + sidecar) without the Ref being disposed.
  CullControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cullControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cullControllerHash();

  @$internal
  @override
  CullController create() => CullController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CullSelection value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CullSelection>(value),
    );
  }
}

String _$cullControllerHash() => r'1c53480a4b1f782c8430147f748191c37f8ac178';

/// Owns grid focus/selection and writes cull marks straight to the read model
/// (the reactive `photos` stream reflects them immediately).
///
/// keepAlive: focus/selection is session state, and it must survive the async
/// gaps inside a mark write (DB + sidecar) without the Ref being disposed.

abstract class _$CullController extends $Notifier<CullSelection> {
  CullSelection build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<CullSelection, CullSelection>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CullSelection, CullSelection>,
              CullSelection,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
