import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A lightweight [ProviderObserver] that keeps a bounded ring buffer of recent
/// provider activity (`BUILD_PLAN.md` §8 diagnostics). It does nothing on its
/// own — when a "setState/markNeedsBuild called during build" error fires, the
/// logger dumps [recentDump] so we can see which provider cascade triggered it
/// (the error itself only names the widget, not the trigger).
///
/// High-frequency preview/thumbnail updates are skipped so the buffer stays
/// meaningful; everything else (photos, groups, filter, import switches) is
/// recorded with a millisecond timestamp.
base class ProviderDiagnostics extends ProviderObserver {
  /// Creates the diagnostics observer (install on the root `ProviderScope`).
  ProviderDiagnostics();

  static const int _maxEntries = 40;
  final List<String> _recent = [];

  // Substrings of providers that update too often to be useful here.
  static const List<String> _noisy = [
    'thumbnail',
    'loupePreview',
    'previewCache',
  ];

  void _record(String event, ProviderObserverContext context) {
    final label = context.provider.toString();
    for (final n in _noisy) {
      if (label.contains(n)) return;
    }
    final t = DateTime.now().toIso8601String().substring(
      11,
      23,
    ); // HH:mm:ss.mmm
    _recent.add('$t  $event  $label');
    if (_recent.length > _maxEntries) _recent.removeAt(0);
  }

  /// The recent provider activity, oldest first.
  String recentDump() =>
      _recent.isEmpty ? '(no recorded provider activity)' : _recent.join('\n');

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) =>
      _record('add', context);

  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) => _record('update', context);

  @override
  void didDisposeProvider(ProviderObserverContext context) =>
      _record('dispose', context);

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) => _record('FAIL($error)', context);
}

/// The app-wide diagnostics observer — install it on the root `ProviderScope`
/// and dump [ProviderDiagnostics.recentDump] from the error logger.
final ProviderDiagnostics appProviderDiagnostics = ProviderDiagnostics();
