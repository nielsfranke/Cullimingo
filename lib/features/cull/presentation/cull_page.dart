import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/files/open_external.dart';
import 'package:cullimingo/core/files/supported_files.dart';
import 'package:cullimingo/core/logging/app_logger.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/core/secrets/secret_store.dart';
import 'package:cullimingo/core/settings/app_settings.dart';
import 'package:cullimingo/core/update/update_checker.dart';
import 'package:cullimingo/core/update/update_providers.dart';
import 'package:cullimingo/features/cull/data/phash_compute.dart';
import 'package:cullimingo/features/cull/data/reject_deleter.dart';
import 'package:cullimingo/features/cull/domain/compare_focus.dart';
import 'package:cullimingo/features/cull/domain/cull_key_mappings.dart';
import 'package:cullimingo/features/cull/domain/cull_shortcuts.dart';
import 'package:cullimingo/features/cull/domain/dropped_folders.dart';
import 'package:cullimingo/features/cull/domain/duplicate_groups.dart';
import 'package:cullimingo/features/cull/domain/grid_navigation.dart';
import 'package:cullimingo/features/cull/domain/grid_zoom_anchor.dart';
import 'package:cullimingo/features/cull/domain/perceptual_hash.dart';
import 'package:cullimingo/features/cull/presentation/background_jobs.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/widgets/compare_view.dart';
import 'package:cullimingo/features/cull/presentation/widgets/cull_tab_bar.dart';
import 'package:cullimingo/features/cull/presentation/widgets/cull_top_bar.dart';
import 'package:cullimingo/features/cull/presentation/widgets/delete_rejects_dialog.dart';
import 'package:cullimingo/features/cull/presentation/widgets/empty_states.dart';
import 'package:cullimingo/features/cull/presentation/widgets/export_bar.dart';
import 'package:cullimingo/features/cull/presentation/widgets/find_similar_dialog.dart';
import 'package:cullimingo/features/cull/presentation/widgets/grid_cell.dart';
import 'package:cullimingo/features/cull/presentation/widgets/keyboard_shortcuts_dialog.dart';
import 'package:cullimingo/features/cull/presentation/widgets/loupe_view.dart';
import 'package:cullimingo/features/cull/presentation/widgets/notice_bar.dart';
import 'package:cullimingo/features/delivery/data/delivery_client.dart';
import 'package:cullimingo/features/delivery/data/delivery_uploader.dart';
import 'package:cullimingo/features/delivery/domain/delivery_server.dart';
import 'package:cullimingo/features/export/data/export_service.dart';
import 'package:cullimingo/features/export/domain/export_plan.dart';
import 'package:cullimingo/features/export/presentation/export_dialog.dart';
import 'package:cullimingo/features/filter/data/selection_source.dart';
import 'package:cullimingo/features/filter/domain/filename_match.dart';
import 'package:cullimingo/features/filter/domain/photo_filter.dart';
import 'package:cullimingo/features/filter/domain/photo_sort.dart';
import 'package:cullimingo/features/filter/presentation/filter_bar.dart';
import 'package:cullimingo/features/filter/presentation/filter_providers.dart';
import 'package:cullimingo/features/handoff/data/contactsheet_client.dart';
import 'package:cullimingo/features/handoff/data/transfer_service.dart';
import 'package:cullimingo/features/handoff/domain/external_editor.dart';
import 'package:cullimingo/features/handoff/domain/pull_collections.dart';
import 'package:cullimingo/features/handoff/domain/pull_marks.dart';
import 'package:cullimingo/features/handoff/presentation/contactsheet_dialog.dart';
import 'package:cullimingo/features/handoff/presentation/send_to_providers.dart';
import 'package:cullimingo/features/handoff/presentation/transfer_dialog.dart';
import 'package:cullimingo/features/ingest/data/removable_media.dart';
import 'package:cullimingo/features/ingest/data/verified_copy.dart';
import 'package:cullimingo/features/ingest/data/volume_detector.dart';
import 'package:cullimingo/features/ingest/presentation/ingest_dialog.dart';
import 'package:cullimingo/features/inspector/presentation/inspector_panel.dart';
import 'package:cullimingo/features/inspector/presentation/inspector_providers.dart';
import 'package:cullimingo/features/metadata/domain/xmp_data.dart';
import 'package:cullimingo/features/metadata/presentation/apply_template.dart';
import 'package:cullimingo/features/metadata/presentation/geocode_selection.dart';
import 'package:cullimingo/features/metadata/presentation/iptc_editor_dialog.dart';
import 'package:cullimingo/features/metadata/presentation/keyword_dialog.dart';
import 'package:cullimingo/features/naming/data/rename_service.dart';
import 'package:cullimingo/features/naming/presentation/rename_dialog.dart';
import 'package:cullimingo/features/settings/presentation/settings_dialog.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

part 'cull_page.notices.dart';
part 'cull_page.grid.dart';
part 'cull_page.workspace.dart';
part 'cull_page.selections.dart';
part 'cull_page.jobs.dart';
part 'cull_page.keyboard.dart';

/// Spacing between cells.
const double _cellSpacing = AppSpacing.sm;

/// Cell height as a fraction of its width (room for the image + filename row).
const double _cellAspect = 0.98;

/// Rows to warm ahead of the viewport so they're ready before they scroll in.
const int _prefetchRows = 5;

/// The cull grid — the heart of Cullimingo (`BUILD_PLAN.md` §5 Phase 1):
/// toolbar, a virtualized thumbnail grid with keyboard-driven rate/flag/colour,
/// and a full-width export bar.
class CullPage extends ConsumerStatefulWidget {
  /// Creates the cull page.
  const CullPage({super.key});

  @override
  ConsumerState<CullPage> createState() => _CullPageState();
}

class _CullPageState extends ConsumerState<CullPage>
    with
        _CullNotices,
        _CullGrid,
        _CullWorkspace,
        _CullSelections,
        _CullJobs,
        _CullKeyboard {
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_schedulePrefetch);
    // Dev/automation hook: auto-open a folder at launch. No effect in normal
    // use (the env var is unset). Handy for UI screenshots and smoke tests.
    final autoDir = Platform.environment['CULLIMINGO_OPEN_DIR'];
    if (autoDir != null && autoDir.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _importFolder(autoDir),
      );
    } else {
      // Reopen last session's folders if the user enabled it (default off).
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_restoreLastFolders()),
      );
      // First launch only: pop the keyboard cheat sheet so new users find the
      // keyboard-first workflow. Skipped under the automation hook above so it
      // never lands in screenshots/smoke tests.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maybeShowFirstRunShortcuts(),
      );
    }
    // Watch for inserted cards + a vanished open folder. The timer is cancelled
    // in dispose, so it never outlives the page (or leaks into widget tests).
    WidgetsBinding.instance.addPostFrameCallback((_) => _pollFilesystem());
    _cardPollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _pollFilesystem(),
    );
  }

  @override
  void dispose() {
    _prefetchTimer?.cancel();
    _prefetchToken?.cancel();
    _cardPollTimer?.cancel();
    _noticeTimer?.cancel();
    unawaited(_exportSub?.cancel());
    unawaited(_transferSub?.cancel());
    _csCancel?.cancelled = true;
    _gridFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(photosProvider);
    final filtered = ref.watch(filteredPhotosProvider);
    final selectedCount = ref.watch(
      cullControllerProvider.select((s) => s.selectedIds.length),
    );
    final workspace = ref.watch(workspaceProvider);
    ref
      // Keep the "Send to" editor list warm so the right-click menu / ⌘E can
      // read it synchronously (loaded once; Settings invalidates it on edit).
      ..watch(sendToEditorsProvider)
      // Keep the saved open-folders list current so reopen-on-startup works.
      ..listen(workspaceProvider, (_, _) => _persistOpenFolders())
      // Flash an "update available" notice when the startup check (kicked off
      // in main(), no-op in tests) finds a newer GitHub release.
      ..listen(availableUpdateProvider, (_, next) {
        final update = next.value;
        if (update != null) _showUpdateNotice(update);
      })
      // Warn when a mark reached the DB but its .xmp sidecar couldn't be
      // written — otherwise the failure is invisible and the marks silently
      // never round-trip to Lightroom / Capture One.
      ..listen(sidecarWriteErrorProvider, (_, next) {
        final n = next.count;
        if (n > 0) {
          _notify(
            '$n ${n == 1 ? 'mark' : 'marks'} saved, but the .xmp sidecar '
            "couldn't be written — check the folder is writable.",
            kind: NoticeKind.warning,
          );
        }
      });
    final total = photosAsync.value?.length ?? 0;
    final inspectorOpen = total > 0 && ref.watch(inspectorOpenProvider);
    final jobs = ref.watch(backgroundJobsProvider);

    return Scaffold(
      body: DropTarget(
        onDragDone: (details) => unawaited(_handleDrop(details)),
        child: CallbackShortcuts(
          bindings: _appShortcuts(),
          child: Stack(
            children: [
              Column(
                children: [
                  CullTopBar(
                    count: total,
                    onOpenFolder: _openFolder,
                    onIngest: _ingest,
                    includeSubfolders: _includeSubfolders,
                    onIncludeSubfolders: _setIncludeSubfolders,
                    onFind: total > 0 ? _findByList : null,
                    onCompare: total > 0 ? _openCompare : null,
                    onExpandBrackets: total > 0
                        ? _expandSelectionToBrackets
                        : null,
                    onFindSimilar: total > 0 ? _findSimilar : null,
                    onClearSimilar:
                        ref.watch(currentSimilarGroupsProvider) != null
                        ? _clearSimilar
                        : null,
                    onImport: total > 0 ? _importSelection : null,
                    onSaveSelection: total > 0 ? _saveSelection : null,
                    onLoadSelection: total > 0 ? _loadSelection : null,
                    onDeleteSelection: total > 0 ? _deleteSelection : null,
                    onEditKeywords: total > 0
                        ? () => unawaited(
                            showKeywordEditor(
                              context,
                              ref,
                            ).then((_) => _gridFocus.requestFocus()),
                          )
                        : null,
                    onEditMetadata: total > 0
                        ? () => unawaited(
                            showIptcEditor(
                              context,
                              ref,
                            ).then((_) => _gridFocus.requestFocus()),
                          )
                        : null,
                    onApplyTemplate: total > 0
                        ? () => unawaited(_applyTemplate())
                        : null,
                    onGeocode: total > 0
                        ? () => unawaited(_geocodeSelection())
                        : null,
                    onResync: total > 0 ? _resyncSidecars : null,
                    onRefresh: total > 0 ? _refreshFolder : null,
                    onDeleteRejects: total > 0
                        ? () => unawaited(_deleteRejects())
                        : null,
                    onContactSheet: total > 0 ? _openContactSheet : null,
                    onSettings: _openSettings,
                    onShortcuts: _showShortcuts,
                    inspectorOpen: inspectorOpen,
                    onToggleInspector: total > 0
                        ? () =>
                              ref.read(inspectorOpenProvider.notifier).toggle()
                        : null,
                    cellWidth: total > 0
                        ? ref.watch(gridCellWidthProvider)
                        : null,
                    onCellWidth: _onZoomChanged,
                    onZoomStart: total > 0 ? _onZoomStart : null,
                    onZoomEnd: total > 0 ? _onZoomEnd : null,
                  ),
                  if (workspace.tabs.isNotEmpty)
                    CullTabBar(
                      state: workspace,
                      onSelect: _switchTab,
                      onClose: _closeTab,
                      onNew: _openFolder,
                      recentFolders: ref.watch(recentFoldersProvider),
                      onOpenRecent: (path) => unawaited(
                        _importFolder(path, recursive: _includeSubfolders),
                      ),
                    ),
                  if (total > 0) const FilterBar(),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: photosAsync.when(
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            error: (e, _) => Center(child: Text('Error: $e')),
                            data: (photos) => photos.isEmpty
                                ? CullEmptyState(onOpenFolder: _openFolder)
                                : filtered.isEmpty
                                ? const NoMatchesState()
                                : _grid(filtered),
                          ),
                        ),
                        if (inspectorOpen) const InspectorPanel(),
                      ],
                    ),
                  ),
                  if (_notice != null)
                    NoticeBar(notice: _notice!, onDismiss: _dismissNotice),
                  ExportBar(
                    selectedCount: selectedCount,
                    total: filtered.length,
                    onExport: filtered.isEmpty ? null : _export,
                  ),
                ],
              ),
              // Non-modal export progress: floats over the grid (bottom-right,
              // above the export bar) so culling/scrolling continues during a
              // background export (§6).
              if (jobs.export != null)
                Positioned(
                  right: AppSpacing.lg,
                  bottom: 84,
                  child: ExportProgressCard(
                    done: jobs.export!.done,
                    total: jobs.export!.total,
                    onCancel: _cancelExport,
                  ),
                ),
              if (jobs.contactSheet != null)
                Positioned(
                  right: AppSpacing.lg,
                  bottom: 84,
                  child: ExportProgressCard(
                    verb: jobs.contactSheet!.verb,
                    done: jobs.contactSheet!.done,
                    total: jobs.contactSheet!.total,
                    onCancel: _cancelContactSheet,
                  ),
                ),
              if (jobs.findSimilar != null)
                Positioned(
                  right: AppSpacing.lg,
                  bottom: 84,
                  child: ExportProgressCard(
                    verb: jobs.findSimilar!.verb,
                    done: jobs.findSimilar!.done,
                    total: jobs.findSimilar!.total,
                    onCancel: () => _hashCancel?.cancelled = true,
                  ),
                ),
              if (jobs.transfer != null)
                Positioned(
                  right: AppSpacing.lg,
                  bottom: 84,
                  child: ExportProgressCard(
                    verb: jobs.transfer!.verb,
                    done: jobs.transfer!.done,
                    total: jobs.transfer!.total,
                    onCancel: _cancelTransfer,
                  ),
                ),
              // Fullscreen loupe overlays everything; the grid Focus underneath
              // keeps key focus, so `[`/`]` and cull keys still route to _onKey.
              if (_loupeOpen && filtered.isNotEmpty)
                Positioned.fill(
                  child: LoupeView(
                    onClose: () => setState(() => _loupeOpen = false),
                    onTransfer: _transfer,
                    onSendTo: (editor) => unawaited(_sendTo(editor)),
                    onEditMetadata: () =>
                        unawaited(showIptcEditor(context, ref)),
                    onRename: () => unawaited(_rename()),
                    onApplyTemplate: () => unawaited(_applyTemplate()),
                    onGeocode: () => unawaited(_geocodeSelection()),
                    onExport: _export,
                    onContactSheet: (pull) =>
                        unawaited(_openContactSheet(pullMode: pull)),
                  ),
                ),
              // Fullscreen compare overlay (§8).
              if (_compareOpen && filtered.isNotEmpty)
                Positioned.fill(
                  child: CompareView(
                    photoIds: _compareIds,
                    focusedId: _compareFocusedId,
                    onFocus: (id) => setState(() => _compareFocusedId = id),
                    onRemove: _removeFromCompare,
                    onClose: () => setState(() => _compareOpen = false),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grid(List<Photo> photos) {
    final cellWidth = ref.watch(gridCellWidthProvider);
    _cellExtent = cellWidth * _cellAspect;
    // While a zoom drag is live the thumbnails keep decoding at the frozen
    // width, so the grid reflows every frame without re-decoding; on release we
    // drop back to the live width for one gapless re-decode at full sharpness.
    // The scroll is re-anchored around the captured photo synchronously in
    // _onZoomChanged, so the grid zooms in place (see _onZoomStart).
    final decodeWidth = _zoomDragging ? _frozenDecodeWidth : cellWidth;
    return Focus(
      focusNode: _gridFocus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final newColumns = (constraints.maxWidth / cellWidth).floor().clamp(
            1,
            12,
          );
          // A width-driven reflow (the inspector panel opening/closing narrows
          // the grid → fewer/more columns) would otherwise leave the same
          // scroll offset pointing at a different row, scrolling the focused
          // photo away. Re-anchor on it too, the same as a zoom change — unless
          // the zoom path already queued an anchor this frame (don't clobber it
          // with the now-updated cell extent).
          if (!_zoomDragging &&
              _pendingZoomAnchor == null &&
              _columns > 0 &&
              newColumns != _columns) {
            _queueZoomReanchor(
              photos,
              oldColumns: _columns,
              oldExtent: _cellExtent,
            );
          }
          _columns = newColumns;
          _viewportHeight = constraints.maxHeight;
          _gridWidth = constraints.maxWidth;
          // The grid is laid out for this tab now — apply any pending scroll
          // restore (jump to the tab's saved offset, clamped to its content),
          // then warm the visible window + lookahead. A pending re-anchor (from
          // an inspector-driven reflow) is held while a zoom drag is live so it
          // can't jump the scroll mid-resize.
          _applyPendingScrollRestore();
          if (!_zoomDragging) _applyPendingZoomReanchor();
          _schedulePrefetch();
          return GridView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(AppSpacing.md),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _columns,
              mainAxisSpacing: _cellSpacing,
              crossAxisSpacing: _cellSpacing,
              mainAxisExtent: _cellExtent,
            ),
            itemCount: photos.length,
            itemBuilder: (context, i) => GridCell(
              photo: photos[i],
              cellWidth: decodeWidth,
              onOpenLoupe: _openLoupe,
              onTransfer: _transfer,
              onSendTo: (editor) => unawaited(_sendTo(editor)),
              onEditMetadata: () => unawaited(
                showIptcEditor(
                  context,
                  ref,
                ).then((_) => _gridFocus.requestFocus()),
              ),
              onRename: () => unawaited(_rename()),
              onApplyTemplate: () => unawaited(_applyTemplate()),
              onGeocode: () => unawaited(_geocodeSelection()),
              onExport: _export,
              onExpandBrackets: _expandSelectionToBrackets,
              onApplyMarksToBracket: () => unawaited(_applyMarksToBracket()),
              onStack: () => unawaited(_stackSelection()),
              onUnstack: () => unawaited(_unstackSelection()),
              onContactSheet: (pull) =>
                  unawaited(_openContactSheet(pullMode: pull)),
              onDelete: () => unawaited(_deleteSelected()),
            ),
          );
        },
      ),
    );
  }
}

/// A cancel token for a running background job, flipped by the card's Cancel
/// button (or on dispose) and polled by the runner between ticks/batches. Kept
/// as a plain object — not [backgroundJobsProvider] state — so the async loop
/// can still read it after the page is disposed (a provider read would throw).
class _JobCancel {
  bool cancelled = false;
}
