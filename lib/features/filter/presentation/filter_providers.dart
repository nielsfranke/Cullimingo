import 'dart:async';

import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/settings/app_settings.dart';
import 'package:cullimingo/features/cull/domain/duplicate_groups.dart';
import 'package:cullimingo/features/cull/domain/exposure_brackets.dart';
import 'package:cullimingo/features/cull/domain/raw_jpeg_pairs.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/filter/domain/filename_match.dart';
import 'package:cullimingo/features/filter/domain/filter_preset.dart';
import 'package:cullimingo/features/filter/domain/photo_filter.dart';
import 'package:cullimingo/features/filter/domain/photo_sort.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'filter_providers.g.dart';

/// Holds the active grid filter and toggles for the quick-filter chips.
@riverpod
class PhotoFilterController extends _$PhotoFilterController {
  @override
  PhotoFilter build() => const PhotoFilter();

  /// Clears all constraints ("All").
  void clear() => state = const PhotoFilter();

  /// Replaces the whole filter — restores a tab's saved filter on switch.
  // ignore: use_setters_to_change_properties
  void restore(PhotoFilter filter) => state = filter;

  /// Sets the minimum rating, toggling off if already at [rating].
  void toggleMinRating(int rating) =>
      state = state.withMinRating(state.minRating == rating ? 0 : rating);

  /// Sets the flag constraint, toggling off if already [flag].
  void toggleFlag(PickFlag flag) =>
      state = state.withFlag(state.flag == flag ? null : flag);

  /// Sets the colour constraint, toggling off if already [color].
  void toggleColor(ColorLabel color) =>
      state = state.withColor(state.color == color ? null : color);

  /// Toggles the "has keyword" constraint.
  void toggleHasKeyword() => state = state.withHasKeyword(!state.hasKeyword);

  /// Toggles the "needs caption" constraint (the caption-pass view).
  void toggleNeedsCaption() =>
      state = state.withNeedsCaption(!state.needsCaption);

  /// Toggles the "selected only" quick-filter.
  void toggleSelectedOnly() =>
      state = state.withSelectedOnly(!state.selectedOnly);

  /// Toggles the "bursts only" quick-filter.
  void toggleBurstsOnly() => state = state.withBurstsOnly(!state.burstsOnly);

  /// Toggles the "hide JPEG (RAW+JPEG)" quick-filter.
  void toggleHideJpegPairs() =>
      state = state.withHideJpegPairs(!state.hideJpegPairs);

  /// Toggles the "collapse exposure brackets" quick-filter.
  void toggleCollapseBrackets() =>
      state = state.withCollapseBrackets(!state.collapseBrackets);
}

/// Startup seed for [FilterPresets] — the presets persisted last session,
/// overridden in `main()` (empty on first run / tests).
@Riverpod(keepAlive: true)
List<FilterPreset> filterPresetsSeed(Ref ref) => const [];

/// The user's saved, named grid-filter presets (`BUILD_PLAN.md` §5). Global —
/// a filter carries no import-specific data — so a preset is offered on every
/// shoot. Applied via [PhotoFilterController.restore]; persisted to settings.
@Riverpod(keepAlive: true)
class FilterPresets extends _$FilterPresets {
  @override
  List<FilterPreset> build() => ref.watch(filterPresetsSeedProvider);

  /// Saves [filter] under [name] (trimmed), replacing any preset with the same
  /// name (case-insensitive) and appending new ones last. [PhotoFilter.
  /// selectedOnly] is stripped — it references the live selection, so it can't
  /// be part of a reusable preset. A blank name is ignored.
  void save(String name, PhotoFilter filter) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final lower = trimmed.toLowerCase();
    state = [
      for (final p in state)
        if (p.name.toLowerCase() != lower) p,
      FilterPreset(name: trimmed, filter: filter.withSelectedOnly(false)),
    ];
    _persist();
  }

  /// Removes the preset named [name] (case-insensitive).
  void delete(String name) {
    final lower = name.toLowerCase();
    state = [
      for (final p in state)
        if (p.name.toLowerCase() != lower) p,
    ];
    _persist();
  }

  void _persist() {
    final snapshot = FilterPreset.encodeList(state);
    unawaited(AppSettings.load().then((s) => s.setFilterPresets(snapshot)));
  }
}

/// Holds the active grid sort order (top-bar sort control, `BUILD_PLAN.md` §7).
@riverpod
class PhotoSortController extends _$PhotoSortController {
  @override
  PhotoSort build() => const PhotoSort();

  /// Orders the grid by [key], keeping the current direction.
  void setKey(PhotoSortKey key) => state = state.withKey(key);

  /// Flips ascending ↔ descending.
  void toggleDirection() => state = state.toggled();

  /// Replaces the whole sort — restores a tab's saved order on switch.
  // ignore: use_setters_to_change_properties
  void restore(PhotoSort sort) => state = sort;
}

/// Capture-time burst grouping over the current import's photos (§8). Classic
/// provider — it reads the drift-generated `Photo` type via [photosProvider].
final burstGroupsProvider = Provider<BurstGroups>((ref) {
  final photos = ref.watch(photosProvider).value ?? const <Photo>[];
  return BurstGroups(
    groupByCaptureTime([
      for (final p in photos)
        (id: p.id, capturedAt: p.capturedAt, camera: p.camera),
    ]),
  );
}, name: 'burstGroups');

/// RAW+JPEG pairing over the current import's photos (§8). Classic provider —
/// it reads the drift-generated `Photo` type via [photosProvider].
final rawJpegPairsProvider = Provider<RawJpegPairs>((ref) {
  final photos = ref.watch(photosProvider).value ?? const <Photo>[];
  return RawJpegPairs([
    for (final p in photos) (id: p.id, path: p.path, isRaw: p.isRaw),
  ]);
}, name: 'rawJpegPairs');

/// Exposure-bracket grouping over the current import's photos (§8). Classic
/// provider — it reads the drift-generated `Photo` type via [photosProvider].
/// The hidden JPEG side of a RAW+JPEG pair is kept out of the grouping input (a
/// duplicated exposure would trip the repeat-boundary rule) and folded back in
/// afterwards so expanding a selection still grabs both files.
final bracketGroupsProvider = Provider<BracketGroups>((ref) {
  final photos = ref.watch(photosProvider).value ?? const <Photo>[];
  final hiddenJpeg = ref.watch(rawJpegPairsProvider).hiddenJpegIds;

  // A RAW's hidden JPEG sibling shares its normalized basename — map each
  // grouping-visible photo to the hidden siblings that should rejoin its stack.
  final visible = [
    for (final p in photos)
      if (!hiddenJpeg.contains(p.id)) p,
  ];
  final hiddenByName = <String, List<int>>{};
  for (final p in photos) {
    if (hiddenJpeg.contains(p.id)) {
      hiddenByName.putIfAbsent(normalizeName(p.path), () => []).add(p.id);
    }
  }
  final siblings = <int, List<int>>{};
  for (final p in visible) {
    final ids = hiddenByName[normalizeName(p.path)];
    if (ids != null) siblings[p.id] = ids;
  }

  return BracketGroups([
    for (final p in visible)
      (
        id: p.id,
        capturedAt: p.capturedAt,
        camera: p.camera,
        exposureBias: p.exposureBias,
        exposureTime: p.exposureTime,
      ),
  ], siblings: siblings);
}, name: 'bracketGroups');

/// On-demand perceptual-hash similarity groups (§8), **per import** so running
/// "Find similar" in one folder doesn't switch every other tab to similarity
/// mode. Empty until the user runs the pass for a folder.
@riverpod
class SimilarGroups extends _$SimilarGroups {
  @override
  Map<int, BurstGroups> build() => const {};

  /// Stores a freshly computed similarity grouping for [importId].
  void setFor(int importId, BurstGroups groups) =>
      state = {...state, importId: groups};

  /// Drops the similarity grouping for [importId] (reverts it to bursts).
  void clearFor(int importId) => state = {
    for (final e in state.entries)
      if (e.key != importId) e.key: e.value,
  };
}

/// The computed similarity grouping for the *current* import, or null.
final currentSimilarGroupsProvider = Provider<BurstGroups?>((ref) {
  final importId = ref.watch(currentImportProvider);
  if (importId == null) return null;
  return ref.watch(similarGroupsProvider)[importId];
}, name: 'currentSimilarGroups');

/// The grouping the UI surfaces (badge / chip / compare-group): the current
/// import's computed similarity groups when present, else its capture-time
/// bursts.
final effectiveGroupsProvider = Provider<BurstGroups>(
  (ref) =>
      ref.watch(currentSimilarGroupsProvider) ?? ref.watch(burstGroupsProvider),
  name: 'effectiveGroups',
);

/// The photos shown in the grid after the active filter is applied. Classic
/// provider because it exposes the drift-generated `Photo` type (codegen can't
/// convert it — see [photosProvider]).
final filteredPhotosProvider = Provider<List<Photo>>((ref) {
  final photos = ref.watch(photosProvider).value ?? const <Photo>[];
  final filter = ref.watch(photoFilterControllerProvider);
  final sort = ref.watch(photoSortControllerProvider);

  // The base list after filtering (still in DB order: capture time then path).
  List<Photo> base;
  if (!filter.isActive) {
    base = photos;
  } else {
    // `selectedOnly` is the one constraint PhotoFilter can't judge alone — it
    // needs the live grid selection.
    final selectedIds = filter.selectedOnly
        ? ref.watch(cullControllerProvider.select((s) => s.selectedIds))
        : null;
    // `hideJpegPairs`: drop the JPEG side of a RAW+JPEG pair (the RAW stays).
    // Pairing lives outside the value object, so apply it here.
    final hiddenJpeg = filter.hideJpegPairs
        ? ref.watch(rawJpegPairsProvider).hiddenJpegIds
        : null;
    // `collapseBrackets`: hide the non-reference frames of each exposure
    // bracket so the grid shows one cell (the normal exposure) per stack.
    final hiddenBracket = filter.collapseBrackets
        ? ref.watch(bracketGroupsProvider).collapsedHiddenIds
        : null;
    bool passes(Photo p) =>
        filter.matches(p) &&
        (selectedIds == null || selectedIds.contains(p.id)) &&
        (hiddenJpeg == null || !hiddenJpeg.contains(p.id)) &&
        (hiddenBracket == null || !hiddenBracket.contains(p.id));

    // `burstsOnly`: show only photos in a group (≥2), and lay each group out
    // contiguously (members together, groups in capture order) so it's obvious
    // which photos belong together — the value object can't do either. Burst
    // grouping owns the layout, so the user sort doesn't apply in this view.
    if (filter.burstsOnly) {
      return groupContiguous(
        ref.watch(effectiveGroupsProvider).groups,
        {for (final p in photos) p.id: p},
        passes,
      );
    }
    base = photos.where(passes).toList();
  }
  // The default sort == the DB order, so skip the re-sort in the common case.
  return sort.isDefault ? base : sort.sort(base);
}, name: 'filteredPhotos');
