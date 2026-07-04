import 'dart:typed_data';

/// Produces preview bytes for a photo, or null when they can't (yet) be made.
typedef PreviewExtract = Future<Uint8List?> Function();

/// Default back-off between retries — short at first (a hydrated file appears
/// almost immediately), stretching out so a genuinely cold source still gets a
/// chance without hammering the pool.
const List<Duration> kPreviewRetryDelays = [
  Duration(milliseconds: 500),
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
];

/// Runs [extract], retrying while it returns null, to ride out a *transient*
/// miss: a cold network/Dropbox file that isn't hydrated yet can blow past the
/// preview pool's watchdog and get abandoned, yielding a spurious null. The
/// cache never stores that null, so a later attempt usually succeeds once the
/// file is local — but the cell's (still-visible) provider would otherwise
/// settle on the first null forever and stay blank even after the cache fills.
///
/// Retries bail the instant [isCancelled] returns true (the cell scrolled off
/// and its `CancelToken` fired), so a genuinely empty source — e.g. a Linux
/// video with no poster frame, passed with [retryable] false — can't spin. The
/// attempt count is bounded by [delays] regardless.
///
/// [sleep] is injectable so tests don't wait real time; it defaults to
/// [Future.delayed].
Future<Uint8List?> retryPreview(
  PreviewExtract extract, {
  required bool Function() isCancelled,
  bool retryable = true,
  List<Duration> delays = kPreviewRetryDelays,
  Future<void> Function(Duration)? sleep,
}) async {
  final wait = sleep ?? Future<void>.delayed;
  var bytes = await extract();
  if (bytes != null || !retryable) return bytes;
  for (final delay in delays) {
    if (isCancelled()) return null;
    await wait(delay);
    if (isCancelled()) return null;
    bytes = await extract();
    if (bytes != null) return bytes;
  }
  return bytes;
}
