import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// The workspace tab strip: one chip per open folder plus an "open folder"
/// button whose menu also lists recently-opened folders.
class CullTabBar extends StatelessWidget {
  /// Creates the tab bar.
  const CullTabBar({
    required this.state,
    required this.onSelect,
    required this.onClose,
    required this.onNew,
    required this.recentFolders,
    required this.onOpenRecent,
    super.key,
  });

  /// The open workspace (tabs + active index).
  final WorkspaceState state;

  /// Called with the index of the tab to activate.
  final ValueChanged<int> onSelect;

  /// Called with the index of the tab to close.
  final ValueChanged<int> onClose;

  /// Called to open another folder in a new tab (folder picker).
  final Future<void> Function() onNew;

  /// Recently-opened folder paths (most-recent-first) for the "+" menu.
  final List<String> recentFolders;

  /// Called with a recent folder's path to reopen it.
  final ValueChanged<String> onOpenRecent;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: state.tabs.length,
              itemBuilder: (context, i) => _TabChip(
                label: state.tabs[i].label,
                active: i == state.activeIndex,
                onTap: () => onSelect(i),
                onClose: () => onClose(i),
              ),
            ),
          ),
          _OpenFolderButton(
            onNew: onNew,
            recentFolders: recentFolders,
            openTabs: {for (final t in state.tabs) t.sourcePath},
            onOpenRecent: onOpenRecent,
          ),
        ],
      ),
    );
  }
}

/// The "+" button: a plain click opens the folder picker; its dropdown lists
/// recently-opened folders (those not already open) for quick reopening.
class _OpenFolderButton extends StatelessWidget {
  const _OpenFolderButton({
    required this.onNew,
    required this.recentFolders,
    required this.openTabs,
    required this.onOpenRecent,
  });

  final Future<void> Function() onNew;
  final List<String> recentFolders;
  final Set<String> openTabs;
  final ValueChanged<String> onOpenRecent;

  @override
  Widget build(BuildContext context) {
    // Only offer recents that aren't already open in a tab.
    final recent = [
      for (final path in recentFolders)
        if (!openTabs.contains(path)) path,
    ];
    if (recent.isEmpty) {
      return IconButton(
        onPressed: onNew,
        tooltip: 'Open another folder',
        iconSize: 18,
        icon: const Icon(Icons.add, color: AppColors.textSecondary),
      );
    }
    return MenuAnchor(
      builder: (context, controller, _) => IconButton(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        tooltip: 'Open folder / recent',
        iconSize: 18,
        icon: const Icon(Icons.add, color: AppColors.textSecondary),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.folder_open, size: 16),
          onPressed: () => unawaitedOpen(onNew),
          child: const Text('Open folder…'),
        ),
        const Divider(height: 1),
        for (final path in recent)
          MenuItemButton(
            leadingIcon: const Icon(Icons.history, size: 16),
            onPressed: () => onOpenRecent(path),
            child: Tooltip(
              message: path,
              waitDuration: const Duration(milliseconds: 600),
              child: Text(p.basename(path)),
            ),
          ),
      ],
    );
  }

  // A MenuItemButton onPressed can't be async; fire-and-forget the picker.
  static void unawaitedOpen(Future<void> Function() open) {
    // ignore: discarded_futures — the picker manages its own lifecycle.
    open();
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200),
        padding: const EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: active ? AppColors.surfaceElevated : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: active ? AppColors.accent : Colors.transparent,
              width: 2,
            ),
            right: const BorderSide(color: AppColors.border),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: active
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
