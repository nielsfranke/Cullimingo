// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inspector_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether the read-only metadata inspector side panel is open (Phase 8).
/// Session state — not persisted; a panel toggle need not survive relaunch.

@ProviderFor(InspectorOpen)
final inspectorOpenProvider = InspectorOpenProvider._();

/// Whether the read-only metadata inspector side panel is open (Phase 8).
/// Session state — not persisted; a panel toggle need not survive relaunch.
final class InspectorOpenProvider
    extends $NotifierProvider<InspectorOpen, bool> {
  /// Whether the read-only metadata inspector side panel is open (Phase 8).
  /// Session state — not persisted; a panel toggle need not survive relaunch.
  InspectorOpenProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'inspectorOpenProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$inspectorOpenHash();

  @$internal
  @override
  InspectorOpen create() => InspectorOpen();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$inspectorOpenHash() => r'b56f0f66c54588b79d2509faa88f4476854bf803';

/// Whether the read-only metadata inspector side panel is open (Phase 8).
/// Session state — not persisted; a panel toggle need not survive relaunch.

abstract class _$InspectorOpen extends $Notifier<bool> {
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

/// EXIF detail for the file at [path], read in a background isolate. Keyed by
/// path so changing focus re-reads; auto-dispose frees it when focus moves on
/// or the panel closes.

@ProviderFor(focusedExif)
final focusedExifProvider = FocusedExifFamily._();

/// EXIF detail for the file at [path], read in a background isolate. Keyed by
/// path so changing focus re-reads; auto-dispose frees it when focus moves on
/// or the panel closes.

final class FocusedExifProvider
    extends
        $FunctionalProvider<
          AsyncValue<ExifDetail>,
          ExifDetail,
          FutureOr<ExifDetail>
        >
    with $FutureModifier<ExifDetail>, $FutureProvider<ExifDetail> {
  /// EXIF detail for the file at [path], read in a background isolate. Keyed by
  /// path so changing focus re-reads; auto-dispose frees it when focus moves on
  /// or the panel closes.
  FocusedExifProvider._({
    required FocusedExifFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'focusedExifProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$focusedExifHash();

  @override
  String toString() {
    return r'focusedExifProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<ExifDetail> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<ExifDetail> create(Ref ref) {
    final argument = this.argument as String;
    return focusedExif(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is FocusedExifProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$focusedExifHash() => r'7bbfc47e36caf82a6414dbeb9841d228eacd6d49';

/// EXIF detail for the file at [path], read in a background isolate. Keyed by
/// path so changing focus re-reads; auto-dispose frees it when focus moves on
/// or the panel closes.

final class FocusedExifFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<ExifDetail>, String> {
  FocusedExifFamily._()
    : super(
        retry: null,
        name: r'focusedExifProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// EXIF detail for the file at [path], read in a background isolate. Keyed by
  /// path so changing focus re-reads; auto-dispose frees it when focus moves on
  /// or the panel closes.

  FocusedExifProvider call(String path) =>
      FocusedExifProvider._(argument: path, from: this);

  @override
  String toString() => r'focusedExifProvider';
}
