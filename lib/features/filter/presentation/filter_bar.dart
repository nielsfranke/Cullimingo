import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/files/supported_files.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/filter/domain/filter_preset.dart';
import 'package:cullimingo/features/filter/domain/photo_filter.dart';
import 'package:cullimingo/features/filter/presentation/filter_providers.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:cullimingo/shared/widgets/edge_fade_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The quick-filter bar: All / Picks / Rejected chips with live counts, a star
/// rating threshold, and colour-label dots (`BUILD_PLAN.md` §5/§7).
class FilterBar extends ConsumerWidget {
  /// Creates the filter bar.
  const FilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(photosProvider).value ?? const <Photo>[];
    final filter = ref.watch(photoFilterControllerProvider);
    final controller = ref.read(photoFilterControllerProvider.notifier);
    final selectedCount = ref.watch(
      cullControllerProvider.select((s) => s.selectedIds.length),
    );

    int count(bool Function(Photo) test) => all.where(test).length;

    // "Similar" once a perceptual-hash pass has run for this folder, else the
    // free capture-time bursts.
    final groupLabel = ref.watch(currentSimilarGroupsProvider) != null
        ? 'Similar'
        : 'Bursts';
    final groupCount = ref.watch(effectiveGroupsProvider).memberIds.length;
    final pairCount = ref.watch(rawJpegPairsProvider).pairCount;
    final bracketCount = ref.watch(bracketGroupsProvider).bracketCount;
    // The file-type filter is only useful when the folder actually mixes RAW
    // and JPEG — otherwise "RAW only"/"JPEG only" is a no-op or empties the
    // grid. But keep it offered while it's still *active*, even if the folder
    // stopped being mixed (e.g. you filtered to JPEG then deleted every JPEG):
    // otherwise the control vanishes with the filter stuck on, leaving no way
    // to clear it short of "All".
    final rawCount = count((p) => p.isRaw);
    final jpegCount = count((p) => isJpegPath(p.path));
    final showFileType =
        (rawCount > 0 && jpegCount > 0) ||
        filter.fileType != FileTypeFilter.all;

    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: EdgeFadeScroll(
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          children: [
            const _FilterPresetsButton(),
            const _Divider(),
            const _SearchField(),
            const _Divider(),
            _Chip(
              label: 'All (${all.length})',
              selected: !filter.isActive,
              onTap: controller.clear,
            ),
            _Chip(
              label: 'Selected ($selectedCount)',
              selected: filter.selectedOnly,
              onTap: controller.toggleSelectedOnly,
            ),
            const _Divider(),
            _Chip(
              label: 'Picks (${count((p) => p.flag == PickFlag.pick)})',
              selected: filter.flag == PickFlag.pick,
              onTap: () => controller.toggleFlag(PickFlag.pick),
            ),
            _Chip(
              label: 'Rejected (${count((p) => p.flag == PickFlag.reject)})',
              selected: filter.flag == PickFlag.reject,
              onTap: () => controller.toggleFlag(PickFlag.reject),
            ),
            const _Divider(),
            for (var star = 1; star <= 5; star++)
              _StarToggle(
                star: star,
                active: filter.minRating >= star,
                onTap: () => controller.toggleMinRating(star),
              ),
            const _Divider(),
            for (final label in ColorLabel.values)
              if (label != ColorLabel.none)
                _ColorToggle(
                  label: label,
                  selected: filter.color == label,
                  onTap: () => controller.toggleColor(label),
                ),
            const _Divider(),
            // The situational attribute/grouping filters live in two grouped
            // dropdowns so the bar stays scannable; the core cull filters above
            // (flags / stars / colours) stay inline. Each dropdown tints when
            // any of its filters is active, and its items carry live counts.
            _FilterMenuButton(
              label: 'Metadata',
              active: filter.hasKeyword || filter.needsCaption,
              menuChildren: [
                CheckboxMenuButton(
                  value: filter.hasKeyword,
                  closeOnActivate: false,
                  onChanged: (_) => controller.toggleHasKeyword(),
                  child: Text(
                    'Keyworded (${count((p) => p.keywords.isNotEmpty)})',
                  ),
                ),
                CheckboxMenuButton(
                  value: filter.needsCaption,
                  closeOnActivate: false,
                  onChanged: (_) => controller.toggleNeedsCaption(),
                  child: Text(
                    'Needs caption '
                    '(${count((p) => p.iptc.caption.trim().isEmpty)})',
                  ),
                ),
              ],
            ),
            _FilterMenuButton(
              label: 'Grouping',
              active:
                  filter.burstsOnly ||
                  filter.hideJpegPairs ||
                  filter.collapseBrackets ||
                  filter.fileType != FileTypeFilter.all,
              menuChildren: [
                CheckboxMenuButton(
                  value: filter.burstsOnly,
                  closeOnActivate: false,
                  onChanged: (_) => controller.toggleBurstsOnly(),
                  child: Text('$groupLabel ($groupCount)'),
                ),
                // Only offered when the folder actually has exposure brackets.
                if (bracketCount > 0)
                  CheckboxMenuButton(
                    value: filter.collapseBrackets,
                    closeOnActivate: false,
                    onChanged: (_) => controller.toggleCollapseBrackets(),
                    child: Text('Stack brackets ($bracketCount)'),
                  ),
                // Only offered when the folder actually has RAW+JPEG pairs.
                if (pairCount > 0)
                  CheckboxMenuButton(
                    value: filter.hideJpegPairs,
                    closeOnActivate: false,
                    onChanged: (_) => controller.toggleHideJpegPairs(),
                    child: Text('Hide JPEG ($pairCount)'),
                  ),
                // File-type radio (All / RAW / JPEG) — shown when the folder
                // mixes both, or while a type filter is still active.
                if (showFileType) ...[
                  const Divider(height: 1),
                  RadioMenuButton<FileTypeFilter>(
                    value: FileTypeFilter.all,
                    groupValue: filter.fileType,
                    closeOnActivate: false,
                    onChanged: (v) =>
                        controller.setFileType(v ?? FileTypeFilter.all),
                    child: const Text('All file types'),
                  ),
                  RadioMenuButton<FileTypeFilter>(
                    value: FileTypeFilter.raw,
                    groupValue: filter.fileType,
                    closeOnActivate: false,
                    onChanged: (v) =>
                        controller.setFileType(v ?? FileTypeFilter.all),
                    child: Text('RAW only ($rawCount)'),
                  ),
                  RadioMenuButton<FileTypeFilter>(
                    value: FileTypeFilter.jpeg,
                    groupValue: filter.fileType,
                    closeOnActivate: false,
                    onChanged: (v) =>
                        controller.setFileType(v ?? FileTypeFilter.all),
                    child: Text('JPEG only ($jpegCount)'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
      child: Material(
        color: selected ? AppColors.accent : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Live filename search box. Filters the grid as you type by substring against
/// each photo's filename (with extension, case-insensitive), so "DSC_004" and
/// "jpg" both work. Owns its own [FocusNode] so the grid's bare-key cull
/// shortcuts (1–5, P, X, colours) never fire while the user is typing, and
/// mirrors the filter provider so clearing the filter elsewhere ("All") empties
/// the box.
class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  late final TextEditingController _controller;
  final _focus = FocusNode(debugLabel: 'filter-search');

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(photoFilterControllerProvider).query,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(
      photoFilterControllerProvider.select((f) => f.query),
    );
    // Re-sync the box when the filter is cleared/replaced elsewhere (the "All"
    // chip, or a tab switch restoring a saved filter). A programmatic set does
    // not fire onChanged, so this can't loop with the user's own typing.
    if (query != _controller.text) {
      _controller.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
      child: SizedBox(
        width: 190,
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
          cursorColor: AppColors.accent,
          textAlignVertical: TextAlignVertical.center,
          onChanged: (v) =>
              ref.read(photoFilterControllerProvider.notifier).setQuery(v),
          onSubmitted: (_) => _focus.unfocus(),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.surfaceElevated,
            hintText: 'Search filename…',
            hintStyle: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
            prefixIcon: const Icon(
              Icons.search,
              size: 16,
              color: AppColors.textSecondary,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 30,
              minHeight: 30,
            ),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    iconSize: 14,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close),
                    color: AppColors.textSecondary,
                    onPressed: () => ref
                        .read(photoFilterControllerProvider.notifier)
                        .setQuery(''),
                  ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 30,
              minHeight: 30,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }
}

/// A chip-styled dropdown trigger that opens a [MenuAnchor] of checkable
/// filter items. Tints with [AppColors.accent] (like a selected [_Chip]) when
/// [active], so an active filter hidden inside the menu is still visible on the
/// bar. Tapping the trigger toggles the menu (it stays visible while open).
class _FilterMenuButton extends StatelessWidget {
  const _FilterMenuButton({
    required this.label,
    required this.active,
    required this.menuChildren,
  });

  final String label;
  final bool active;
  final List<Widget> menuChildren;

  @override
  Widget build(BuildContext context) {
    final fg = active ? Colors.white : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
      child: MenuAnchor(
        menuChildren: menuChildren,
        builder: (context, controller, child) => Material(
          color: active ? AppColors.accent : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.md, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  Icon(Icons.arrow_drop_down, size: 18, color: fg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StarToggle extends StatelessWidget {
  const _StarToggle({
    required this.star,
    required this.active,
    required this.onTap,
  });

  final int star;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      iconSize: 16,
      visualDensity: VisualDensity.compact,
      tooltip: 'Rating ≥ $star',
      icon: Icon(
        active ? Icons.star_rounded : Icons.star_outline_rounded,
        color: active ? AppColors.ratingGold : AppColors.textSecondary,
      ),
    );
  }
}

class _ColorToggle extends StatelessWidget {
  const _ColorToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final ColorLabel label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Tooltip(
        message: selected
            ? '${label.displayName} label — showing only these'
            : 'Filter: ${label.displayName} label',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: label.color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? Colors.white
                      : Colors.black.withValues(alpha: 0.3),
                  width: selected ? 2 : 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 10),
      child: VerticalDivider(width: 1, color: AppColors.border),
    );
  }
}

/// Sentinel for the "save current filter" menu entry — a non-null value so
/// `PopupMenuButton` doesn't read a tap on it as a dismissal.
class _SaveCurrentFilter {
  const _SaveCurrentFilter();
}

const _saveCurrentFilter = _SaveCurrentFilter();

/// Filter-bar bookmark menu: save the active filter under a name, then re-apply
/// or delete previously saved presets (`BUILD_PLAN.md` §5). Presets are global,
/// so the same list is offered on every folder.
class _FilterPresetsButton extends ConsumerWidget {
  const _FilterPresetsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(filterPresetsProvider);
    final filter = ref.watch(photoFilterControllerProvider);
    final hasPresets = presets.isNotEmpty;
    // Capture the notifiers now so the async name prompt doesn't reach back
    // through `ref` after the await.
    final filterController = ref.read(photoFilterControllerProvider.notifier);
    final presetsController = ref.read(filterPresetsProvider.notifier);

    return PopupMenuButton<Object>(
      tooltip: 'Filter presets',
      icon: hasPresets
          ? const Badge(
              backgroundColor: AppColors.accent,
              smallSize: 8,
              offset: Offset(1, -1),
              child: Icon(Icons.filter_alt, size: 18),
            )
          : const Icon(Icons.filter_alt_outlined, size: 18),
      onSelected: (value) async {
        if (value is FilterPreset) {
          filterController.restore(value.filter);
          return;
        }
        final name = await _promptPresetName(context);
        if (name == null || name.trim().isEmpty) return;
        presetsController.save(name, filter);
      },
      itemBuilder: (context) => [
        PopupMenuItem<Object>(
          value: _saveCurrentFilter,
          enabled: filter.isActive,
          child: const Text('Save current filter…'),
        ),
        if (hasPresets) const PopupMenuDivider(),
        for (final preset in presets)
          PopupMenuItem<Object>(
            value: preset,
            child: Row(
              children: [
                Expanded(
                  child: Text(preset.name, overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  tooltip: 'Delete',
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    Navigator.of(context).pop();
                    presetsController.delete(preset.name);
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Single-line dialog naming the preset. Returns the text, or null on cancel.
  Future<String?> _promptPresetName(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save filter preset'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Preset name'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
