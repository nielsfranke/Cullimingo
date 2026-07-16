// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cull_job_runner.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The one long-lived owner of every non-modal background job: export,
/// delivered export (+ its retry), copy/move, ContactSheet send/pull and the
/// find-similar hashing pass.
///
/// This state used to live in the page's widget State ("plain objects so a
/// running loop can still poll them after the page is disposed") — a running
/// job must survive page rebuilds, so it belongs in a `keepAlive` provider,
/// not a `State` object. Progress still flows through
/// [backgroundJobsProvider] (the floating cards) and outcomes through
/// [NoticesController]; the page keeps only the dialogs that *start* jobs.

@ProviderFor(cullJobRunner)
final cullJobRunnerProvider = CullJobRunnerProvider._();

/// The one long-lived owner of every non-modal background job: export,
/// delivered export (+ its retry), copy/move, ContactSheet send/pull and the
/// find-similar hashing pass.
///
/// This state used to live in the page's widget State ("plain objects so a
/// running loop can still poll them after the page is disposed") — a running
/// job must survive page rebuilds, so it belongs in a `keepAlive` provider,
/// not a `State` object. Progress still flows through
/// [backgroundJobsProvider] (the floating cards) and outcomes through
/// [NoticesController]; the page keeps only the dialogs that *start* jobs.

final class CullJobRunnerProvider
    extends $FunctionalProvider<CullJobRunner, CullJobRunner, CullJobRunner>
    with $Provider<CullJobRunner> {
  /// The one long-lived owner of every non-modal background job: export,
  /// delivered export (+ its retry), copy/move, ContactSheet send/pull and the
  /// find-similar hashing pass.
  ///
  /// This state used to live in the page's widget State ("plain objects so a
  /// running loop can still poll them after the page is disposed") — a running
  /// job must survive page rebuilds, so it belongs in a `keepAlive` provider,
  /// not a `State` object. Progress still flows through
  /// [backgroundJobsProvider] (the floating cards) and outcomes through
  /// [NoticesController]; the page keeps only the dialogs that *start* jobs.
  CullJobRunnerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cullJobRunnerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cullJobRunnerHash();

  @$internal
  @override
  $ProviderElement<CullJobRunner> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CullJobRunner create(Ref ref) {
    return cullJobRunner(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CullJobRunner value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CullJobRunner>(value),
    );
  }
}

String _$cullJobRunnerHash() => r'9f7feccaf601bbb05e80148107aefe06c956a8e3';
