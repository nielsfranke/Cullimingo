import 'dart:async';

import 'package:cullimingo/core/cache/display_metrics.dart';
import 'package:cullimingo/core/cache/memory_budget.dart';
import 'package:cullimingo/core/cache/preview_cache.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/files/supported_files.dart';
import 'package:cullimingo/core/isolates/preview_pool.dart';
import 'package:cullimingo/core/raw/jpeg_orientation_writer.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/core/settings/app_settings.dart';
import 'package:cullimingo/core/settings/performance_preset.dart';
import 'package:cullimingo/features/cull/domain/cull_shortcuts.dart';
import 'package:cullimingo/features/cull/domain/loupe_zoom.dart';
import 'package:cullimingo/features/cull/domain/mark_undo.dart';
import 'package:cullimingo/features/cull/domain/orientation_math.dart';
import 'package:cullimingo/features/cull/domain/preview_retry.dart';
import 'package:cullimingo/features/cull/domain/recent_folders.dart';
import 'package:cullimingo/features/filter/domain/photo_filter.dart';
import 'package:cullimingo/features/filter/domain/photo_sort.dart';
import 'package:cullimingo/features/library/data/library_repository.dart';
import 'package:cullimingo/features/metadata/data/metadata_repository.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cull_providers.g.dart';

/// The app-wide drift database. Kept alive for the whole session.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
}

/// Number of photos whose XMP sidecar write is still in flight — drives the
/// toolbar "Syncing N…" indicator and the drain-on-quit guard. Marks hit the DB
/// (and the grid) instantly, then mirror to sidecars in the background; this is
/// the only window in which a mark is applied but not yet on disk.
@Riverpod(keepAlive: true)
class SidecarSync extends _$SidecarSync {
  @override
  int build() => 0;

  /// Adjusts the in-flight count as writes begin (`+n`) and finish (`-n`).
  /// Clamped at 0 so a stray decrement can't drive it negative and wedge
  /// [drain].
  void add(int deltaPhotos) {
    final next = state + deltaPhotos;
    state = next < 0 ? 0 : next;
  }

  /// Completes once no sidecar writes are pending, or [timeout] elapses. The
  /// quit guard awaits this so a fast ⌘Q after a batch of marks can't exit
  /// before the XMP is on disk. Polls rather than subscribes — the counts are
  /// tiny and infrequent.
  Future<void> drain({
    Duration timeout = const Duration(seconds: 5),
    Duration pollInterval = const Duration(milliseconds: 50),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (state > 0 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollInterval);
    }
  }
}

/// The most recent failed sidecar-write batch. A photo's marks hit the DB (and
/// the grid) instantly, then mirror to its `.xmp`; when that write fails (a
/// read-only volume, a full disk, a removed drive) the count surfaces here —
/// with a monotonic `seq` so two identical-sized failures each still notify —
/// and the page warns instead of the failure being silently invisible.
@Riverpod(keepAlive: true)
class SidecarWriteError extends _$SidecarWriteError {
  @override
  ({int seq, int count}) build() => (seq: 0, count: 0);

  /// Records that [count] photos failed to write their sidecar.
  void report(int count) {
    if (count <= 0) return;
    state = (seq: state.seq + 1, count: count);
  }
}

/// Keeps the read model and XMP sidecars in sync (C1/LR interop). Reports write
/// progress to [SidecarSync] so the UI can show "Syncing N…", and write
/// failures to [SidecarWriteError] so the page can warn.
@Riverpod(keepAlive: true)
MetadataRepository metadataRepository(Ref ref) => MetadataRepository(
  ref.watch(appDatabaseProvider),
  onSync: ref.read(sidecarSyncProvider.notifier).add,
  onWriteError: ref.read(sidecarWriteErrorProvider.notifier).report,
);

/// Repository that imports folders into the read model.
@Riverpod(keepAlive: true)
LibraryRepository libraryRepository(Ref ref) => LibraryRepository(
  ref.watch(appDatabaseProvider),
  metadata: ref.watch(metadataRepositoryProvider),
);

/// Persistent isolate pool that extracts thumbnails (RAW + bitmap), keeping
/// libraw loaded once per worker. Disposed with the app.
@Riverpod(keepAlive: true)
PreviewPool previewPool(Ref ref) {
  final pool = PreviewPool();
  ref.onDispose(pool.dispose);
  return pool;
}

/// The active performance settings (thumbnail px + RAM cache budget).
/// Overridden in main() with the user's chosen preset; the default resolves the
/// recommended preset for this machine, so tests run without an override.
final performanceSettingsProvider = Provider<PerformanceSettings>(
  (ref) => resolvePerformance(
    recommendedPreset(totalBytes: totalPhysicalMemoryBytes()),
    totalBytes: totalPhysicalMemoryBytes(),
  ),
);

/// Two-tier on-disk preview cache wrapping the pool (decode-once). Pruned to
/// the disk budget on creation (startup) so it can't fill the disk over time.
/// Thumbnail resolution + RAM budget come from the active performance preset.
@Riverpod(keepAlive: true)
PreviewCache previewCache(Ref ref) {
  final perf = ref.watch(performanceSettingsProvider);
  final cache = PreviewCache(
    extractor: ref.watch(previewPoolProvider),
    thumbLongEdge: perf.thumbLongEdge,
    // Loupe previews scale to the sharpest connected display so a full-screen
    // loupe stays pixel-perfect on 4K/5K/Retina (fixed 2048px looked soft).
    loupeLongEdge: loupeLongEdgeForDisplays(
      PlatformDispatcher.instance.displays.map((d) => d.size),
    ),
    ramBudgetBytes: perf.ramBudgetBytes,
  );
  unawaited(cache.pruneToBudget());
  return cache;
}

/// Startup seed for [GridCellWidth] — the value persisted last session,
/// overridden in `main()` (default [GridCellWidth.fallback] on first run).
@Riverpod(keepAlive: true)
double gridCellWidthSeed(Ref ref) => GridCellWidth.fallback;

/// Target grid cell width in logical pixels, driven by the toolbar size slider.
/// Only changes how big thumbnails are *drawn* — the cached source stays 512px,
/// so resizing never re-extracts (Photo-Mechanic-style; §7). The size is
/// remembered globally: seeded from the last session and saved (debounced) on
/// change, so the next launch opens at the same zoom.
@Riverpod(keepAlive: true)
class GridCellWidth extends _$GridCellWidth {
  /// Smallest cell width the slider allows.
  static const double min = 120;

  /// Largest cell width the slider allows. The 1024px cached source stays sharp
  /// up to ~512 logical px on a 2× display.
  static const double max = 520;

  /// Default when nothing was saved yet.
  static const double fallback = 200;

  Timer? _saveDebounce;

  @override
  double build() {
    ref.onDispose(() => _saveDebounce?.cancel());
    return ref.watch(gridCellWidthSeedProvider).clamp(min, max);
  }

  /// Sets the target cell width (clamped to [[min], [max]]) and persists it
  /// globally, debounced so dragging the slider doesn't thrash the file.
  void set(double width) {
    state = width.clamp(min, max);
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), () {
      final saved = state;
      unawaited(AppSettings.load().then((s) => s.setGridCellWidth(saved)));
    });
  }
}

/// Startup seed for [TooltipsEnabled] — the value persisted last session,
/// overridden in `main()` (default true on first run / tests).
@Riverpod(keepAlive: true)
bool tooltipsEnabledSeed(Ref ref) => true;

/// Whether button tooltips are shown app-wide (Settings → Interface). Applies
/// immediately (the app wraps its UI in `TooltipVisibility`) and is persisted.
@Riverpod(keepAlive: true)
class TooltipsEnabled extends _$TooltipsEnabled {
  @override
  bool build() => ref.watch(tooltipsEnabledSeedProvider);

  /// Shows or hides tooltips and remembers the choice.
  // ignore: avoid_positional_boolean_parameters — simple flag setter.
  void set(bool value) {
    state = value;
    unawaited(AppSettings.load().then((s) => s.setShowTooltips(value)));
  }
}

/// Startup seed for [AutoAdvanceAfterMark] — the value persisted last session,
/// overridden in `main()` (default false on first run / tests).
@Riverpod(keepAlive: true)
bool autoAdvanceAfterMarkSeed(Ref ref) => false;

/// Whether marking a single photo advances focus to the next one,
/// Photo-Mechanic style (Settings → Interface). Read in the keyboard handler;
/// persisted.
@Riverpod(keepAlive: true)
class AutoAdvanceAfterMark extends _$AutoAdvanceAfterMark {
  @override
  bool build() => ref.watch(autoAdvanceAfterMarkSeedProvider);

  /// Turns auto-advance on or off and remembers the choice.
  // ignore: avoid_positional_boolean_parameters — simple flag setter.
  void set(bool value) {
    state = value;
    unawaited(AppSettings.load().then((s) => s.setAutoAdvanceAfterMark(value)));
  }
}

/// Startup seed for [ShortcutsHintSeen]. **Defaults to true (already seen)** so
/// the first-run cheat sheet only ever fires on a real launch, where `main()`
/// overrides it with the persisted flag — widget tests, which don't override
/// it, never get a surprise dialog popped over the page.
@Riverpod(keepAlive: true)
bool shortcutsHintSeenSeed(Ref ref) => true;

/// Whether the first-run keyboard cheat sheet has already been shown. The cull
/// page pops the sheet once when this is false, then calls [ShortcutsHintSeen.
/// markSeen] to persist it so it never shows again.
@Riverpod(keepAlive: true)
class ShortcutsHintSeen extends _$ShortcutsHintSeen {
  @override
  bool build() => ref.watch(shortcutsHintSeenSeedProvider);

  /// Marks the cheat sheet as seen and remembers it (idempotent).
  void markSeen() {
    if (state) return;
    state = true;
    unawaited(AppSettings.load().then((s) => s.setHasSeenShortcutsHint(true)));
  }
}

/// Startup seed for [MarkConfirmationEnabled]. **Defaults to false** so the
/// loupe's hide-timer never fires unbidden in widget tests; `main()` overrides
/// it with the persisted flag (true by default), so production is on.
@Riverpod(keepAlive: true)
bool markConfirmationEnabledSeed(Ref ref) => false;

/// Whether the loupe flashes an ephemeral mark-confirmation HUD (Settings →
/// Interface). Read live by the loupe; persisted.
@Riverpod(keepAlive: true)
class MarkConfirmationEnabled extends _$MarkConfirmationEnabled {
  @override
  bool build() => ref.watch(markConfirmationEnabledSeedProvider);

  /// Turns the confirmation overlay on or off and remembers the choice.
  // ignore: avoid_positional_boolean_parameters — simple flag setter.
  void set(bool value) {
    state = value;
    unawaited(
      AppSettings.load().then((s) => s.setMarkConfirmationOverlay(value)),
    );
  }
}

/// Startup seed for [FilmstripVisible]. **Defaults to false** so the loupe's
/// filmstrip (and its scroll-into-view animation) never fires unbidden in
/// widget tests; `main()` overrides it with the persisted flag (true by
/// default), so production shows the strip.
@Riverpod(keepAlive: true)
bool filmstripVisibleSeed(Ref ref) => false;

/// Whether the loupe shows its thumbnail filmstrip. Toggled from the loupe;
/// persisted.
@Riverpod(keepAlive: true)
class FilmstripVisible extends _$FilmstripVisible {
  @override
  bool build() => ref.watch(filmstripVisibleSeedProvider);

  /// Shows or hides the filmstrip and remembers the choice.
  // ignore: avoid_positional_boolean_parameters — simple flag setter.
  void set(bool value) {
    state = value;
    unawaited(AppSettings.load().then((s) => s.setFilmstripVisible(value)));
  }
}

/// Whether the loupe shows the RGB histogram panel. Session state — not
/// persisted, a panel toggle need not survive relaunch (mirrors
/// `InspectorOpen`).
@riverpod
class LoupeHistogramVisible extends _$LoupeHistogramVisible {
  @override
  bool build() => false;

  /// Flips the histogram panel on/off.
  void toggle() => state = !state;
}

/// Whether the loupe tints blown highlights (red) and crushed shadows (blue)
/// over the photo. Session state — not persisted.
@riverpod
class LoupeClippingVisible extends _$LoupeClippingVisible {
  @override
  bool build() => false;

  /// Flips the clipping-warning overlay on/off.
  void toggle() => state = !state;
}

/// Whether the loupe overlays a focus-peaking edge map over the photo (pure
/// gradient-magnitude signal processing, not AI). Session state — not
/// persisted.
@riverpod
class LoupeFocusPeakingVisible extends _$LoupeFocusPeakingVisible {
  @override
  bool build() => false;

  /// Flips the focus-peaking overlay on/off.
  void toggle() => state = !state;
}

/// Startup seed for [RecentFolders] — the paths persisted last session,
/// overridden in `main()` (empty on first run / tests).
@Riverpod(keepAlive: true)
List<String> recentFoldersSeed(Ref ref) => const [];

/// The recently-opened folders (most-recent-first) behind the "Open recent"
/// menu. Updated whenever a folder is opened; persisted.
@Riverpod(keepAlive: true)
class RecentFolders extends _$RecentFolders {
  @override
  List<String> build() => ref.watch(recentFoldersSeedProvider);

  /// Promotes [path] to the front (dedup + capped) and remembers the list.
  void add(String path) {
    final next = promoteRecentFolder(state, path);
    if (listEquals(next, state)) return;
    state = next;
    unawaited(AppSettings.load().then((s) => s.setRecentFolders(next)));
  }

  /// Drops [path] from the list (e.g. a folder that no longer exists).
  void remove(String path) {
    if (!state.contains(path)) return;
    state = [
      for (final p in state)
        if (p != path) p,
    ];
    final next = state;
    unawaited(AppSettings.load().then((s) => s.setRecentFolders(next)));
  }
}

/// A mark just applied in the loupe, for the ephemeral confirmation HUD.
/// Emitted by the mark action (keyboard or toolbar), not derived from the shown
/// photo — so the flash still fires when auto-advance has already blitted on.
/// [seq] bumps on every push so re-applying the same mark re-triggers it.
class LoupeMarkSignal {
  /// Creates a signal for exactly one applied mark dimension.
  const LoupeMarkSignal({
    required this.seq,
    this.rating,
    this.flag,
    this.color,
  });

  /// Monotonic id so identical repeats still register as a new flash.
  final int seq;

  /// The applied rating (0 = cleared), or null when this isn't a rating.
  final int? rating;

  /// The applied pick/reject flag, or null when this isn't a flag.
  final PickFlag? flag;

  /// The applied colour label, or null when this isn't a colour.
  final ColorLabel? color;
}

/// Signals the loupe's mark-confirmation HUD. The loupe listens; the keyboard
/// handler and loupe toolbar push here when a mark is applied in the loupe.
@Riverpod(keepAlive: true)
class LoupeMarkFlash extends _$LoupeMarkFlash {
  int _seq = 0;

  @override
  LoupeMarkSignal? build() => null;

  /// Flashes a rating (0 = cleared).
  void rating(int value) => state = LoupeMarkSignal(seq: ++_seq, rating: value);

  /// Flashes a pick/reject flag.
  void flag(PickFlag value) =>
      state = LoupeMarkSignal(seq: ++_seq, flag: value);

  /// Flashes a colour label.
  void color(ColorLabel value) =>
      state = LoupeMarkSignal(seq: ++_seq, color: value);
}

/// Startup seed for [CullShortcuts] — persisted overrides from last session,
/// overridden in `main()` (empty = all defaults, on first run / tests).
@Riverpod(keepAlive: true)
Map<String, int> cullShortcutsSeed(Ref ref) => const {};

/// The resolved cull keymap (defaults + user rebindings), used by the grid key
/// handler and the shortcuts UI. Rebinding applies immediately and persists.
@Riverpod(keepAlive: true)
class CullShortcutsController extends _$CullShortcutsController {
  @override
  CullShortcuts build() =>
      CullShortcuts.fromOverrides(ref.watch(cullShortcutsSeedProvider));

  /// Rebinds [action] to [key] (caller has already checked it's assignable and
  /// resolved any conflict) and persists the change.
  void rebind(CullAction action, LogicalKeyboardKey key) {
    state = state.withBinding(action, key);
    _persist();
  }

  /// Restores every action to its default key.
  void resetDefaults() {
    state = CullShortcuts.defaults();
    _persist();
  }

  void _persist() {
    final overrides = state.toOverrides();
    unawaited(
      AppSettings.load().then((s) => s.setShortcutOverrides(overrides)),
    );
  }
}

/// Persisted loupe zoom — the *mode* (Fit / 100% / custom) plus the custom
/// scale. Kept alive so the choice carries across photo navigation and loupe
/// close/reopen. We store the mode, not a raw scale, because the absolute scale
/// that means "100%" differs per photo and viewport — restoring the number
/// would land on the wrong zoom (see [LoupeZoom.scaleForMode]).
@Riverpod(keepAlive: true)
class LoupeZoomLevel extends _$LoupeZoomLevel {
  @override
  ({LoupeZoomMode mode, double customScale}) build() =>
      (mode: LoupeZoomMode.fit, customScale: 1);

  /// Records the current zoom [mode]; [customScale] is kept for
  /// [LoupeZoomMode.custom] so a dialled-in zoom restores exactly.
  void set(LoupeZoomMode mode, double customScale) => state = (
    mode: mode,
    customScale: mode == LoupeZoomMode.custom ? customScale : state.customScale,
  );
}

/// One open folder in the workspace — a Photo-Mechanic-style tab. Carries its
/// own view state ([selection]/[filter]) so switching tabs restores where you
/// were. The page saves the live state into the active tab before switching and
/// restores the incoming tab's afterwards.
class CullTab {
  /// Creates a tab.
  const CullTab({
    required this.importId,
    required this.sourcePath,
    required this.label,
    this.selection = const CullSelection(),
    this.filter = const PhotoFilter(),
    this.sort = const PhotoSort(),
    this.scrollOffset = 0,
  });

  /// The import (folder) shown in this tab.
  final int importId;

  /// Absolute path of the folder (for ejection/deletion detection).
  final String sourcePath;

  /// Short display label (folder name).
  final String label;

  /// Saved focus/selection for this tab.
  final CullSelection selection;

  /// Saved grid filter for this tab.
  final PhotoFilter filter;

  /// Saved grid sort order for this tab.
  final PhotoSort sort;

  /// Saved grid scroll offset, restored on switch so each tab reopens where you
  /// left it (and a fresh tab starts at the top).
  final double scrollOffset;

  /// Returns a copy with the given fields replaced.
  CullTab copyWith({
    CullSelection? selection,
    PhotoFilter? filter,
    PhotoSort? sort,
    double? scrollOffset,
  }) => CullTab(
    importId: importId,
    sourcePath: sourcePath,
    label: label,
    selection: selection ?? this.selection,
    filter: filter ?? this.filter,
    sort: sort ?? this.sort,
    scrollOffset: scrollOffset ?? this.scrollOffset,
  );
}

/// The open tabs plus which one is active.
class WorkspaceState {
  /// Creates a workspace state.
  const WorkspaceState({this.tabs = const [], this.activeIndex = 0});

  /// The open tabs, in bar order.
  final List<CullTab> tabs;

  /// Index of the active tab in [tabs] (ignored when [tabs] is empty).
  final int activeIndex;

  /// The active tab, or `null` when nothing is open.
  CullTab? get active =>
      (tabs.isEmpty || activeIndex >= tabs.length) ? null : tabs[activeIndex];
}

/// Holds the open folders as tabs. Deliberately "dumb" — it never reaches into
/// the live [CullController]/filter providers; the page orchestrates saving and
/// restoring per-tab view state around [activate]/[openImport]/[close].
@Riverpod(keepAlive: true)
class Workspace extends _$Workspace {
  @override
  WorkspaceState build() => const WorkspaceState();

  /// Opens [importId] as a tab: activates an existing tab for it, or appends a
  /// new one and activates that. Returns the (now active) tab's index.
  int openImport({
    required int importId,
    required String sourcePath,
    required String label,
  }) {
    final existing = state.tabs.indexWhere((t) => t.importId == importId);
    if (existing >= 0) {
      state = WorkspaceState(tabs: state.tabs, activeIndex: existing);
      return existing;
    }
    final tabs = [
      ...state.tabs,
      CullTab(importId: importId, sourcePath: sourcePath, label: label),
    ];
    state = WorkspaceState(tabs: tabs, activeIndex: tabs.length - 1);
    return tabs.length - 1;
  }

  /// Makes the tab at [index] active.
  void activate(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    state = WorkspaceState(tabs: state.tabs, activeIndex: index);
  }

  /// Stores the live view state into the active tab (call before switching).
  void saveActive({
    required CullSelection selection,
    required PhotoFilter filter,
    required PhotoSort sort,
    required double scrollOffset,
  }) {
    final tab = state.active;
    if (tab == null) return;
    final tabs = [...state.tabs];
    tabs[state.activeIndex] = tab.copyWith(
      selection: selection,
      filter: filter,
      sort: sort,
      scrollOffset: scrollOffset,
    );
    state = WorkspaceState(tabs: tabs, activeIndex: state.activeIndex);
  }

  /// Closes the tab at [index], keeping a sensible neighbour active.
  void close(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    final tabs = [...state.tabs]..removeAt(index);
    final active = state.activeIndex > index
        ? state.activeIndex - 1
        : state.activeIndex.clamp(0, tabs.isEmpty ? 0 : tabs.length - 1);
    state = WorkspaceState(tabs: tabs, activeIndex: active);
  }

  /// Closes every tab (e.g. the active folder vanished).
  void clear() => state = const WorkspaceState();
}

/// The currently open import (folder), derived from the active tab, or `null`
/// before any folder is opened.
final currentImportProvider = Provider<int?>(
  (ref) => ref.watch(workspaceProvider).active?.importId,
  name: 'currentImport',
);

/// Reactive list of photos for the open import (empty when none is open).
///
/// Written as a classic [StreamProvider] rather than codegen: the generator
/// can't convert the drift-generated `Photo` type (it lives in a `part` file)
/// and throws InvalidTypeException. Mixing both provider styles is supported.
final photosProvider = StreamProvider<List<Photo>>((ref) {
  final importId = ref.watch(currentImportProvider);
  if (importId == null) return Stream.value(const []);
  return ref.watch(libraryRepositoryProvider).watchImport(importId);
}, name: 'photos');

/// The saved selections for the open import (empty when none is open). Classic
/// provider because it exposes the drift-generated `SavedSelection` type.
final savedSelectionsProvider = StreamProvider<List<SavedSelection>>((ref) {
  final importId = ref.watch(currentImportProvider);
  if (importId == null) return Stream.value(const []);
  return ref.watch(appDatabaseProvider).watchSavedSelections(importId);
});

/// Whether the preview providers retry a transient null. **Defaults to false**
/// so the retry's back-off timers never linger in widget tests (which render
/// the grid with a stub cache that always misses); `main()` overrides it to
/// true so production actually retries. A plain seed provider — there's nothing
/// to toggle at runtime.
@Riverpod(keepAlive: true)
bool previewRetryEnabled(Ref ref) => false;

/// Decoded preview bytes for [path]. Auto-dispose: when the cell scrolls
/// off-screen the provider is disposed, which cancels the still-queued pool job
/// so the visible cells jump ahead (`BUILD_PLAN.md` §2).
///
/// Retries a *transient* null (a cold Dropbox/network file that tripped the
/// pool's watchdog before it hydrated) so the cell doesn't stay blank forever
/// after a later pass fills the cache — see [retryPreview].
@riverpod
Future<Uint8List?> thumbnail(Ref ref, String path) {
  final cancel = CancelToken();
  ref.onDispose(cancel.cancel);
  final cache = ref.watch(previewCacheProvider);
  final retry = ref.watch(previewRetryEnabledProvider);
  return retryPreview(
    () => cache.thumbnail(path, cancel: cancel),
    isCancelled: () => cancel.isCancelled,
    retryable: retry && !isVideoPath(path),
  );
}

/// Screen-res loupe preview bytes for [path] (scaled to the display's pixel
/// long edge), for the fullscreen loupe view. Auto-dispose: closing the loupe
/// (or blitting past a neighbour) cancels the still-queued pool job so the
/// photo on screen renders first.
@riverpod
Future<Uint8List?> loupePreview(Ref ref, String path) {
  final cancel = CancelToken();
  ref.onDispose(cancel.cancel);
  final cache = ref.watch(previewCacheProvider);
  final retry = ref.watch(previewRetryEnabledProvider);
  return retryPreview(
    () => cache.get(path, PreviewTier.loupe, cancel: cancel),
    isCancelled: () => cancel.isCancelled,
    retryable: retry && !isVideoPath(path),
  );
}

/// Full-resolution source bytes for [path] — the original bitmap or a RAW's
/// full embedded JPEG — loaded lazily only when the loupe zooms in, so 100% is
/// true 1:1 pixel-peeping instead of an upscaled preview. Auto-dispose: leaving
/// the photo (or the loupe) cancels the pending decode.
@riverpod
Future<Uint8List?> loupeFullPreview(Ref ref, String path) {
  final cancel = CancelToken();
  ref.onDispose(cancel.cancel);
  final cache = ref.watch(previewCacheProvider);
  final retry = ref.watch(previewRetryEnabledProvider);
  return retryPreview(
    () => cache.get(path, PreviewTier.full, cancel: cancel),
    isCancelled: () => cancel.isCancelled,
    retryable: retry && !isVideoPath(path),
  );
}

/// Keyboard focus + multi-selection for the grid.
class CullSelection {
  /// Creates a selection state.
  const CullSelection({
    this.focusedId,
    this.anchorId,
    this.selectedIds = const {},
  });

  /// The id of the focused photo, or `null` when nothing is focused.
  final int? focusedId;

  /// Anchor for Shift-range selection — the last single click / toggle.
  final int? anchorId;

  /// Ids of photos in the current selection.
  final Set<int> selectedIds;

  /// The ids cull marks should apply to: the selection when the focused photo
  /// is part of it, otherwise the focused photo alone. So a single click or
  /// keyboard navigation marks one photo, while a built-up selection marks all.
  Set<int> get markTargets {
    if (selectedIds.isNotEmpty &&
        focusedId != null &&
        selectedIds.contains(focusedId)) {
      return selectedIds;
    }
    return {?focusedId};
  }

  /// Returns a copy with the given fields replaced.
  CullSelection copyWith({
    int? focusedId,
    int? anchorId,
    Set<int>? selectedIds,
  }) => CullSelection(
    focusedId: focusedId ?? this.focusedId,
    anchorId: anchorId ?? this.anchorId,
    selectedIds: selectedIds ?? this.selectedIds,
  );
}

/// Owns grid focus/selection and writes cull marks straight to the read model
/// (the reactive `photos` stream reflects them immediately).
///
/// keepAlive: focus/selection is session state, and it must survive the async
/// gaps inside a mark write (DB + sidecar) without the Ref being disposed.
@Riverpod(keepAlive: true)
class CullController extends _$CullController {
  @override
  CullSelection build() => const CullSelection();

  AppDatabase get _db => ref.read(appDatabaseProvider);
  MetadataRepository get _meta => ref.read(metadataRepositoryProvider);

  // Session-wide undo/redo for mark changes (rating/flag/colour/rotation).
  // Lives on the notifier (keepAlive) so it survives tab switches; batch
  // operations are recorded as one entry, so one ⌘Z takes back the whole batch.
  final UndoHistory _history = UndoHistory();

  /// Replaces the whole focus/selection state — used to restore a tab's saved
  /// view when switching tabs.
  // ignore: use_setters_to_change_properties
  void restore(CullSelection selection) => state = selection;

  /// Moves keyboard focus to [photoId] (cursor only — leaves the selection so
  /// you can navigate within or away from a built-up selection). The anchor
  /// follows focus so a later Shift-range starts from here.
  void focus(int photoId) =>
      state = state.copyWith(focusedId: photoId, anchorId: photoId);

  /// Selects only [photoId] (plain click): the selection becomes this photo,
  /// which also becomes the focus and the Shift-range anchor.
  void selectOnly(int photoId) => state = state.copyWith(
    focusedId: photoId,
    anchorId: photoId,
    selectedIds: {photoId},
  );

  /// Adds/removes [photoId] from the selection (Space / ⌘-click) and focuses it.
  void toggleSelect(int photoId) {
    final next = {...state.selectedIds};
    if (!next.add(photoId)) next.remove(photoId);
    state = state.copyWith(
      focusedId: photoId,
      anchorId: photoId,
      selectedIds: next,
    );
  }

  /// Selects the contiguous range between the anchor (or current focus) and
  /// [photoId] over [orderedIds] — the photos as the grid currently shows them
  /// (Shift-click). Focus moves to [photoId]; the anchor stays put.
  void extendSelectionTo(int photoId, List<int> orderedIds) {
    final anchor = state.anchorId ?? state.focusedId ?? photoId;
    final from = orderedIds.indexOf(anchor);
    final to = orderedIds.indexOf(photoId);
    if (from < 0 || to < 0) {
      selectOnly(photoId);
      return;
    }
    final lo = from < to ? from : to;
    final hi = from < to ? to : from;
    state = state.copyWith(
      focusedId: photoId,
      selectedIds: orderedIds.sublist(lo, hi + 1).toSet(),
    );
  }

  /// Drops [removedIds] from focus/selection/anchor after their photos were
  /// deleted, leaving the rest of the selection intact.
  void pruneMissing(Set<int> removedIds) {
    state = CullSelection(
      focusedId: removedIds.contains(state.focusedId) ? null : state.focusedId,
      anchorId: removedIds.contains(state.anchorId) ? null : state.anchorId,
      selectedIds: {
        for (final id in state.selectedIds)
          if (!removedIds.contains(id)) id,
      },
    );
  }

  /// Replaces the selection wholesale (e.g. from an imported Picdrop/CSV list)
  /// and focuses the first selected photo.
  void setSelection(Set<int> ids) {
    state = state.copyWith(
      selectedIds: ids,
      focusedId: ids.isEmpty ? state.focusedId : ids.first,
      anchorId: ids.isEmpty ? state.anchorId : ids.first,
    );
  }

  /// Sets [rating] on every [CullSelection.markTargets] photo (batch marking).
  Future<void> applyRating(int rating) =>
      _setRatingAll(state.markTargets, rating);

  /// Sets [flag] on every [CullSelection.markTargets] photo (batch marking).
  Future<void> applyFlag(PickFlag flag) => _setFlagAll(state.markTargets, flag);

  /// Sets [label] on every [CullSelection.markTargets] photo (batch marking).
  Future<void> applyColor(ColorLabel label) =>
      _setColorAll(state.markTargets, label);

  /// Rotates every [CullSelection.markTargets] photo by [quarterTurnsCW]
  /// clockwise quarter-turns (negative = counter-clockwise). Batch rotate.
  Future<void> applyRotation(int quarterTurnsCW) =>
      _rotateAll(state.markTargets.toList(), quarterTurnsCW);

  /// Undoes the most recent mark change (rating/flag/colour/rotation), batch
  /// or single. Returns a short description for the notice bar ("rating
  /// (3 photos)"), or `null` when there is nothing to undo.
  Future<String?> undo() async {
    final entry = _history.takeUndo();
    if (entry == null) return null;
    await _revert(entry);
    return entry.describe();
  }

  /// Re-applies the most recently undone mark change. Returns its description,
  /// or `null` when there is nothing to redo.
  Future<String?> redo() async {
    final entry = _history.takeRedo();
    if (entry == null) return null;
    await _reapply(entry);
    return entry.describe();
  }

  /// Forgets the undo/redo history (call when photos are removed from disk, so
  /// stale entries can't "restore" marks onto reused ids).
  void clearHistory() => _history.clear();

  // Undo/redo apply their DB writes in one transaction (single stream emit)
  // and mirror the sidecars in one batch, like a fresh batch mark.
  Future<void> _revert(CullUndoEntry entry) async {
    switch (entry) {
      case RatingUndoEntry(:final before):
        await _db.setRatings(before);
        await _meta.writeSidecarsForPhotos(before.keys.toList());
      case FlagUndoEntry(:final before):
        await _db.setFlags(before);
        await _meta.writeSidecarsForPhotos(before.keys.toList());
      case ColorUndoEntry(:final before):
        await _db.setColorLabels(before);
        await _meta.writeSidecarsForPhotos(before.keys.toList());
      case RotationUndoEntry(:final photoIds, :final quarterTurnsCW):
        for (final id in photoIds) {
          await _rotateOne(id, -quarterTurnsCW);
        }
    }
  }

  Future<void> _reapply(CullUndoEntry entry) async {
    switch (entry) {
      case RatingUndoEntry(:final before, :final after):
        await _db.setRatingAll(before.keys.toList(), after);
        await _meta.writeSidecarsForPhotos(before.keys.toList());
      case FlagUndoEntry(:final before, :final after):
        await _db.setFlagAll(before.keys.toList(), after);
        await _meta.writeSidecarsForPhotos(before.keys.toList());
      case ColorUndoEntry(:final before, :final after):
        await _db.setColorLabelAll(before.keys.toList(), after);
        await _meta.writeSidecarsForPhotos(before.keys.toList());
      case RotationUndoEntry(:final photoIds, :final quarterTurnsCW):
        for (final id in photoIds) {
          await _rotateOne(id, quarterTurnsCW);
        }
    }
  }

  /// The current rows for [ids] (missing ids are simply absent) — the
  /// before-values an undo entry captures.
  Future<List<Photo>> _photosByIds(Set<int> ids) =>
      (_db.select(_db.photos)..where((t) => t.id.isIn(ids.toList()))).get();

  // The batch mark paths: one UPDATE for the whole batch (single stream emit,
  // one grid rebuild), then the sidecar mirror as one batch (§0.6).
  Future<void> _setRatingAll(Set<int> ids, int rating) async {
    final rows = await _photosByIds(ids);
    if (rows.isEmpty) return;
    _history.push(
      RatingUndoEntry(
        before: {for (final r in rows) r.id: r.rating},
        after: rating,
      ),
    );
    final idList = [for (final r in rows) r.id];
    await _db.setRatingAll(idList, rating);
    await _meta.writeSidecarsForPhotos(idList);
  }

  Future<void> _setFlagAll(Set<int> ids, PickFlag flag) async {
    final rows = await _photosByIds(ids);
    if (rows.isEmpty) return;
    _history.push(
      FlagUndoEntry(before: {for (final r in rows) r.id: r.flag}, after: flag),
    );
    final idList = [for (final r in rows) r.id];
    await _db.setFlagAll(idList, flag);
    await _meta.writeSidecarsForPhotos(idList);
  }

  Future<void> _setColorAll(Set<int> ids, ColorLabel label) async {
    final rows = await _photosByIds(ids);
    if (rows.isEmpty) return;
    _history.push(
      ColorUndoEntry(
        before: {for (final r in rows) r.id: r.colorLabel},
        after: label,
      ),
    );
    final idList = [for (final r in rows) r.id];
    await _db.setColorLabelAll(idList, label);
    await _meta.writeSidecarsForPhotos(idList);
  }

  Future<void> _rotateAll(List<int> ids, int quarterTurnsCW) async {
    if (ids.isEmpty) return;
    _history.push(
      RotationUndoEntry(photoIds: ids, quarterTurnsCW: quarterTurnsCW),
    );
    for (final id in ids) {
      await _rotateOne(id, quarterTurnsCW);
    }
  }

  /// Rotates a photo by [quarterTurnsCW] clockwise quarter-turns (undoable).
  Future<void> rotate(int photoId, int quarterTurnsCW) =>
      _rotateAll([photoId], quarterTurnsCW);

  /// Rotates a photo by [quarterTurnsCW] clockwise quarter-turns.
  ///
  /// For a JPEG we *commit* the new orientation into the file's embedded EXIF
  /// (losslessly) so Finder/Preview and our own re-decoded preview both show
  /// it; the baked preview then already carries the rotation, so we clear the
  /// widget-layer delta (`user_rotation` → 0) to avoid rotating twice, and
  /// evict the stale cached preview. For RAW (embedded EXIF not writable)
  /// we keep the rotation as a widget-layer delta. Either way the new effective
  /// orientation is mirrored to the XMP sidecar (`tiff:Orientation`).
  Future<void> _rotateOne(int photoId, int quarterTurnsCW) async {
    final photo = await (_db.select(
      _db.photos,
    )..where((t) => t.id.equals(photoId))).getSingleOrNull();
    if (photo == null) return;

    final effective = rotateOrientation(
      photo.orientation,
      photo.userRotation + quarterTurnsCW,
    );
    final committed = await writeEmbeddedOrientation(photo.path, effective);
    if (committed) {
      await _db.setBakedOrientation(photoId, effective);
      // The file's EXIF (and thus what libvips bakes) changed → drop the stale
      // in-RAM previews and re-fetch so the grid + loupe re-decode.
      ref.read(previewCacheProvider).evict(photo.path);
      ref
        ..invalidate(thumbnailProvider(photo.path))
        ..invalidate(loupePreviewProvider(photo.path));
    } else {
      await _db.rotatePhoto(photoId, quarterTurnsCW);
    }
    await _meta.writeSidecarForPhoto(photoId);
  }

  /// Sets the star rating (0 clears it) and mirrors it to the XMP sidecar.
  /// Undoable.
  Future<void> setRating(int photoId, int rating) =>
      _setRatingAll({photoId}, rating);

  /// Sets the pick/reject flag and mirrors it to the XMP sidecar. Undoable.
  Future<void> setFlag(int photoId, PickFlag flag) =>
      _setFlagAll({photoId}, flag);

  /// Sets the colour label and mirrors it to the XMP sidecar. Undoable.
  Future<void> setColor(int photoId, ColorLabel label) =>
      _setColorAll({photoId}, label);

  /// Replaces the keyword list and mirrors it to the sidecar (`dc:subject`).
  Future<void> setKeywords(int photoId, List<String> keywords) async {
    await _db.setKeywords(photoId, keywords);
    await _meta.writeSidecarForPhoto(photoId);
  }

  /// Replaces the descriptive IPTC Core fields and mirrors them to the sidecar.
  Future<void> setIptc(int photoId, IptcCore iptc) async {
    await _db.setIptc(photoId, iptc);
    await _meta.writeSidecarForPhoto(photoId);
  }

  /// Writes both IPTC fields and keywords for a photo in one sidecar flush —
  /// used by template application, which can change both at once.
  Future<void> setIptcAndKeywords(
    int photoId,
    IptcCore iptc,
    List<String> keywords,
  ) async {
    await _db.setIptc(photoId, iptc);
    await _db.setKeywords(photoId, keywords);
    await _meta.writeSidecarForPhoto(photoId);
  }
}
