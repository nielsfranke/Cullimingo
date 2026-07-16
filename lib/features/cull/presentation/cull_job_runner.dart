import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/files/open_external.dart';
import 'package:cullimingo/core/files/verified_copy.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/core/secrets/secret_store.dart';
import 'package:cullimingo/features/cull/data/phash_compute.dart';
import 'package:cullimingo/features/cull/domain/duplicate_groups.dart';
import 'package:cullimingo/features/cull/domain/perceptual_hash.dart';
import 'package:cullimingo/features/cull/domain/similarity_sensitivity.dart';
import 'package:cullimingo/features/cull/presentation/background_jobs.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/notices_provider.dart';
import 'package:cullimingo/features/cull/presentation/widgets/notice_bar.dart';
import 'package:cullimingo/features/delivery/data/delivery_client.dart';
import 'package:cullimingo/features/delivery/data/delivery_uploader.dart';
import 'package:cullimingo/features/delivery/domain/delivery_server.dart';
import 'package:cullimingo/features/export/data/export_service.dart';
import 'package:cullimingo/features/export/domain/export_plan.dart';
import 'package:cullimingo/features/export/presentation/export_dialog.dart';
import 'package:cullimingo/features/filter/presentation/filter_providers.dart';
import 'package:cullimingo/features/handoff/data/contactsheet_client.dart';
import 'package:cullimingo/features/handoff/data/transfer_service.dart';
import 'package:cullimingo/features/handoff/domain/pull_collections.dart';
import 'package:cullimingo/features/handoff/domain/pull_marks.dart';
import 'package:cullimingo/features/handoff/presentation/contactsheet_dialog.dart';
import 'package:cullimingo/features/handoff/presentation/transfer_dialog.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cull_job_runner.g.dart';

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
@Riverpod(keepAlive: true)
CullJobRunner cullJobRunner(Ref ref) {
  final runner = CullJobRunner._(ref);
  // App teardown / test-container disposal: stop the loops so nothing ticks
  // into a disposed container.
  ref.onDispose(runner._shutdown);
  return runner;
}

/// A cancel token for a running background job, flipped by the card's Cancel
/// button and polled by the running loop between ticks/batches.
class _JobCancel {
  bool cancelled = false;
}

/// See [cullJobRunner].
class CullJobRunner {
  CullJobRunner._(this._ref);

  final Ref _ref;

  // Cancels the in-flight export stream.
  StreamSubscription<ExportProgress>? _exportSub;

  // Cancels the in-flight copy/move stream.
  StreamSubscription<TransferProgress>? _transferSub;

  // Cancel token for the in-flight ContactSheet send/pull, polled between
  // ticks/batches.
  _JobCancel? _csCancel;

  // Cancel token for the in-flight delivered export (render + upload).
  _JobCancel? _deliveryCancel;

  // Cancel token for the in-flight find-similar hashing pass.
  _JobCancel? _hashCancel;

  // Failed uploads waiting behind the notice's "Retry failed" action, plus
  // the temp dir their rendered files live in (null when the files are in a
  // kept local folder). Replaced (and its temp dir deleted) when the next
  // delivered export starts.
  ({List<DeliveryItem> items, DeliveryServer server, Directory? tempDir})?
  _failedDelivery;

  BackgroundJobs get _jobs => _ref.read(backgroundJobsProvider.notifier);

  NoticesController get _notices =>
      _ref.read(noticesControllerProvider.notifier);

  void _notify(String message, {NoticeKind kind = NoticeKind.info}) =>
      _notices.notify(message, kind: kind);

  void _shutdown() {
    unawaited(_exportSub?.cancel());
    unawaited(_transferSub?.cancel());
    _csCancel?.cancelled = true;
    _deliveryCancel?.cancelled = true;
    _hashCancel?.cancelled = true;
  }

  /// Runs [request] in the background (non-modal), driving the floating
  /// progress card via [backgroundJobsProvider]. The grid stays interactive
  /// throughout (the render is on isolates; only progress ticks reach the
  /// UI). On done, summarises via the notice bar and optionally opens the
  /// destination folder.
  void runExportJob(ExportRequest request) {
    if (request.server != null) {
      unawaited(_runExportDelivered(request));
      return;
    }
    unawaited(_exportSub?.cancel());
    final results = <ExportResult>[];
    _jobs.startExport(request.plan.length);
    // Kept in _exportSub and cancelled in cancelExport/_shutdown.
    _exportSub =
        runExport(
          plan: request.plan,
          destinationRoot: request.destinationRoot,
          nextToOriginals: request.nextToOriginals,
          subfolder: request.subfolder,
          preset: request.preset,
        ).listen(
          (tick) {
            results.add(tick.last);
            _jobs.tickExport(tick.done);
          },
          onDone: () {
            final summary = ExportSummary(results);
            _jobs.clearExport();
            final failed = summary.failed;
            _notify(
              failed > 0
                  ? 'Exported ${summary.written} photo(s) · $failed failed'
                  : 'Exported ${summary.written} photo(s)',
              kind: failed > 0 ? NoticeKind.warning : NoticeKind.success,
            );
            if (request.openWhenDone && summary.written > 0) {
              // Next-to-originals has no single root — open the first
              // output's folder (beside its source, plus the optional
              // subfolder).
              final target =
                  request.destinationRoot ??
                  (request.plan.isEmpty
                      ? null
                      : p.join(
                          p.dirname(request.plan.first.source),
                          request.subfolder,
                        ));
              if (target != null) unawaited(openExternally(target));
            }
          },
        );
  }

  /// Cancels the in-flight (delivered) export.
  void cancelExport() {
    unawaited(_exportSub?.cancel());
    _exportSub = null;
    _deliveryCancel?.cancelled = true;
    _jobs.clearExport();
    _notify('Export cancelled');
  }

  /// Runs a delivered export (`BUILD_PLAN.md` §11): render via the export
  /// pipeline into the local destination (or a temp dir when no local copy is
  /// kept), then upload to the request's server — one connection, per-file
  /// retries on a reconnect (see [runDelivery]). The floating export card
  /// flips from "Exporting" to "Uploading" between the phases.
  Future<void> _runExportDelivered(ExportRequest request) async {
    final server = request.server!;
    final localRoot = request.destinationRoot;
    _discardFailedDelivery();
    final tempDir = localRoot == null
        ? Directory.systemTemp.createTempSync('cm_delivery')
        : null;
    final root = localRoot ?? tempDir!.path;
    final cancel = _deliveryCancel = _JobCancel();
    var keepTemp = false;
    _jobs.startExport(request.plan.length);
    try {
      // 1. Render to [root] via the export pipeline.
      final rendered = <ExportResult>[];
      await for (final tick in runExport(
        plan: request.plan,
        destinationRoot: root,
        preset: request.preset,
      )) {
        if (cancel.cancelled) return;
        rendered.add(tick.last);
        _jobs.tickExport(tick.done);
      }
      if (cancel.cancelled) return;
      final renderFailed = rendered.where((r) => !r.ok).length;
      final okPaths = [
        for (final r in rendered)
          if (r.ok) r.relPath,
      ];
      if (okPaths.isEmpty) {
        _notify('Nothing was rendered to upload', kind: NoticeKind.warning);
        return;
      }

      // 2. Upload over one connection.
      final summary = await _uploadItems(
        items: deliveryItemsFor(localRoot: root, relPaths: okPaths),
        server: server,
        cancel: cancel,
      );
      if (summary == null) return; // cancelled mid-upload

      keepTemp = _reportDelivery(
        summary,
        server: server,
        renderFailed: renderFailed,
        tempDir: tempDir,
      );
      if (request.openWhenDone && localRoot != null) {
        unawaited(openExternally(localRoot));
      }
    } on Object catch (e) {
      _notify('Delivery failed: $e', kind: NoticeKind.warning);
    } finally {
      if (!keepTemp) _deleteTemp(tempDir);
      _jobs.clearExport();
    }
  }

  /// The notice's "Retry failed" action: re-uploads the stored failures over
  /// a fresh connection; whatever fails again re-arms the same notice.
  Future<void> retryFailedDelivery() async {
    final pending = _failedDelivery;
    if (pending == null) return;
    _failedDelivery = null;
    _notices.dismiss();
    final cancel = _deliveryCancel = _JobCancel();
    var keepTemp = false;
    _jobs.startExport(pending.items.length);
    try {
      final summary = await _uploadItems(
        items: pending.items,
        server: pending.server,
        cancel: cancel,
      );
      if (summary == null) return;
      keepTemp = _reportDelivery(
        summary,
        server: pending.server,
        renderFailed: 0,
        tempDir: pending.tempDir,
      );
    } on Object catch (e) {
      _notify('Delivery failed: $e', kind: NoticeKind.warning);
    } finally {
      if (!keepTemp) _deleteTemp(pending.tempDir);
      _jobs.clearExport();
    }
  }

  /// Uploads [items] to [server] with the export card in "Uploading" mode.
  /// Returns null when [cancel] fired mid-run.
  Future<DeliverySummary?> _uploadItems({
    required List<DeliveryItem> items,
    required DeliveryServer server,
    required _JobCancel cancel,
  }) async {
    final password =
        await _ref
            .read(secretStoreProvider)
            .read(deliveryPasswordKey(server.id)) ??
        '';
    _jobs.updateExport(verb: 'Uploading', done: 0, total: items.length);
    final results = <DeliveryResult>[];
    await for (final tick in runDelivery(
      items: items,
      connectClient: () => createDeliveryClient(server, password),
      remoteDir: server.remoteDir,
    )) {
      if (cancel.cancelled) return null;
      results.add(tick.last);
      _jobs.updateExport(done: tick.done);
    }
    return DeliverySummary(results);
  }

  /// Shows the outcome notice; failures arm the "Retry failed" action (and
  /// keep [tempDir] alive for it). Returns whether the temp dir must survive.
  bool _reportDelivery(
    DeliverySummary summary, {
    required DeliveryServer server,
    required int renderFailed,
    required Directory? tempDir,
  }) {
    final failures = summary.failures;
    final parts = [
      'Delivered ${summary.delivered} photo(s) to ${server.name}',
      if (renderFailed > 0) '$renderFailed failed to render',
      if (failures.isNotEmpty)
        '${failures.length} failed to upload (${failures.first.error})',
    ];
    if (failures.isEmpty) {
      _notify(
        parts.join(' · '),
        kind: renderFailed > 0 ? NoticeKind.warning : NoticeKind.success,
      );
      return false;
    }
    _failedDelivery = (
      items: [for (final f in failures) f.item],
      server: server,
      tempDir: tempDir,
    );
    _notices.show(
      Notice(
        kind: NoticeKind.warning,
        message: parts.join(' · '),
        icon: NoticeKind.warning.icon,
        actions: [
          (
            label: 'Retry failed',
            onTap: () => unawaited(retryFailedDelivery()),
          ),
        ],
      ),
    );
    return tempDir != null;
  }

  /// Drops a stored retry (its files are gone once the temp dir is).
  void _discardFailedDelivery() {
    final pending = _failedDelivery;
    _failedDelivery = null;
    _deleteTemp(pending?.tempDir);
  }

  void _deleteTemp(Directory? dir) {
    if (dir == null) return;
    final path = dir.path;
    // Off the UI isolate: after a delivery/contact-sheet run the temp dir
    // holds hundreds of rendered files — a recursive sync delete janks.
    unawaited(
      Isolate.run(() {
        try {
          Directory(path).deleteSync(recursive: true);
        } on Object {
          // Best effort — a leftover temp dir is harmless.
        }
      }),
    );
  }

  /// Runs [request] in the background (non-modal): the verified copy
  /// (+ delete on move) happens on isolates, only progress ticks reach the
  /// UI, so the grid stays interactive. Summarises via the notice bar and
  /// optionally opens the destination folder.
  Future<void> runTransferJob(TransferRequest request) async {
    unawaited(_transferSub?.cancel());
    final isMove = request.mode == TransferMode.move;
    final plan = await buildTransferPlan(
      request.sources,
      includeSidecars: request.includeSidecars,
    );
    if (plan.isEmpty) return;
    final results = <CopyResult>[];
    _jobs.startTransfer(isMove ? 'Moving' : 'Copying', plan.length);
    // Kept in _transferSub and cancelled in cancelTransfer/_shutdown.
    _transferSub =
        runTransfer(
          plan: plan,
          destinationRoot: request.destinationRoot,
          mode: request.mode,
        ).listen(
          (tick) {
            results.add(tick.last);
            _jobs.tickTransfer(tick.done);
          },
          onDone: () {
            _jobs.clearTransfer();
            final summary = TransferSummary(results);
            final parts = [
              '${isMove ? 'Moved' : 'Copied'} ${summary.transferred} photo(s)',
              if (summary.conflicts > 0)
                '${summary.conflicts} skipped (name in use)',
              if (summary.failed > 0) '${summary.failed} failed',
            ];
            _notify(
              parts.join(' · '),
              kind: summary.failed > 0 || summary.conflicts > 0
                  ? NoticeKind.warning
                  : NoticeKind.success,
            );
            if (request.openWhenDone && summary.transferred > 0) {
              unawaited(openExternally(request.destinationRoot));
            }
          },
        );
  }

  /// Cancels the in-flight copy/move.
  void cancelTransfer() {
    unawaited(_transferSub?.cancel());
    _transferSub = null;
    _jobs.clearTransfer();
    _notify('Transfer cancelled');
  }

  /// Renders [request]'s sources to a temp folder via the export pipeline,
  /// then uploads them into the chosen (or freshly created) ContactSheet
  /// gallery in batches. Non-modal (floating progress card).
  Future<void> runContactSheetSend(ContactSheetRequest request) async {
    final tempDir = Directory.systemTemp.createTempSync('cm_cs_send');
    final client = ContactSheetClient(
      baseUrl: request.baseUrl,
      token: request.token,
    );
    final cancel = _csCancel = _JobCancel();
    _jobs.startContactSheet('Rendering', request.sources.length);
    try {
      // 1. Render to temp via the export pipeline.
      final plan = buildExportPlan(request.sources, request.preset);
      await for (final tick in runExport(
        plan: plan,
        destinationRoot: tempDir.path,
        preset: request.preset,
      )) {
        if (cancel.cancelled) break;
        _jobs.updateContactSheet(done: tick.done);
      }
      if (cancel.cancelled) return;

      // Listed on an isolate: hundreds of rendered files, and directory
      // listing is blocking I/O (§0.6).
      final tempPath = tempDir.path;
      final filePaths = await Isolate.run(
        () => Directory(tempPath)
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => f.path)
            .toList(),
      );
      final files = [for (final path in filePaths) File(path)];
      if (files.isEmpty) {
        throw const ContactSheetException('Nothing was rendered to upload');
      }

      // 2. Resolve the gallery. For a new destination, create the chain of
      // new (sub-)galleries in order — each nested under the previous, the
      // first under request.parentId — and upload into the deepest one.
      var galleryId = request.galleryId;
      if (galleryId == null) {
        var parentId = request.parentId;
        for (final name in request.newGalleryNames) {
          parentId = (await client.createGallery(
            name: name,
            parentId: parentId,
          )).id;
        }
        galleryId = parentId;
      }
      if (galleryId == null) {
        throw const ContactSheetException('No gallery to upload into');
      }

      // 3. Upload in batches, reporting progress.
      _jobs.updateContactSheet(verb: 'Uploading', total: files.length, done: 0);
      const batchSize = 10;
      var uploaded = 0;
      for (var i = 0; i < files.length && !cancel.cancelled; i += batchSize) {
        final end = (i + batchSize).clamp(0, files.length);
        await client.uploadImages(
          galleryId: galleryId,
          files: files.sublist(i, end),
        );
        uploaded = end;
        _jobs.updateContactSheet(done: end);
      }

      if (!cancel.cancelled) {
        _notify(
          'Sent $uploaded photo(s) to ContactSheet',
          kind: NoticeKind.success,
        );
      }
    } on ContactSheetException catch (e) {
      _notify(e.message, kind: NoticeKind.warning);
    } on Object catch (e) {
      _notify('Send failed: $e', kind: NoticeKind.warning);
    } finally {
      client.close();
      _deleteTemp(tempDir);
      _jobs.clearContactSheet();
    }
  }

  /// Cancels the in-flight ContactSheet send/pull.
  void cancelContactSheet() {
    _csCancel?.cancelled = true;
    _jobs.clearContactSheet();
    _notify('Send cancelled');
  }

  /// Pulls client marks (ratings/colours) from a shared ContactSheet gallery
  /// back onto the matching photos, selects them, and optionally imports the
  /// client's collections as named saved selections. Non-modal (floating
  /// progress card).
  Future<void> runContactSheetPull(ContactSheetPullRequest request) async {
    final client = ContactSheetClient(
      baseUrl: request.baseUrl,
      token: request.token,
    );
    final cancel = _csCancel = _JobCancel();
    _jobs.startContactSheet('Pulling', 0);
    try {
      final marks = await client.pullGalleryMarks(request.shareToken);
      final photos = _ref.read(photosProvider).value ?? const <Photo>[];
      final photoRefs = [
        for (final photo in photos) (id: photo.id, path: photo.path),
      ];
      final resolved = resolvePulledMarks(marks, photoRefs);

      if (resolved.isNotEmpty) {
        _jobs.updateContactSheet(verb: 'Applying', total: resolved.length);
        final controller = _ref.read(cullControllerProvider.notifier);
        // Group by value and apply as batch marks: one UPDATE + one stream
        // emit + one sidecar batch per distinct value. Per-photo setRating/
        // setColor ran the full update→re-emit→grid-rebuild→sidecar pipeline
        // once per pulled mark — hundreds of times for a busy gallery.
        final byRating = <int, Set<int>>{};
        final byColor = <ColorLabel, Set<int>>{};
        for (final mark in resolved) {
          if (mark.rating != null) {
            (byRating[mark.rating!] ??= {}).add(mark.photoId);
          }
          if (mark.color != null) {
            (byColor[mark.color!] ??= {}).add(mark.photoId);
          }
        }
        var done = 0;
        void tickApplied(int count) {
          done = (done + count).clamp(0, resolved.length);
          _jobs.updateContactSheet(done: done);
        }

        for (final entry in byRating.entries) {
          if (cancel.cancelled) break;
          await controller.setRatingForIds(entry.value, entry.key);
          tickApplied(entry.value.length);
        }
        for (final entry in byColor.entries) {
          if (cancel.cancelled) break;
          await controller.setColorForIds(entry.value, entry.key);
        }
        if (!cancel.cancelled) tickApplied(resolved.length);
        // The client only ever saw the normal exposures, so their picks
        // re-attach the ±EV bracket siblings when auto-expand is on.
        _selectMaybeExpanding({for (final m in resolved) m.photoId});
      }

      // Collections → saved selections (best-effort; a gallery with
      // collections disabled 403s, which we treat as "none").
      var savedCollections = 0;
      final importId = _ref.read(currentImportProvider);
      if (request.importCollections && importId != null && !cancel.cancelled) {
        try {
          final collections = await client.pullCollections(request.shareToken);
          final selections = resolveCollectionSelections(
            collections,
            marks,
            photoRefs,
          );
          final db = _ref.read(appDatabaseProvider);
          for (final selection in selections) {
            await db.saveSelection(
              importId: importId,
              name: selection.name,
              photoIds: selection.photoIds,
            );
            savedCollections++;
          }
        } on ContactSheetException {
          // Collections not available for this gallery — skip silently.
        }
      }

      if (!cancel.cancelled) {
        if (resolved.isEmpty && savedCollections == 0) {
          _notify('No matching client marks in “${request.galleryName}”');
        } else {
          final parts = [
            if (resolved.isNotEmpty) '${resolved.length} marked photo(s)',
            if (savedCollections > 0) '$savedCollections collection(s)',
          ];
          _notify(
            'Pulled ${parts.join(' + ')} from “${request.galleryName}”',
            kind: NoticeKind.success,
          );
        }
      }
    } on ContactSheetException catch (e) {
      _notify(e.message, kind: NoticeKind.warning);
    } on Object catch (e) {
      _notify('Pull failed: $e', kind: NoticeKind.warning);
    } finally {
      client.close();
      _jobs.clearContactSheet();
    }
  }

  /// Replaces the selection with [ids], first growing it to each photo's
  /// exposure bracket when the auto-expand-on-select setting is on (the
  /// client only ever saw the normal exposures, so their picks re-attach the
  /// siblings automatically).
  void _selectMaybeExpanding(Set<int> ids) {
    var selected = ids;
    if (ids.isNotEmpty && _ref.read(autoExpandBracketsOnSelectProvider)) {
      final groups = _ref.read(bracketGroupsProvider);
      selected = {
        for (final id in ids) ...groups.groupOf(id),
      };
    }
    _ref.read(cullControllerProvider.notifier).setSelection(selected);
  }

  /// Computes perceptual hashes for every photo of the current import (off
  /// the UI isolate) and groups visually similar ones (§8). Shows a floating
  /// progress card and stores the result in [similarGroupsProvider], which
  /// the badge/chip/compare then reflect.
  Future<void> runFindSimilar(SimilaritySensitivity sensitivity) async {
    final importId = _ref.read(currentImportProvider);
    final photos = _ref.read(photosProvider).value ?? const <Photo>[];
    if (importId == null || photos.length < 2) return;
    final cache = _ref.read(previewCacheProvider);
    final cancel = _hashCancel = _JobCancel();
    _jobs.startFindSimilar(photos.length);
    final hashes = <({int id, int hash})>[];
    try {
      // Process in chunks: fetch each chunk's thumbnails (bounded
      // concurrency), then hash the whole chunk in ONE background isolate.
      // Hashing per photo would spawn hundreds of isolates and can fail
      // under that load.
      const chunkSize = 48;
      var done = 0;
      for (var i = 0; i < photos.length && !cancel.cancelled; i += chunkSize) {
        final end = (i + chunkSize).clamp(0, photos.length);
        final chunk = photos.sublist(i, end);
        final loaded = await Future.wait(
          chunk.map((photo) async {
            try {
              // Prefetch priority: the whole-folder hashing pass must queue
              // *behind* the cells the user is looking at, not compete with
              // them — at visible priority it starved live scrolling.
              return (
                id: photo.id,
                bytes: await cache.thumbnail(
                  photo.path,
                  priority: JobPriority.prefetch,
                ),
              );
            } on Object {
              return (id: photo.id, bytes: null);
            }
          }),
        );
        final withBytes = [
          for (final l in loaded)
            if (l.bytes != null) (id: l.id, bytes: l.bytes!),
        ];
        if (withBytes.isNotEmpty) {
          // `compute` sends only the byte list to the isolate (no closure
          // that could capture unsendable state, e.g. a Timer).
          final byteList = [for (final w in withBytes) w.bytes];
          final hashList = await compute(hashThumbnails, byteList);
          for (var k = 0; k < withBytes.length; k++) {
            final h = hashList[k];
            if (h != null) hashes.add((id: withBytes[k].id, hash: h));
          }
        }
        done = end;
        _jobs.tickFindSimilar(done);
      }
      if (cancel.cancelled) return;
      final result = BurstGroups(
        clusterByHash(hashes, maxDistance: sensitivity.maxDistance),
      );
      _ref.read(similarGroupsProvider.notifier).setFor(importId, result);
      _notify(
        result.burstCount == 0
            ? 'No similar photos found (${sensitivity.label} sensitivity)'
            : 'Found ${result.burstCount} similar group(s), '
                  '${result.memberIds.length} photos · '
                  '${sensitivity.label} (Similar filter)',
        kind: NoticeKind.success,
      );
    } on Object catch (e) {
      _notify('Find similar failed: $e', kind: NoticeKind.warning);
    } finally {
      _jobs.clearFindSimilar();
    }
  }

  /// Cancels the in-flight find-similar pass.
  void cancelFindSimilar() {
    _hashCancel?.cancelled = true;
  }
}
