// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notices_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The single app-wide notification surface (`BUILD_PLAN.md` §7), as state:
/// the page's bottom bar watches this, and long-running jobs (which outlive
/// any one page build — see `cull_job_runner.dart`) report through it without
/// holding a `BuildContext`. Transient messages (info/success without
/// actions) auto-dismiss; warnings and actionable notices stay until
/// dismissed. Null = nothing showing.

@ProviderFor(NoticesController)
final noticesControllerProvider = NoticesControllerProvider._();

/// The single app-wide notification surface (`BUILD_PLAN.md` §7), as state:
/// the page's bottom bar watches this, and long-running jobs (which outlive
/// any one page build — see `cull_job_runner.dart`) report through it without
/// holding a `BuildContext`. Transient messages (info/success without
/// actions) auto-dismiss; warnings and actionable notices stay until
/// dismissed. Null = nothing showing.
final class NoticesControllerProvider
    extends $NotifierProvider<NoticesController, Notice?> {
  /// The single app-wide notification surface (`BUILD_PLAN.md` §7), as state:
  /// the page's bottom bar watches this, and long-running jobs (which outlive
  /// any one page build — see `cull_job_runner.dart`) report through it without
  /// holding a `BuildContext`. Transient messages (info/success without
  /// actions) auto-dismiss; warnings and actionable notices stay until
  /// dismissed. Null = nothing showing.
  NoticesControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'noticesControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$noticesControllerHash();

  @$internal
  @override
  NoticesController create() => NoticesController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Notice? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Notice?>(value),
    );
  }
}

String _$noticesControllerHash() => r'bd3fda69c0bfb62da9405bbd102af0dd385fcc27';

/// The single app-wide notification surface (`BUILD_PLAN.md` §7), as state:
/// the page's bottom bar watches this, and long-running jobs (which outlive
/// any one page build — see `cull_job_runner.dart`) report through it without
/// holding a `BuildContext`. Transient messages (info/success without
/// actions) auto-dismiss; warnings and actionable notices stay until
/// dismissed. Null = nothing showing.

abstract class _$NoticesController extends $Notifier<Notice?> {
  Notice? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Notice?, Notice?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Notice?, Notice?>,
              Notice?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
