part of 'cull_page.dart';

/// Grid layout math, viewport prefetch, scroll restore and loupe.
mixin _CullGrid on _CullNotices {
  final FocusNode _gridFocus = FocusNode(debugLabel: 'cull-grid');

  final ScrollController _scroll = ScrollController();

  int _columns = 1;

  double _viewportHeight = 0;

  // Cell main-axis extent, derived from the slider width each build. A field so
  // keyboard-scroll and prefetch row math stay exact.
  double _cellExtent = 196;

  // Whether the fullscreen loupe overlay is showing. The loupe reads the
  // focused photo from CullController, so opening it needs no extra state.
  bool _loupeOpen = false;

  Timer? _prefetchTimer;

  // Cancels the previous prefetch batch when the viewport moves, so stale
  // (scrolled-past) warm-ups don't clog the pool ahead of the visible cells.
  CancelToken? _prefetchToken;

  // A grid scroll offset to apply once the (new tab's) grid has laid out, or
  // null when there's nothing pending. Consumed in the grid's LayoutBuilder so
  // the jump happens with the new content's real maxScrollExtent.
  double? _pendingScrollRestore;

  // The cell width from the last grid build, so a zoom change is detectable.
  double? _lastCellWidth;

  // A grid item to hold steady across a zoom change (see [zoomAnchor]), or null
  // when no re-anchor is pending. Consumed after the new layout so the anchor
  // photo stays under the eye instead of scrolling away when thumbnails resize.
  ZoomAnchor? _pendingZoomAnchor;

  // Debounced: a scroll or grid (re)layout triggers one prefetch once settled.
  void _schedulePrefetch() {
    _prefetchTimer?.cancel();
    _prefetchTimer = Timer(const Duration(milliseconds: 90), _prefetch);
  }

  /// Warms the cache for the cells just outside the viewport (mostly ahead) so
  /// they render instantly when scrolled into view (`BUILD_PLAN.md` §2).
  void _prefetch() {
    if (!mounted || !_scroll.hasClients || _columns < 1) return;
    final photos = ref.read(filteredPhotosProvider);
    if (photos.isEmpty) return;

    final rowHeight = _cellExtent + _cellSpacing;
    final firstRow = (_scroll.offset / rowHeight).floor();
    final visibleRows = (_viewportHeight / rowHeight).ceil() + 1;

    final start = ((firstRow - 1) * _columns).clamp(0, photos.length);
    final end = ((firstRow + visibleRows + _prefetchRows) * _columns).clamp(
      0,
      photos.length,
    );

    _prefetchToken?.cancel();
    final token = _prefetchToken = CancelToken();
    final cache = ref.read(previewCacheProvider);
    for (var i = start; i < end; i++) {
      unawaited(
        cache.thumbnail(
          photos[i].path,
          cancel: token,
          priority: JobPriority.prefetch,
        ),
      );
    }
  }

  void _selectAllVisible() {
    final photos = ref.read(filteredPhotosProvider);
    if (photos.isEmpty) return;
    ref
        .read(cullControllerProvider.notifier)
        .setSelection(photos.map((p) => p.id).toSet());
  }

  // Applies a queued per-tab scroll offset after the new grid lays out. Runs in
  // a post-frame callback so the GridView's maxScrollExtent reflects the new
  // tab's content before we clamp+jump.
  void _applyPendingScrollRestore() {
    final target = _pendingScrollRestore;
    if (target == null) return;
    _pendingScrollRestore = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      _scroll.jumpTo(target.clamp(0, max));
      _schedulePrefetch();
    });
  }

  // Captures the grid item to hold steady across a zoom change, from the
  // *outgoing* layout ([oldColumns]/[oldExtent]). The re-scroll happens later,
  // once the new layout is measured, in [_applyPendingZoomReanchor].
  void _queueZoomReanchor(
    List<Photo> photos, {
    required int oldColumns,
    required double oldExtent,
  }) {
    if (!_scroll.hasClients) return;
    final focusedId = ref.read(cullControllerProvider).focusedId;
    _pendingZoomAnchor = zoomAnchor(
      offset: _scroll.offset,
      viewportHeight: _viewportHeight,
      columns: oldColumns,
      rowHeight: oldExtent + _cellSpacing,
      count: photos.length,
      focusedIndex: focusedId == null
          ? -1
          : photos.indexWhere((p) => p.id == focusedId),
    );
  }

  // Re-scrolls after a zoom so the queued anchor row sits at the same on-screen
  // y it had before. Runs post-frame so the new maxScrollExtent is in place.
  void _applyPendingZoomReanchor() {
    final anchor = _pendingZoomAnchor;
    if (anchor == null) return;
    _pendingZoomAnchor = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || _columns < 1) return;
      _scroll.jumpTo(
        zoomReanchorOffset(
          anchor: anchor,
          columns: _columns,
          rowHeight: _cellExtent + _cellSpacing,
          maxScrollExtent: _scroll.position.maxScrollExtent,
        ),
      );
      _schedulePrefetch();
    });
  }

  /// After a list-driven selection (Find / Import), move focus to the first
  /// selected photo in grid order and scroll its row to the top of the
  /// viewport, so the matches read from the top instead of being stuck at the
  /// bottom edge. No-op if nothing matched or the matches are all hidden by the
  /// active filter.
  void _revealFirstSelected(Set<int> ids) {
    if (ids.isEmpty) return;
    final filtered = ref.read(filteredPhotosProvider);
    final index = filtered.indexWhere((p) => ids.contains(p.id));
    if (index < 0) return;
    ref.read(cullControllerProvider.notifier).focus(filtered[index].id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || _columns < 1) return;
      final rowTop = (index ~/ _columns) * (_cellExtent + _cellSpacing);
      unawaited(
        _scroll.animateTo(
          rowTop.clamp(0, _scroll.position.maxScrollExtent),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  void _ensureRowVisible(int index) {
    if (!_scroll.hasClients || _columns < 1) return;
    final row = index ~/ _columns;
    final rowTop = row * (_cellExtent + _cellSpacing);
    final rowBottom = rowTop + _cellExtent;
    final offset = _scroll.offset;
    if (rowTop < offset) {
      unawaited(
        _scroll.animateTo(
          rowTop,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        ),
      );
    } else if (rowBottom > offset + _viewportHeight) {
      unawaited(
        _scroll.animateTo(
          rowBottom - _viewportHeight,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  /// Opens the loupe on [photoId] (from a double-click), focusing it first.
  void _openLoupe(int photoId) {
    ref.read(cullControllerProvider.notifier).focus(photoId);
    setState(() => _loupeOpen = true);
  }
}
