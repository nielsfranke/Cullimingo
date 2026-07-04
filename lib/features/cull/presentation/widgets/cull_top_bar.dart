import 'dart:async';

import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/widgets/grid_zoom_slider.dart';
import 'package:cullimingo/features/filter/domain/photo_sort.dart';
import 'package:cullimingo/features/filter/presentation/filter_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The top application toolbar: library title + photo count on the left, and a
/// horizontally-scrolling row of folder/selection actions on the right
/// (`BUILD_PLAN.md` §7). Every folder-specific callback is nullable so the bar
/// disables the matching control when no folder is open.
class CullTopBar extends StatelessWidget {
  /// Creates the top bar.
  const CullTopBar({
    required this.count,
    required this.onOpenFolder,
    required this.onIngest,
    required this.includeSubfolders,
    required this.onIncludeSubfolders,
    required this.onSettings,
    required this.onShortcuts,
    required this.inspectorOpen,
    this.onToggleInspector,
    this.onFind,
    this.onCompare,
    this.onFindSimilar,
    this.onClearSimilar,
    this.onImport,
    this.onSaveSelection,
    this.onLoadSelection,
    this.onDeleteSelection,
    this.onEditKeywords,
    this.onEditMetadata,
    this.onApplyTemplate,
    this.onGeocode,
    this.onResync,
    this.onRefresh,
    this.onDeleteRejects,
    this.onContactSheet,
    this.cellWidth,
    this.onCellWidth,
    super.key,
  });

  /// How many photos are in the open folder (0 = none).
  final int count;

  /// Opens a folder.
  final Future<void> Function() onOpenFolder;

  /// Opens the card-import flow.
  final Future<void> Function() onIngest;

  /// Whether "Open folder" includes sub-folders.
  final bool includeSubfolders;

  /// Toggles the include-subfolders setting.
  final ValueChanged<bool> onIncludeSubfolders;

  /// Opens the central Settings dialog (always available — app settings).
  final Future<void> Function() onSettings;

  /// Opens the keyboard-shortcuts cheat sheet (always available).
  final VoidCallback onShortcuts;

  /// Whether the metadata inspector panel is currently open.
  final bool inspectorOpen;

  /// Toggles the metadata inspector panel (null = disabled, no folder open).
  final VoidCallback? onToggleInspector;

  /// Opens the paste-a-list Find dialog (null = disabled, no folder).
  final Future<void> Function()? onFind;

  /// Opens the compare view on the selection (null = disabled, no folder).
  final VoidCallback? onCompare;

  /// Runs the perceptual-hash "find similar" pass (null = disabled, no folder).
  final Future<void> Function()? onFindSimilar;

  /// Clears the computed similarity grouping (null = none computed).
  final VoidCallback? onClearSimilar;

  /// Opens the import-a-list flow (null = disabled, no folder).
  final Future<void> Function()? onImport;

  /// Saves the current selection under a name (null = disabled, no folder).
  final Future<void> Function()? onSaveSelection;

  /// Loads a saved selection into the grid (null = disabled, no folder).
  final void Function(SavedSelection)? onLoadSelection;

  /// Deletes a saved selection (null = disabled, no folder).
  final Future<void> Function(SavedSelection)? onDeleteSelection;

  /// Opens the keyword editor for the selection/focused photo (null = disabled).
  final VoidCallback? onEditKeywords;

  /// Opens the IPTC metadata editor for the selection/focused photo
  /// (null = disabled).
  final VoidCallback? onEditMetadata;

  /// Stamps the saved metadata template onto the selection (null = disabled).
  final VoidCallback? onApplyTemplate;

  /// Fills the selection's IPTC location from GPS (null = disabled).
  final VoidCallback? onGeocode;

  /// Re-reads sidecars from disk (null = disabled, no folder open).
  final Future<void> Function()? onResync;

  /// Re-scans the folder for added/removed files (null = disabled, no folder).
  final Future<void> Function()? onRefresh;

  /// Moves the folder's rejected photos to the OS trash (after confirmation).
  /// Null hides the entry.
  final VoidCallback? onDeleteRejects;

  /// Opens the ContactSheet dialog (send/pull); null = disabled, no folder.
  final Future<void> Function()? onContactSheet;

  /// Current grid cell width, or `null` to hide the size slider (no photos).
  final double? cellWidth;

  /// Called as the size slider moves.
  final ValueChanged<double>? onCellWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Text(
            'Library',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          if (count > 0) ...[
            Text(
              '$count photos',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(width: AppSpacing.md),
            // Sort control (BUILD_PLAN §7), on the left by the photo count.
            const _SortButton(),
          ],
          // Background XMP-sidecar write progress; self-hides when idle.
          const _SyncIndicator(),
          // The right-hand controls scroll horizontally if they don't fit, so
          // the toolbar never overflows on a narrow window (and new buttons
          // can't break the layout). reverse: keeps them right-aligned.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Folder-scoped view/browse controls, grouped together and
                  // only present with a folder open (so the divider never
                  // dangles on an empty bar).
                  if (count > 0) ...[
                    if (cellWidth != null && onCellWidth != null) ...[
                      const Icon(
                        Icons.photo_size_select_large,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      SizedBox(
                        width: 140,
                        child: GridZoomSlider(
                          value: cellWidth!,
                          onCommit: onCellWidth!,
                        ),
                      ),
                      const _BarDivider(),
                    ],
                    if (onFind != null)
                      IconButton(
                        onPressed: onFind,
                        tooltip: 'Find by filename (⌘F)',
                        icon: const Icon(Icons.search, size: 18),
                      ),
                    if (onToggleInspector != null)
                      IconButton(
                        onPressed: onToggleInspector,
                        tooltip: inspectorOpen
                            ? 'Hide info (I)'
                            : 'Show info (I)',
                        icon: Icon(
                          Icons.info_outline,
                          size: 18,
                          color: inspectorOpen
                              ? AppColors.accent
                              : AppColors.textSecondary,
                        ),
                      ),
                    if (onSaveSelection != null &&
                        onLoadSelection != null &&
                        onDeleteSelection != null)
                      _SavedSelectionsButton(
                        onSave: onSaveSelection!,
                        onLoad: onLoadSelection!,
                        onDelete: onDeleteSelection!,
                      ),
                    const _BarDivider(),
                  ],
                  // Get-photos group: the sub-folder mode toggle sits with the
                  // Open-folder button it modifies, next to card Import.
                  IconButton(
                    onPressed: () => onIncludeSubfolders(!includeSubfolders),
                    tooltip: includeSubfolders
                        ? 'Open folder: including sub-folders'
                        : 'Open folder: top level only',
                    icon: Icon(
                      Icons.account_tree_outlined,
                      size: 18,
                      color: includeSubfolders
                          ? AppColors.accent
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  TextButton.icon(
                    onPressed: onIngest,
                    icon: const Icon(Icons.sd_card, size: 18),
                    label: const Text('Import'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Tooltip(
                    message: 'Open folder (⌘/Ctrl O)',
                    child: FilledButton.icon(
                      onPressed: onOpenFolder,
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: const Text('Open folder'),
                    ),
                  ),
                  const _BarDivider(),
                  // App-level group (always reachable, even with no folder).
                  IconButton(
                    onPressed: onShortcuts,
                    tooltip: 'Keyboard shortcuts (?)',
                    icon: const Icon(Icons.keyboard_outlined, size: 18),
                  ),
                  IconButton(
                    onPressed: () => unawaited(onSettings()),
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings_outlined, size: 18),
                  ),
                  // The More menu only holds folder-specific actions — hide it
                  // with no folder open so it's never an empty/near-empty menu.
                  if (count > 0) ...[
                    const SizedBox(width: AppSpacing.xs),
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      icon: const Icon(Icons.more_vert, size: 18),
                      popUpAnimationStyle: kMenuAnimationStyle,
                      onSelected: (value) {
                        switch (value) {
                          case 'compare':
                            onCompare?.call();
                          case 'find-similar':
                            if (onFindSimilar != null) {
                              unawaited(onFindSimilar!());
                            }
                          case 'clear-similar':
                            onClearSimilar?.call();
                          case 'import-list':
                            if (onImport != null) unawaited(onImport!());
                          case 'keywords':
                            onEditKeywords?.call();
                          case 'metadata':
                            onEditMetadata?.call();
                          case 'apply-template':
                            onApplyTemplate?.call();
                          case 'geocode':
                            onGeocode?.call();
                          case 'resync':
                            if (onResync != null) unawaited(onResync!());
                          case 'delete-rejects':
                            onDeleteRejects?.call();
                          case 'refresh':
                            if (onRefresh != null) unawaited(onRefresh!());
                          case 'contactsheet':
                            if (onContactSheet != null) {
                              unawaited(onContactSheet!());
                            }
                        }
                      },
                      // Grouped by purpose (review · metadata · client ·
                      // folder) with a divider between each non-empty group, so
                      // the long action list scans instead of reading as a
                      // flat grab-bag.
                      itemBuilder: (context) {
                        PopupMenuItem<String> entry(
                          String value,
                          String label,
                        ) => PopupMenuItem<String>(
                          value: value,
                          height: 40,
                          child: Text(label),
                        );
                        final groups = <List<PopupMenuEntry<String>>>[
                          [
                            if (onCompare != null)
                              entry('compare', 'Compare selected (C)'),
                            if (onFindSimilar != null)
                              entry('find-similar', 'Find similar photos'),
                            if (onClearSimilar != null)
                              entry('clear-similar', 'Clear similar grouping'),
                          ],
                          [
                            if (onEditKeywords != null)
                              entry('keywords', 'Edit keywords (K)'),
                            if (onEditMetadata != null)
                              entry('metadata', 'Edit metadata (M)'),
                            if (onApplyTemplate != null)
                              entry(
                                'apply-template',
                                'Apply metadata template (T)',
                              ),
                            if (onGeocode != null)
                              entry('geocode', 'Fill location from GPS'),
                          ],
                          [
                            if (onImport != null)
                              entry('import-list', 'Import selection list…'),
                            if (onContactSheet != null)
                              entry('contactsheet', 'ContactSheet…'),
                          ],
                          [
                            if (onRefresh != null)
                              entry('refresh', 'Refresh folder (⌘R)'),
                            if (onResync != null)
                              entry('resync', 'Re-sync sidecars from disk'),
                          ],
                          // Destructive, so it sits alone behind a divider.
                          [
                            if (onDeleteRejects != null)
                              entry(
                                'delete-rejects',
                                'Delete rejected photos… (⌘⌫)',
                              ),
                          ],
                        ];
                        final entries = <PopupMenuEntry<String>>[];
                        for (final group in groups) {
                          if (group.isEmpty) continue;
                          if (entries.isNotEmpty) {
                            entries.add(const PopupMenuDivider());
                          }
                          entries.addAll(group);
                        }
                        return entries;
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A thin vertical rule that separates groups of toolbar controls.
class _BarDivider extends StatelessWidget {
  const _BarDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 20,
    margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    color: AppColors.border,
  );
}

/// Toolbar sort control (`BUILD_PLAN.md` §7): a "Sort by" menu of the sortable
/// fields plus an ascending/descending toggle. Reads/writes the sort provider
/// directly, so it needs no wiring through [CullTopBar].
class _SortButton extends ConsumerWidget {
  const _SortButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(photoSortControllerProvider);
    final notifier = ref.read(photoSortControllerProvider.notifier);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<PhotoSortKey>(
          tooltip: 'Sort by',
          popUpAnimationStyle: kMenuAnimationStyle,
          onSelected: notifier.setKey,
          itemBuilder: (context) => [
            for (final key in PhotoSortKey.values)
              CheckedPopupMenuItem(
                value: key,
                checked: key == sort.key,
                child: Text(key.label),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.sort,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  sort.key.label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                ),
                const Icon(
                  Icons.arrow_drop_down,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        IconButton(
          onPressed: notifier.toggleDirection,
          tooltip: sort.ascending ? 'Ascending' : 'Descending',
          icon: Icon(
            sort.ascending ? Icons.arrow_upward : Icons.arrow_downward,
            size: 16,
          ),
        ),
      ],
    );
  }
}

/// Shows "Syncing N…" while XMP sidecar writes are in flight, and nothing when
/// idle. Marks land in the DB (and the grid) instantly, then mirror to sidecars
/// in the background — this is the only visible sign that work is outstanding.
class _SyncIndicator extends ConsumerWidget {
  const _SyncIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(sidecarSyncProvider);
    if (pending == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.md),
      child: Tooltip(
        message: 'Writing marks to XMP sidecars',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Syncing $pending…',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sentinel for the "save current selection" entry in [_SavedSelectionsButton]
/// — a non-null value so `PopupMenuButton` doesn't treat it as a cancel.
class _SaveCurrentSelection {
  const _SaveCurrentSelection();
}

const _saveCurrentSelection = _SaveCurrentSelection();

/// Toolbar bookmark menu: save the current grid selection by name, and reload
/// or delete previously saved ones for the open import (`BUILD_PLAN.md` §5).
class _SavedSelectionsButton extends ConsumerWidget {
  const _SavedSelectionsButton({
    required this.onSave,
    required this.onLoad,
    required this.onDelete,
  });

  final Future<void> Function() onSave;
  final void Function(SavedSelection) onLoad;
  final Future<void> Function(SavedSelection) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved =
        ref.watch(savedSelectionsProvider).value ?? const <SavedSelection>[];
    final hasSaved = saved.isNotEmpty;
    return PopupMenuButton<Object>(
      tooltip: 'Saved selections',
      popUpAnimationStyle: kMenuAnimationStyle,
      // A small accent dot when saved selections exist — present-or-not is all
      // we need, and a dot stays legible without covering the glyph.
      icon: hasSaved
          ? const Badge(
              backgroundColor: AppColors.accent,
              smallSize: 8,
              offset: Offset(1, -1),
              child: Icon(Icons.bookmark, size: 18),
            )
          : const Icon(Icons.bookmark_border, size: 18),
      onSelected: (value) {
        if (value is SavedSelection) {
          onLoad(value);
        } else {
          unawaited(onSave());
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem<Object>(
          value: _saveCurrentSelection,
          child: Text('Save current selection…'),
        ),
        if (saved.isNotEmpty) const PopupMenuDivider(),
        for (final selection in saved)
          PopupMenuItem<Object>(
            value: selection,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${selection.name} (${selection.photoIds.length})',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Delete',
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    Navigator.of(context).pop();
                    unawaited(onDelete(selection));
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}
