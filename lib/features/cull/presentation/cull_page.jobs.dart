part of 'cull_page.dart';

/// The page-side half of the non-modal jobs: the dialogs that *start* export,
/// copy/move, ContactSheet and find-similar, plus the short, dialog-bound
/// flows (rename, delete, send-to). The long-running orchestration — cancel
/// tokens, retry state, temp dirs, the loops themselves — lives in
/// [CullJobRunner] (`keepAlive`), so a running job never depends on this
/// widget's lifetime; progress reaches the floating cards via
/// [backgroundJobsProvider] and outcomes via [NoticesController].
mixin _CullJobs on _CullSelections {
  CullJobRunner get _jobRunner => ref.read(cullJobRunnerProvider);

  /// Opens the export dialog for the current selection (or the whole filtered
  /// set when nothing is selected) — the bottom "Export N Photos" bar
  /// (`BUILD_PLAN.md` §6).
  Future<void> _export() async {
    final sources = _exportSources();
    if (sources.isEmpty) return;
    final request = await showExportDialog(context, sources: sources);
    if (!mounted) return;
    _gridFocus.requestFocus();
    if (request != null) _jobRunner.runExportJob(request);
  }

  void _cancelExport() => _jobRunner.cancelExport();

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
    if (request != null) await _jobRunner.runTransferJob(request);
  }

  void _cancelTransfer() => _jobRunner.cancelTransfer();

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
        await _jobRunner.runContactSheetSend(request);
      case ContactSheetPull(:final request):
        await _jobRunner.runContactSheetPull(request);
      case null:
        break;
    }
  }

  void _cancelContactSheet() => _jobRunner.cancelContactSheet();

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

  /// Asks for a similarity sensitivity, then hands the (heavy) hashing pass
  /// to the job runner (§8). On-demand: the floating progress card tracks it
  /// and the result lands in [similarGroupsProvider].
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
    await _jobRunner.runFindSimilar(sensitivity);
  }

  void _cancelFindSimilar() => _jobRunner.cancelFindSimilar();

  /// Discards the current folder's similarity grouping (back to bursts).
  void _clearSimilar() {
    final importId = ref.read(currentImportProvider);
    if (importId == null) return;
    ref.read(similarGroupsProvider.notifier).clearFor(importId);
    _notify('Cleared similar grouping');
  }
}
