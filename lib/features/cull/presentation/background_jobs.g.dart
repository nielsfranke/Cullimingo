// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'background_jobs.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Holds the progress of the page's non-modal background jobs (export,
/// ContactSheet send, find-similar). Pure state transitions — the runner drives
/// these and the page watches them to render the floating progress cards.
///
/// Every `tick`/`update` is a no-op when its slot is null, so a late progress
/// event that arrives after the job was cancelled (its slot cleared) can never
/// resurrect the card.

@ProviderFor(BackgroundJobs)
final backgroundJobsProvider = BackgroundJobsProvider._();

/// Holds the progress of the page's non-modal background jobs (export,
/// ContactSheet send, find-similar). Pure state transitions — the runner drives
/// these and the page watches them to render the floating progress cards.
///
/// Every `tick`/`update` is a no-op when its slot is null, so a late progress
/// event that arrives after the job was cancelled (its slot cleared) can never
/// resurrect the card.
final class BackgroundJobsProvider
    extends $NotifierProvider<BackgroundJobs, BackgroundJobsState> {
  /// Holds the progress of the page's non-modal background jobs (export,
  /// ContactSheet send, find-similar). Pure state transitions — the runner drives
  /// these and the page watches them to render the floating progress cards.
  ///
  /// Every `tick`/`update` is a no-op when its slot is null, so a late progress
  /// event that arrives after the job was cancelled (its slot cleared) can never
  /// resurrect the card.
  BackgroundJobsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backgroundJobsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backgroundJobsHash();

  @$internal
  @override
  BackgroundJobs create() => BackgroundJobs();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BackgroundJobsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BackgroundJobsState>(value),
    );
  }
}

String _$backgroundJobsHash() => r'4841eee98d63238d2831bab6551e3e10a452f7da';

/// Holds the progress of the page's non-modal background jobs (export,
/// ContactSheet send, find-similar). Pure state transitions — the runner drives
/// these and the page watches them to render the floating progress cards.
///
/// Every `tick`/`update` is a no-op when its slot is null, so a late progress
/// event that arrives after the job was cancelled (its slot cleared) can never
/// resurrect the card.

abstract class _$BackgroundJobs extends $Notifier<BackgroundJobsState> {
  BackgroundJobsState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<BackgroundJobsState, BackgroundJobsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BackgroundJobsState, BackgroundJobsState>,
              BackgroundJobsState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
