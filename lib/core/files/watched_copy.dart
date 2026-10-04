import 'dart:async';
import 'dart:isolate';

import 'package:cullimingo/core/files/verified_copy.dart';

/// How long a copy may go without any progress (no chunk read, written or
/// hashed) before it's given up on. Generous: a spun-down drive takes ~10 s
/// to wake, and a network share may pause for a while and recover.
const Duration kCopyStallTimeout = Duration(seconds: 60);

/// Message for a copy given up on by [watchedCopy]'s stall watchdog.
const String kCopyStalledMessage =
    'Stopped responding (drive disconnected or network share hung?)';

/// Message for a copy abandoned because the run was cancelled.
const String kCopyAbandonedMessage =
    'Cancelled mid-copy — check this file before relying on it';

/// Runs [verifiedCopy] on its own isolate, giving up when it hangs.
///
/// Blocking file I/O can't be interrupted: on a hard-mounted NAS that drops,
/// a read or write simply never returns, and the import that awaited it
/// used to freeze for good (Cancel couldn't help either — it waits for
/// copies in flight). The copy now sends a heartbeat as it makes progress;
/// after [stallTimeout] without one, or once [abandon] completes (a
/// cancelled run), the isolate is killed and the file reported as an
/// [CopyOutcome.error]. A thread stuck inside the kernel may linger until
/// the OS gives up on the mount, but the run no longer waits for it. A
/// killed copy leaves at most a hidden part file behind, never a file under
/// its real name that wasn't verified first.
Future<CopyResult> watchedCopy({
  required String source,
  required List<String> destinations,
  bool verify = true,
  Set<String> alwaysVerify = const {},
  Duration quietPeriod = kSourceQuietPeriod,
  Map<String, String> volumeGuards = const {},
  Duration stallTimeout = kCopyStallTimeout,
  Future<void>? abandon,
}) async {
  final port = ReceivePort();
  final done = Completer<CopyResult>();
  Isolate? isolate;
  Timer? watchdog;

  void finish(CopyResult result) {
    if (done.isCompleted) return;
    watchdog?.cancel();
    port.close();
    isolate?.kill(priority: Isolate.immediate);
    done.complete(result);
  }

  CopyResult failed(String message) => CopyResult(
    source: source,
    outcome: CopyOutcome.error,
    message: message,
  );

  void arm() {
    watchdog?.cancel();
    watchdog = Timer(stallTimeout, () => finish(failed(kCopyStalledMessage)));
  }

  port.listen((message) {
    switch (message) {
      case CopyResult():
        finish(message);
      case List<Object?>(): // onError: [error, stack]
        finish(failed('${message.firstOrNull}'));
      case null: // onExit without a result
        finish(failed('Copy stopped unexpectedly'));
      default: // heartbeat
        arm();
    }
  });
  unawaited(abandon?.then((_) => finish(failed(kCopyAbandonedMessage))));

  arm();
  try {
    isolate = await Isolate.spawn(
      _copyEntry,
      _CopyJob(
        reply: port.sendPort,
        source: source,
        destinations: destinations,
        verify: verify,
        alwaysVerify: alwaysVerify,
        quietPeriod: quietPeriod,
        volumeGuards: volumeGuards,
      ),
      onExit: port.sendPort,
      onError: port.sendPort,
    );
    // Abandoned or timed out while the isolate was still starting.
    if (done.isCompleted) isolate.kill(priority: Isolate.immediate);
  } on Object catch (e) {
    finish(failed('$e'));
  }
  return done.future;
}

class _CopyJob {
  const _CopyJob({
    required this.reply,
    required this.source,
    required this.destinations,
    required this.verify,
    required this.alwaysVerify,
    required this.quietPeriod,
    required this.volumeGuards,
  });

  final SendPort reply;
  final String source;
  final List<String> destinations;
  final bool verify;
  final Set<String> alwaysVerify;
  final Duration quietPeriod;
  final Map<String, String> volumeGuards;
}

Future<void> _copyEntry(_CopyJob job) async {
  // Throttled: a heartbeat per chunk would flood the port on a fast SSD.
  final sinceBeat = Stopwatch()..start();
  void beat() {
    if (sinceBeat.elapsedMilliseconds < 250) return;
    sinceBeat.reset();
    job.reply.send(true);
  }

  final result = await verifiedCopy(
    source: job.source,
    destinations: job.destinations,
    verify: job.verify,
    alwaysVerify: job.alwaysVerify,
    quietPeriod: job.quietPeriod,
    volumeGuards: job.volumeGuards,
    onProgress: beat,
  );
  job.reply.send(result);
}
