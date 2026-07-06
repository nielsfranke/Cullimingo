part of 'cull_page.dart';

/// Non-modal background jobs: export, ContactSheet, find-similar. The display
/// progress lives in [backgroundJobsProvider] (watched by [build] for the
/// floating cards); the cancel tokens below stay plain objects so a running
/// loop can still poll them after the page is disposed.
mixin _CullJobs on _CullSelections {
  // Cancels the in-flight export stream (also cancelled in dispose).
  StreamSubscription<ExportProgress>? _exportSub;

  // Cancels the in-flight copy/move stream (also cancelled in dispose).
  StreamSubscription<TransferProgress>? _transferSub;

  // Cancel token for the in-flight ContactSheet send/pull, polled between
  // ticks/batches.
  _JobCancel? _csCancel;

  // Cancel token for the in-flight delivered export (render + upload).
  _JobCancel? _deliveryCancel;

  // Failed uploads waiting behind the notice's "Retry failed" action, plus
  // the temp dir their rendered files live in (null when the files are in a
  // kept local folder). Replaced (and its temp dir deleted) when the next
  // delivered export starts.
  ({
    List<DeliveryItem> items,
    DeliveryServer server,
    Directory? tempDir,
  })?
  _failedDelivery;

  // Cancel token for the in-flight find-similar hashing pass.
  _JobCancel? _hashCancel;

  /// Opens the export dialog for the current selection (or the whole filtered
  /// set when nothing is selected) — the bottom "Export N Photos" bar
  /// (`BUILD_PLAN.md` §6).
  Future<void> _export() async {
    final sources = _exportSources();
    if (sources.isEmpty) return;
    final request = await showExportDialog(context, sources: sources);
    if (!mounted) return;
    _gridFocus.requestFocus();
    if (request != null) _runExport(request);
  }

  /// Runs [request] in the background (non-modal), driving the floating
  /// progress card via [backgroundJobsProvider]. The grid stays interactive
  /// throughout (the render is on isolates; only progress ticks reach the UI).
  /// On done, summarises via the notice bar and optionally opens the
  /// destination folder.
  void _runExport(ExportRequest request) {
    if (request.server != null) {
      unawaited(_runExportDelivered(request));
      return;
    }
    unawaited(_exportSub?.cancel());
    final results = <ExportResult>[];
    ref.read(backgroundJobsProvider.notifier).startExport(request.plan.length);
    // Kept in _exportSub and cancelled in _cancelExport/dispose.
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
            if (mounted) {
              ref.read(backgroundJobsProvider.notifier).tickExport(tick.done);
            }
          },
          onDone: () {
            if (!mounted) return;
            final summary = ExportSummary(results);
            ref.read(backgroundJobsProvider.notifier).clearExport();
            final failed = summary.failed;
            _notify(
              failed > 0
                  ? 'Exported ${summary.written} photo(s) · $failed failed'
                  : 'Exported ${summary.written} photo(s)',
              kind: failed > 0 ? NoticeKind.warning : NoticeKind.success,
            );
            if (request.openWhenDone && summary.written > 0) {
              // Next-to-originals has no single root — open the first output's
              // folder (beside its source, plus the optional subfolder).
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
    final jobs = ref.read(backgroundJobsProvider.notifier);
    final cancel = _deliveryCancel = _JobCancel();
    var keepTemp = false;
    jobs.startExport(request.plan.length);
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
        if (mounted) jobs.tickExport(tick.done);
      }
      if (cancel.cancelled) return;
      final renderFailed = rendered.where((r) => !r.ok).length;
      final okPaths = [
        for (final r in rendered)
          if (r.ok) r.relPath,
      ];
      if (okPaths.isEmpty) {
        if (mounted) {
          _notify('Nothing was rendered to upload', kind: NoticeKind.warning);
        }
        return;
      }

      // 2. Upload over one connection.
      final summary = await _uploadItems(
        items: deliveryItemsFor(localRoot: root, relPaths: okPaths),
        server: server,
        cancel: cancel,
      );
      if (summary == null) return; // cancelled mid-upload

      if (mounted) {
        keepTemp = _reportDelivery(
          summary,
          server: server,
          renderFailed: renderFailed,
          tempDir: tempDir,
        );
        if (request.openWhenDone && localRoot != null) {
          unawaited(openExternally(localRoot));
        }
      }
    } on Object catch (e) {
      if (mounted) _notify('Delivery failed: $e', kind: NoticeKind.warning);
    } finally {
      if (!keepTemp) _deleteTemp(tempDir);
      if (mounted) jobs.clearExport();
    }
  }

  /// The notice's "Retry failed" action: re-uploads the stored failures over
  /// a fresh connection; whatever fails again re-arms the same notice.
  Future<void> _retryFailedDelivery() async {
    final pending = _failedDelivery;
    if (pending == null) return;
    _failedDelivery = null;
    _dismissNotice();
    final jobs = ref.read(backgroundJobsProvider.notifier);
    final cancel = _deliveryCancel = _JobCancel();
    var keepTemp = false;
    jobs.startExport(pending.items.length);
    try {
      final summary = await _uploadItems(
        items: pending.items,
        server: pending.server,
        cancel: cancel,
      );
      if (summary == null) return;
      if (mounted) {
        keepTemp = _reportDelivery(
          summary,
          server: pending.server,
          renderFailed: 0,
          tempDir: pending.tempDir,
        );
      }
    } on Object catch (e) {
      if (mounted) _notify('Delivery failed: $e', kind: NoticeKind.warning);
    } finally {
      if (!keepTemp) _deleteTemp(pending.tempDir);
      if (mounted) jobs.clearExport();
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
        await ref
            .read(secretStoreProvider)
            .read(deliveryPasswordKey(server.id)) ??
        '';
    if (mounted) {
      ref
          .read(backgroundJobsProvider.notifier)
          .updateExport(verb: 'Uploading', done: 0, total: items.length);
    }
    final results = <DeliveryResult>[];
    await for (final tick in runDelivery(
      items: items,
      connectClient: () => createDeliveryClient(server, password),
      remoteDir: server.remoteDir,
    )) {
      if (cancel.cancelled) return null;
      results.add(tick.last);
      if (mounted) {
        ref.read(backgroundJobsProvider.notifier).updateExport(done: tick.done);
      }
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
    _showNotice(
      Notice(
        kind: NoticeKind.warning,
        message: parts.join(' · '),
        icon: NoticeKind.warning.icon,
        actions: [
          (
            label: 'Retry failed',
            onTap: () => unawaited(_retryFailedDelivery()),
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
    try {
      dir?.deleteSync(recursive: true);
    } on Object {
      // Best effort — a leftover temp dir is harmless.
    }
  }

  void _cancelExport() {
    unawaited(_exportSub?.cancel());
    _exportSub = null;
    _deliveryCancel?.cancelled = true;
    ref.read(backgroundJobsProvider.notifier).clearExport();
    _notify('Export cancelled');
  }

  /// Copies or moves the current selection (or the focused photo) to a folder
  /// the user picks — opens the dialog, then runs it non-modally. Acts on
  /// [CullSelection.markTargets], the same targets the context menu marks.
  Future<void> _transfer(TransferMode mode) async {
    final sources = _selectionPaths();
    if (sources.isEmpty) return;
    final request = await showTransferDialog(
      context,
      sources: sources,
      mode: mode,
    );
    if (!mounted) return;
    _gridFocus.requestFocus();
    if (request != null) await _runTransfer(request);
  }

  /// Runs [request] in the background (non-modal): the verified copy (+ delete
  /// on move) happens on isolates, only progress ticks reach the UI, so the
  /// grid stays interactive. Summarises via the notice bar and optionally opens
  /// the destination folder.
  Future<void> _runTransfer(TransferRequest request) async {
    unawaited(_transferSub?.cancel());
    final isMove = request.mode == TransferMode.move;
    final plan = await buildTransferPlan(
      request.sources,
      includeSidecars: request.includeSidecars,
    );
    if (!mounted || plan.isEmpty) return;
    final results = <CopyResult>[];
    ref
        .read(backgroundJobsProvider.notifier)
        .startTransfer(isMove ? 'Moving' : 'Copying', plan.length);
    // Kept in _transferSub and cancelled in _cancelTransfer/dispose.
    _transferSub =
        runTransfer(
          plan: plan,
          destinationRoot: request.destinationRoot,
          mode: request.mode,
        ).listen(
          (tick) {
            results.add(tick.last);
            if (mounted) {
              ref.read(backgroundJobsProvider.notifier).tickTransfer(tick.done);
            }
          },
          onDone: () {
            if (!mounted) return;
            ref.read(backgroundJobsProvider.notifier).clearTransfer();
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

  void _cancelTransfer() {
    unawaited(_transferSub?.cancel());
    _transferSub = null;
    ref.read(backgroundJobsProvider.notifier).clearTransfer();
    _notify('Transfer cancelled');
  }

  /// Moves every rejected (X-flagged) photo of the open folder — filtered away
  /// or not — to the OS trash together with its `.xmp` sidecar, after
  /// confirmation, and drops the rows from the grid. Files land in the Trash
  /// (restorable), never hard-deleted; a photo the OS refuses to trash keeps
  /// its row and marks.
  Future<void> _deleteRejects() async {
    final importId = ref.read(currentImportProvider);
    if (importId == null) return;
    final all = ref.read(photosProvider).value ?? const <Photo>[];
    final rejects = [
      for (final photo in all)
        if (photo.flag == PickFlag.reject) photo,
    ];
    if (rejects.isEmpty) {
      _notify('No rejected photos in this folder');
      return;
    }
    final confirmed = await showDeleteRejectsDialog(
      context,
      count: rejects.length,
    );
    if (!mounted) return;
    _gridFocus.requestFocus();
    if (confirmed != true) return;

    final result = await deleteRejectedPhotos(
      db: ref.read(appDatabaseProvider),
      importId: importId,
      rejects: rejects,
    );
    if (!mounted) return;

    final failed = result.failedPaths.toSet();
    final deletedIds = {
      for (final photo in rejects)
        if (!failed.contains(photo.path)) photo.id,
    };
    // The rows are gone: prune them out of focus/selection and forget the
    // undo history, so a stale entry can't "restore" marks onto reused ids.
    ref.read(cullControllerProvider.notifier)
      ..pruneMissing(deletedIds)
      ..clearHistory();
    final cache = ref.read(previewCacheProvider);
    for (final photo in rejects) {
      cache.evict(photo.path);
    }

    if (result.error != null) {
      _notify(result.error!, kind: NoticeKind.warning);
      return;
    }
    final noun = result.deleted == 1 ? 'photo' : 'photos';
    _notify(
      [
        'Moved ${result.deleted} $noun to the Trash',
        if (failed.isNotEmpty) '${failed.length} failed',
      ].join(' · '),
      kind: failed.isEmpty ? NoticeKind.success : NoticeKind.warning,
    );
  }

  /// Moves the current selection (the mark targets) to the OS trash, after
  /// confirmation — the right-click context menu's "Delete…" entry. Same
  /// target rule and cleanup as [_deleteRejects], just over an arbitrary
  /// selection instead of every reject-flagged photo in the folder.
  Future<void> _deleteSelected() async {
    final importId = ref.read(currentImportProvider);
    if (importId == null) return;
    final targets = ref.read(cullControllerProvider).markTargets;
    final photos = [
      for (final photo in ref.read(filteredPhotosProvider))
        if (targets.contains(photo.id)) photo,
    ];
    if (photos.isEmpty) return;

    final confirmed = await showDeleteSelectedPhotosDialog(
      context,
      count: photos.length,
    );
    if (!mounted) return;
    _gridFocus.requestFocus();
    if (confirmed != true) return;

    final result = await deleteRejectedPhotos(
      db: ref.read(appDatabaseProvider),
      importId: importId,
      rejects: photos,
    );
    if (!mounted) return;

    final failed = result.failedPaths.toSet();
    final deletedIds = {
      for (final photo in photos)
        if (!failed.contains(photo.path)) photo.id,
    };
    // The rows are gone: prune them out of focus/selection and forget the
    // undo history, so a stale entry can't "restore" marks onto reused ids.
    ref.read(cullControllerProvider.notifier)
      ..pruneMissing(deletedIds)
      ..clearHistory();
    final cache = ref.read(previewCacheProvider);
    for (final photo in photos) {
      cache.evict(photo.path);
    }

    if (result.error != null) {
      _notify(result.error!, kind: NoticeKind.warning);
      return;
    }
    final noun = result.deleted == 1 ? 'photo' : 'photos';
    _notify(
      [
        'Moved ${result.deleted} $noun to the Trash',
        if (failed.isNotEmpty) '${failed.length} failed',
      ].join(' · '),
      kind: failed.isEmpty ? NoticeKind.success : NoticeKind.warning,
    );
  }

  /// Opens the rename dialog for the current selection (the mark targets) and,
  /// on confirm, renames the files in place. Same target rule as copy/move.
  Future<void> _rename() async {
    final targets = ref.read(cullControllerProvider).markTargets;
    final sources = [
      for (final photo in ref.read(filteredPhotosProvider))
        if (targets.contains(photo.id))
          RenameSource(
            id: photo.id,
            path: photo.path,
            capturedAt: photo.capturedAt ?? photo.mtime,
            camera: photo.camera,
          ),
    ];
    if (sources.isEmpty) return;
    final request = await showRenameDialog(context, sources: sources);
    if (!mounted) return;
    _gridFocus.requestFocus();
    if (request != null) await _runRename(sources, request);
  }

  /// Builds + applies the rename off the UI isolate (fast metadata moves; no
  /// hashing), then rewrites `photos.path` for each renamed row so the grid
  /// refreshes via the drift stream with every mark preserved (§2/§6).
  Future<void> _runRename(
    List<RenameSource> sources,
    RenameRequest request,
  ) async {
    final plan = await buildRenamePlan(
      sources,
      template: request.template,
      shoot: request.shoot,
    );
    if (!mounted) return;
    final results = await runRename(plan);
    if (!mounted) return;
    final renamed = <int, String>{
      for (final r in results)
        if (r.ok) r.photoId: r.newPath!,
    };
    if (renamed.isNotEmpty) {
      await ref.read(appDatabaseProvider).renamePhotoPaths(renamed);
    }
    if (!mounted) return;
    final summary = RenameSummary(results);
    final parts = [
      'Renamed ${summary.renamed} photo(s)',
      if (summary.unchanged > 0) '${summary.unchanged} unchanged',
      if (summary.failed > 0) '${summary.failed} failed',
    ];
    _notify(
      parts.join(' · '),
      kind: summary.failed > 0 ? NoticeKind.warning : NoticeKind.success,
    );
  }

  /// The paths a selection action (copy/move/send-to) acts on: the
  /// [CullSelection.markTargets] photos in current grid order — the selection
  /// when the focused photo is part of it, otherwise the focused photo alone.
  List<String> _selectionPaths() {
    final targets = ref.read(cullControllerProvider).markTargets;
    return [
      for (final photo in ref.read(filteredPhotosProvider))
        if (targets.contains(photo.id)) photo.path,
    ];
  }

  /// Opens the current selection (or focused photo) in [editor] — the "Send to"
  /// menu / ⌘E. Hands over the RAW originals (`open -a` on macOS, the executable
  /// elsewhere); fire-and-forget, so no progress card.
  Future<void> _sendTo(ExternalEditor editor) async {
    final paths = _selectionPaths();
    if (paths.isEmpty) return;
    try {
      await openInApp(editor.path, paths);
      if (mounted) {
        _notify(
          'Opening ${paths.length} photo${paths.length == 1 ? '' : 's'} in '
          '${editor.label}',
        );
      }
    } on Object catch (e) {
      if (mounted) {
        _notify('Couldn’t open ${editor.label}: $e', kind: NoticeKind.warning);
      }
    }
  }

  /// ⌘E: opens the selection in the first configured editor, or hints to add
  /// one when the list is empty.
  Future<void> _sendToPrimary() async {
    final editors = await ref.read(sendToEditorsProvider.future);
    if (!mounted) return;
    if (editors.isEmpty) {
      _notify(
        'No editors configured yet — add one in Settings',
        kind: NoticeKind.warning,
      );
      return;
    }
    await _sendTo(editors.first);
  }

  /// Builds the export sources for the current selection (or whole filtered set
  /// when nothing is selected), the shared input to export + ContactSheet.
  List<ExportSource> _exportSources() {
    final filtered = ref.read(filteredPhotosProvider);
    final selected = ref.read(cullControllerProvider).selectedIds;
    final photos = selected.isEmpty
        ? filtered
        : filtered.where((p) => selected.contains(p.id)).toList();
    return [
      for (final photo in photos)
        ExportSource(
          path: photo.path,
          capturedAt: photo.capturedAt ?? photo.mtime,
          originalName: p.basename(photo.path),
          camera: photo.camera,
          meta: _exportMeta(photo),
          userRotation: photo.userRotation,
        ),
    ];
  }

  /// The marks + IPTC embedded into a photo's exported JPEG, or null when the
  /// photo carries no metadata worth writing (so a plain unrated export stays
  /// byte-clean).
  XmpData? _exportMeta(Photo photo) {
    final data = XmpData(
      rating: photo.rating,
      color: photo.colorLabel,
      flag: photo.flag,
      keywords: photo.keywords,
      iptc: photo.iptc,
      // Derived, so it does NOT count towards hasMarks below — a plain
      // unrated export stays byte-clean.
      dateCreated: photo.capturedAt,
    );
    final hasMarks =
        data.rating > 0 ||
        data.color != ColorLabel.none ||
        data.flag != PickFlag.none ||
        data.keywords.isNotEmpty;
    if (!hasMarks && data.iptc.isEmpty) return null;
    return data;
  }

  /// Opens the ContactSheet dialog (§7b) — send (upload) or pull (marks). Both
  /// run non-modally with the floating progress card. [pullMode] opens straight
  /// into pull (used by the right-click "Pull marks…" entry).
  Future<void> _openContactSheet({bool pullMode = false}) async {
    final sources = _exportSources();
    final action = await showContactSheetDialog(
      context,
      sources: sources,
      initialPullMode: pullMode,
    );
    if (!mounted) return;
    // The connection may have just been configured — refresh the menu gate.
    ref.invalidate(contactSheetConfiguredProvider);
    _gridFocus.requestFocus();
    switch (action) {
      case ContactSheetSend(:final request):
        await _runContactSheet(request);
      case ContactSheetPull(:final request):
        await _runContactSheetPull(request);
      case null:
        break;
    }
  }

  Future<void> _runContactSheet(ContactSheetRequest request) async {
    final tempDir = Directory.systemTemp.createTempSync('cm_cs_send');
    final client = ContactSheetClient(
      baseUrl: request.baseUrl,
      token: request.token,
    );
    final cancel = _csCancel = _JobCancel();
    ref
        .read(backgroundJobsProvider.notifier)
        .startContactSheet('Rendering', request.sources.length);
    try {
      // 1. Render to temp via the export pipeline.
      final plan = buildExportPlan(request.sources, request.preset);
      await for (final tick in runExport(
        plan: plan,
        destinationRoot: tempDir.path,
        preset: request.preset,
      )) {
        if (cancel.cancelled) break;
        if (mounted) {
          ref
              .read(backgroundJobsProvider.notifier)
              .updateContactSheet(done: tick.done);
        }
      }
      if (cancel.cancelled) return;

      final files = tempDir
          .listSync(recursive: true)
          .whereType<File>()
          .toList();
      if (files.isEmpty) {
        throw const ContactSheetException('Nothing was rendered to upload');
      }

      // 2. Resolve the gallery (create when new).
      final galleryId =
          request.galleryId ??
          (await client.createGallery(
            name: request.galleryName!,
            parentId: request.parentId,
          )).id;

      // 3. Upload in batches, reporting progress.
      if (mounted) {
        ref
            .read(backgroundJobsProvider.notifier)
            .updateContactSheet(
              verb: 'Uploading',
              total: files.length,
              done: 0,
            );
      }
      const batchSize = 10;
      var uploaded = 0;
      for (var i = 0; i < files.length && !cancel.cancelled; i += batchSize) {
        final end = (i + batchSize).clamp(0, files.length);
        await client.uploadImages(
          galleryId: galleryId,
          files: files.sublist(i, end),
        );
        uploaded = end;
        if (mounted) {
          ref
              .read(backgroundJobsProvider.notifier)
              .updateContactSheet(done: end);
        }
      }

      if (mounted && !cancel.cancelled) {
        _notify(
          'Sent $uploaded photo(s) to ContactSheet',
          kind: NoticeKind.success,
        );
      }
    } on ContactSheetException catch (e) {
      if (mounted) _notify(e.message, kind: NoticeKind.warning);
    } on Object catch (e) {
      if (mounted) _notify('Send failed: $e', kind: NoticeKind.warning);
    } finally {
      client.close();
      try {
        tempDir.deleteSync(recursive: true);
      } on Object {
        // Best effort — a leftover temp dir is harmless.
      }
      if (mounted) {
        ref.read(backgroundJobsProvider.notifier).clearContactSheet();
      }
    }
  }

  void _cancelContactSheet() {
    _csCancel?.cancelled = true;
    ref.read(backgroundJobsProvider.notifier).clearContactSheet();
    _notify('Send cancelled');
  }

  /// Pulls client ratings/colours from a gallery (§7b): fetch via share token,
  /// match to local photos by filename, apply marks (write-through to XMP) and
  /// select the marked photos. Optionally also imports the gallery's
  /// collections as named saved selections. Non-modal (floating progress card).
  Future<void> _runContactSheetPull(ContactSheetPullRequest request) async {
    final client = ContactSheetClient(
      baseUrl: request.baseUrl,
      token: request.token,
    );
    final cancel = _csCancel = _JobCancel();
    ref.read(backgroundJobsProvider.notifier).startContactSheet('Pulling', 0);
    try {
      final marks = await client.pullGalleryMarks(request.shareToken);
      final photos = ref.read(photosProvider).value ?? const <Photo>[];
      final photoRefs = [
        for (final photo in photos) (id: photo.id, path: photo.path),
      ];
      final resolved = resolvePulledMarks(marks, photoRefs);

      if (resolved.isNotEmpty) {
        if (mounted) {
          ref
              .read(backgroundJobsProvider.notifier)
              .updateContactSheet(verb: 'Applying', total: resolved.length);
        }
        final controller = ref.read(cullControllerProvider.notifier);
        var done = 0;
        for (final mark in resolved) {
          if (cancel.cancelled) break;
          if (mark.rating != null) {
            await controller.setRating(mark.photoId, mark.rating!);
          }
          if (mark.color != null) {
            await controller.setColor(mark.photoId, mark.color!);
          }
          done++;
          if (mounted) {
            ref
                .read(backgroundJobsProvider.notifier)
                .updateContactSheet(done: done);
          }
        }
        // The client only ever saw the normal exposures, so their picks
        // re-attach the ±EV bracket siblings when auto-expand is on.
        _applySelectionMaybeExpanding({for (final m in resolved) m.photoId});
      }

      // Collections → saved selections (best-effort; a gallery with collections
      // disabled 403s, which we treat as "none").
      var savedCollections = 0;
      final importId = ref.read(currentImportProvider);
      if (request.importCollections && importId != null && !cancel.cancelled) {
        try {
          final collections = await client.pullCollections(request.shareToken);
          final selections = resolveCollectionSelections(
            collections,
            marks,
            photoRefs,
          );
          final db = ref.read(appDatabaseProvider);
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

      if (mounted && !cancel.cancelled) {
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
      if (mounted) _notify(e.message, kind: NoticeKind.warning);
    } on Object catch (e) {
      if (mounted) _notify('Pull failed: $e', kind: NoticeKind.warning);
    } finally {
      client.close();
      if (mounted) {
        ref.read(backgroundJobsProvider.notifier).clearContactSheet();
      }
    }
  }

  /// Opens the central Settings dialog (performance / ContactSheet / cache).
  /// A performance-preset change applies at next launch, so it surfaces a
  /// restart hint.
  Future<void> _openSettings() async {
    final changed = await showSettingsDialog(
      context,
      onClearCache: _clearCache,
    );
    if (!mounted) return;
    _gridFocus.requestFocus();
    if (changed != null) {
      _notify(
        'Performance set to ${changed.label} — restart Cullimingo to apply',
        kind: NoticeKind.warning,
      );
    }
  }

  /// Computes perceptual hashes for every photo (off the UI isolate) and groups
  /// visually similar ones (§8). On-demand: shows a floating progress card and
  /// stores the result in [similarGroupsProvider], which the badge/chip/compare
  /// then reflect.
  Future<void> _findSimilar() async {
    if (ref.read(backgroundJobsProvider).findSimilar != null) return;
    final importId = ref.read(currentImportProvider);
    final photos = ref.read(photosProvider).value ?? const <Photo>[];
    if (importId == null || photos.length < 2) {
      _notify('Open a folder with photos first', kind: NoticeKind.warning);
      return;
    }
    // Ask how aggressively to group before doing the (heavier) hashing pass.
    final sensitivity = await showFindSimilarDialog(context);
    if (sensitivity == null || !mounted) return; // cancelled
    final cache = ref.read(previewCacheProvider);
    final cancel = _hashCancel = _JobCancel();
    ref.read(backgroundJobsProvider.notifier).startFindSimilar(photos.length);
    final hashes = <({int id, int hash})>[];
    try {
      // Process in chunks: fetch each chunk's thumbnails (bounded concurrency),
      // then hash the whole chunk in ONE background isolate. Hashing per photo
      // would spawn hundreds of isolates and can fail under that load.
      const chunkSize = 48;
      var done = 0;
      for (var i = 0; i < photos.length && !cancel.cancelled; i += chunkSize) {
        final end = (i + chunkSize).clamp(0, photos.length);
        final chunk = photos.sublist(i, end);
        final loaded = await Future.wait(
          chunk.map((p) async {
            try {
              return (id: p.id, bytes: await cache.thumbnail(p.path));
            } on Object {
              return (id: p.id, bytes: null);
            }
          }),
        );
        final withBytes = [
          for (final l in loaded)
            if (l.bytes != null) (id: l.id, bytes: l.bytes!),
        ];
        if (withBytes.isNotEmpty) {
          // `compute` sends only the byte list to the isolate (no closure that
          // could capture unsendable State, e.g. a Timer).
          final byteList = [for (final w in withBytes) w.bytes];
          final hashList = await compute(hashThumbnails, byteList);
          for (var k = 0; k < withBytes.length; k++) {
            final h = hashList[k];
            if (h != null) hashes.add((id: withBytes[k].id, hash: h));
          }
        }
        done = end;
        if (mounted) {
          ref.read(backgroundJobsProvider.notifier).tickFindSimilar(done);
        }
      }
      if (cancel.cancelled) return;
      final result = BurstGroups(
        clusterByHash(hashes, maxDistance: sensitivity.maxDistance),
      );
      ref.read(similarGroupsProvider.notifier).setFor(importId, result);
      if (mounted) {
        _notify(
          result.burstCount == 0
              ? 'No similar photos found (${sensitivity.label} sensitivity)'
              : 'Found ${result.burstCount} similar group(s), '
                    '${result.memberIds.length} photos · '
                    '${sensitivity.label} (Similar filter)',
          kind: NoticeKind.success,
        );
      }
    } on Object catch (e) {
      if (mounted) {
        _notify('Find similar failed: $e', kind: NoticeKind.warning);
      }
    } finally {
      if (mounted) ref.read(backgroundJobsProvider.notifier).clearFindSimilar();
    }
  }

  /// Discards the current folder's similarity grouping (back to bursts).
  void _clearSimilar() {
    final importId = ref.read(currentImportProvider);
    if (importId == null) return;
    ref.read(similarGroupsProvider.notifier).clearFor(importId);
    _notify('Cleared similar grouping');
  }
}
