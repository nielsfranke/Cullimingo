import 'dart:async';

import 'package:cullimingo/features/delivery/data/delivery_client.dart';
import 'package:path/path.dart' as p;

/// One file to deliver: the rendered export on disk and its remote name.
class DeliveryItem {
  /// Creates an item.
  const DeliveryItem({required this.localPath, required this.remoteName});

  /// Absolute path of the rendered file.
  final String localPath;

  /// Filename on the server (inside the server's remote dir).
  final String remoteName;
}

/// What happened to one delivered file.
class DeliveryResult {
  /// Creates a result; [error] null means delivered.
  const DeliveryResult({required this.item, this.error});

  /// The file this result is about.
  final DeliveryItem item;

  /// The failure message, or null when the upload succeeded.
  final String? error;

  /// Whether the file reached the server.
  bool get ok => error == null;
}

/// A progress tick: one [last] result, [done] of [total] finished — the same
/// shape as `ExportProgress`, so the export page can show both phases alike.
class DeliveryProgress {
  /// Creates a progress tick.
  const DeliveryProgress({
    required this.done,
    required this.total,
    required this.last,
  });

  /// Files attempted so far.
  final int done;

  /// Total files in the run.
  final int total;

  /// The most recent result.
  final DeliveryResult last;
}

/// Aggregate outcome of a delivery run.
class DeliverySummary {
  /// Creates a summary over [results].
  const DeliverySummary(this.results);

  /// Per-file results, in order.
  final List<DeliveryResult> results;

  /// Files that reached the server.
  int get delivered => results.where((r) => r.ok).length;

  /// Files that did not.
  List<DeliveryResult> get failures => [
    for (final r in results)
      if (!r.ok) r,
  ];

  /// Whether every file was delivered.
  bool get allOk => results.isNotEmpty && results.every((r) => r.ok);
}

/// Turns rendered export paths (relative to [localRoot], possibly nested by a
/// dated filename template) into wire-friendly flat [DeliveryItem]s: the
/// basename — unless several files share one, then those keep their full
/// path with `/` flattened to `_` so nothing gets overwritten server-side.
List<DeliveryItem> deliveryItemsFor({
  required String localRoot,
  required List<String> relPaths,
}) {
  final nameCounts = <String, int>{};
  for (final rel in relPaths) {
    nameCounts.update(p.basename(rel), (n) => n + 1, ifAbsent: () => 1);
  }
  return [
    for (final rel in relPaths)
      DeliveryItem(
        localPath: p.join(localRoot, rel),
        remoteName: nameCounts[p.basename(rel)]! > 1
            ? rel.replaceAll('/', '_')
            : p.basename(rel),
      ),
  ];
}

/// Uploads [items] over one connection built by [connectClient], emitting a
/// [DeliveryProgress] per file (`BUILD_PLAN.md` §11).
///
/// Each file gets up to [attemptsPerFile] tries; a failed try tears the
/// connection down and reconnects (pausing [retryDelay] between tries), so a
/// dropped control connection heals itself. When even the *connection*
/// cannot be re-established on a file's last try, the remaining files are
/// failed immediately with the same error instead of timing out one by one.
/// Cancelling the subscription stops before the next file.
///
/// Sequential on purpose: wire uploads are bandwidth-bound, and agency
/// servers are famously grumpy about parallel logins.
Stream<DeliveryProgress> runDelivery({
  required List<DeliveryItem> items,
  required DeliveryClient Function() connectClient,
  required String remoteDir,
  int attemptsPerFile = 3,
  Duration retryDelay = const Duration(milliseconds: 500),
}) {
  final controller = StreamController<DeliveryProgress>();
  var stopped = false;

  Future<void> run() async {
    DeliveryClient? client;
    var done = 0;

    Future<DeliveryClient> ensureConnected() async {
      if (client != null) return client!;
      final fresh = connectClient();
      await fresh.connect();
      await fresh.ensureRemoteDir(remoteDir);
      return client = fresh;
    }

    void tick(DeliveryResult result) {
      done++;
      if (!controller.isClosed) {
        controller.add(
          DeliveryProgress(done: done, total: items.length, last: result),
        );
      }
    }

    String? abortError;
    for (final item in items) {
      if (stopped) break;
      if (abortError != null) {
        tick(DeliveryResult(item: item, error: abortError));
        continue;
      }
      String? lastError;
      for (var attempt = 1; attempt <= attemptsPerFile; attempt++) {
        var connected = false;
        try {
          final c = await ensureConnected();
          connected = true;
          await c.uploadFile(item.localPath, item.remoteName);
          lastError = null;
          break;
        } on DeliveryException catch (e) {
          lastError = e.message;
        } on Object catch (e) {
          lastError = '$e';
        }
        // A failed try leaves the connection in an unknown state — reconnect.
        await client?.close();
        client = null;
        final lastAttempt = attempt == attemptsPerFile;
        if (!connected && lastAttempt) abortError = lastError;
        if (!lastAttempt && !stopped) {
          await Future<void>.delayed(retryDelay);
        }
      }
      tick(DeliveryResult(item: item, error: lastError));
    }
    await client?.close();
    if (!controller.isClosed) await controller.close();
  }

  controller
    ..onListen = () {
      unawaited(run());
    }
    ..onCancel = () => stopped = true;

  return controller.stream;
}
