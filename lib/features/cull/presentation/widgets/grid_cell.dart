import 'dart:async';

import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/files/open_external.dart';
import 'package:cullimingo/core/files/supported_files.dart';
import 'package:cullimingo/features/cull/domain/drag_targets.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/widgets/photo_cell.dart';
import 'package:cullimingo/features/cull/presentation/widgets/thumbnail_context_menu.dart';
import 'package:cullimingo/features/filter/presentation/filter_providers.dart';
import 'package:cullimingo/features/handoff/data/transfer_service.dart';
import 'package:cullimingo/features/handoff/domain/external_editor.dart';
import 'package:cullimingo/features/handoff/presentation/send_to_providers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

/// Watches the thumbnail + selection state for one photo and renders a cell.
class GridCell extends ConsumerWidget {
  /// Creates a grid cell for [photo].
  const GridCell({
    required this.photo,
    required this.cellWidth,
    required this.onOpenLoupe,
    required this.onTransfer,
    required this.onSendTo,
    this.onEditMetadata,
    this.onRename,
    this.onApplyTemplate,
    this.onGeocode,
    this.onExport,
    this.onExpandBrackets,
    this.onApplyMarksToBracket,
    this.onStack,
    this.onUnstack,
    this.onContactSheet,
    this.onDelete,
    super.key,
  });

  /// The photo this cell renders.
  final Photo photo;

  /// Nominal (zoom-slider) cell width, forwarded to [PhotoCell] to key the
  /// thumbnail decode resolution independently of the live layout width.
  final double cellWidth;

  /// Opens the loupe on this photo (double-click).
  final ValueChanged<int> onOpenLoupe;

  /// Copies/moves the current selection to a folder (context menu). The page
  /// owns the dialog + background job; the cell just relays the chosen mode.
  final ValueChanged<TransferMode> onTransfer;

  /// Opens the current selection in a configured external editor (context
  /// menu). The page resolves the target photos and launches the app.
  final ValueChanged<ExternalEditor> onSendTo;

  /// Opens the structured IPTC metadata editor for the selection. Null disables
  /// it. Used by both the context menu and the thumbnail's hover button.
  final VoidCallback? onEditMetadata;

  /// Renames the current selection in place (context menu). Null disables it.
  final VoidCallback? onRename;

  /// Stamps the active metadata template onto the selection. Null disables it.
  final VoidCallback? onApplyTemplate;

  /// Fills the selection's IPTC location from GPS. Null disables it.
  final VoidCallback? onGeocode;

  /// Exports the selection (opens the export dialog). Null disables it.
  final VoidCallback? onExport;

  /// Grows the selection to each photo's exposure-bracket siblings. Null
  /// disables it (the menu entry is only shown for a bracket member).
  final VoidCallback? onExpandBrackets;

  /// Copies the focused photo's marks onto the rest of its exposure bracket.
  /// Null disables it (the menu entry is only shown for a bracket member).
  final VoidCallback? onApplyMarksToBracket;

  /// Manually stacks the selection into one bracket. Null disables it (the menu
  /// entry is only shown when 2+ photos are selected).
  final VoidCallback? onStack;

  /// Removes the selection from any bracket. Null disables it (only shown on a
  /// bracket member).
  final VoidCallback? onUnstack;

  /// Opens the ContactSheet dialog for the selection; the bool is pull mode
  /// (true = fetch client marks, false = send/upload). The menu only offers it
  /// when the integration is configured (§7b).
  final ValueChanged<bool>? onContactSheet;

  /// Moves the selection's files to the OS trash, after confirmation (context
  /// menu). Null disables it.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumb = ref.watch(thumbnailProvider(photo.path)).value;
    final focused = ref.watch(
      cullControllerProvider.select((s) => s.focusedId == photo.id),
    );
    final selected = ref.watch(
      cullControllerProvider.select((s) => s.selectedIds.contains(photo.id)),
    );
    final burstSize = ref.watch(
      effectiveGroupsProvider.select((g) => g.sizeOf(photo.id)),
    );
    // Tint the badge by group only while reviewing groups (Bursts/Similar
    // filter on), so normal browsing isn't a sea of colours.
    final grouping = ref.watch(
      photoFilterControllerProvider.select((f) => f.burstsOnly),
    );
    final groupColor = grouping
        ? burstGroupColor(
            ref.watch(
              effectiveGroupsProvider.select((g) => g.groupIndexOf(photo.id)),
            ),
          )
        : null;
    final paired = ref.watch(
      rawJpegPairsProvider.select((p) => p.isPaired(photo.id)),
    );
    // Badge the reference (normal-exposure) frame of an exposure bracket with
    // its frame count; the other members carry no badge (they hide when the
    // stack is collapsed).
    final bracketSize = ref.watch(
      bracketGroupsProvider.select(
        (b) => b.isReference(photo.id) ? b.sizeOf(photo.id) : 0,
      ),
    );

    // Drag a cell out to Finder/Desktop to copy the original file(s) (§7
    // hand-off). Dragging a selected photo carries the whole selection; an
    // unselected one carries just itself (see [dragTargets]); a collapsed
    // bracket carries all its folded frames (see [_dragConfiguration]).
    // super_native_extensions backs this with NSDraggingSource/file promises
    // on macOS.
    return DragItemWidget(
      allowedOperations: () => const [DropOperation.copy],
      dragItemProvider: (_) async => DragItem(
        suggestedName: p.basename(photo.path),
      )..add(Formats.fileUri(Uri.file(photo.path))),
      child: DraggableWidget(
        onDragConfiguration: (configuration, _) =>
            _dragConfiguration(ref, configuration),
        // Select on the raw pointer-down via Listener: it fires before the
        // gesture arena resolves, so the border appears the instant you press —
        // GestureDetector's onTap/onTapDown can be held up disambiguating a
        // double-tap or competing with the grid's scroll drag. Modifiers mirror
        // desktop conventions: ⌘/Ctrl toggles, Shift range-selects, plain click
        // selects just this photo.
        child: Listener(
          onPointerDown: (event) => _onPointerDown(ref, event),
          // A plain click inside a multi-selection collapses to this photo on
          // release; a cancel (a drag or scroll took over the pointer) leaves
          // the selection intact so a drag-out keeps every selected file.
          onPointerUp: (_) =>
              ref.read(cullControllerProvider.notifier).commitPendingCollapse(),
          onPointerCancel: (_) =>
              ref.read(cullControllerProvider.notifier).cancelPendingCollapse(),
          child: GestureDetector(
            onSecondaryTapDown: (d) =>
                unawaited(_onSecondaryTap(context, ref, d)),
            onDoubleTap: () => isVideoPath(photo.path)
                ? openExternally(photo.path)
                : onOpenLoupe(photo.id),
            // The photo id is tagged on the cell so a right-click landing here
            // while another cell's menu is open can be resolved back to this
            // photo (see [_photoIdAt]). Opaque so the whole cell rect resolves.
            child: MetaData(
              metaData: photo.id,
              behavior: HitTestBehavior.opaque,
              child: PhotoCell(
                photo: photo,
                thumbnail: thumb,
                cellWidth: cellWidth,
                focused: focused,
                selected: selected,
                burstSize: burstSize,
                groupColor: groupColor,
                paired: paired,
                bracketSize: bracketSize,
                // Hover actions act on *this* photo: rotate it directly; the
                // metadata button selects it first, then opens the editor.
                onRotateLeft: () => unawaited(
                  ref
                      .read(cullControllerProvider.notifier)
                      .rotate(photo.id, -1),
                ),
                onRotateRight: () => unawaited(
                  ref.read(cullControllerProvider.notifier).rotate(photo.id, 1),
                ),
                onEditMetadata: onEditMetadata == null
                    ? null
                    : () {
                        _selectForContextMenu(ref, photo.id);
                        onEditMetadata!();
                      },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the drag session: one file item per [dragTargets] photo (in grid
  /// order), reusing the dragged cell's snapshot as each item's preview. For a
  /// single file the default [configuration] is already correct.
  DragConfiguration _dragConfiguration(
    WidgetRef ref,
    DragConfiguration configuration,
  ) {
    // The press became a drag, not a click — cancel the deferred collapse so
    // pointer-up won't shrink the selection to the dragged cell.
    ref.read(cullControllerProvider.notifier).cancelPendingCollapse();
    final selected = ref.read(cullControllerProvider).selectedIds;
    var ids = dragTargets(photo.id, selected);
    // A collapsed bracket shows only its reference frame, yet that cell stands
    // in for the whole stack — so dragging it out carries every hidden sibling
    // too (the ±EV frames the grid folded away).
    if (ref.read(photoFilterControllerProvider).collapseBrackets) {
      final groups = ref.read(bracketGroupsProvider);
      ids = {for (final id in ids) ...groups.groupOf(id)};
    }
    if (ids.length <= 1) return configuration;

    final image = configuration.items.first.image;
    // Resolve over the *unfiltered* photo list: collapsed bracket siblings are
    // hidden from the grid, so they aren't in filteredPhotosProvider.
    final items = [
      for (final row in ref.read(photosProvider).value ?? const <Photo>[])
        if (ids.contains(row.id))
          DragConfigurationItem(
            item: DragItem(suggestedName: p.basename(row.path))
              ..add(Formats.fileUri(Uri.file(row.path))),
            image: image,
          ),
    ];
    return DragConfiguration(
      items: items,
      allowedOperations: const [DropOperation.copy],
    );
  }

  void _onPointerDown(WidgetRef ref, PointerDownEvent event) {
    // A right-click's own selection handling happens later, once the gesture
    // arena resolves it as a secondary tap (`_selectForContextMenu`), which
    // keeps an existing multi-selection intact when the click lands inside
    // it. This handler fires for *every* button before that resolution, so it
    // must not collapse the selection out from under a right-click first.
    if (event.buttons & kSecondaryButton != 0) return;
    final controller = ref.read(cullControllerProvider.notifier);
    final keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed) {
      controller.cancelPendingCollapse();
      final ids = ref.read(filteredPhotosProvider).map((p) => p.id).toList();
      controller.extendSelectionTo(photo.id, ids);
    } else if (keys.isMetaPressed || keys.isControlPressed) {
      controller
        ..cancelPendingCollapse()
        ..toggleSelect(photo.id);
    } else {
      final selection = ref.read(cullControllerProvider);
      final insideMultiSelection =
          selection.selectedIds.length > 1 &&
          selection.selectedIds.contains(photo.id);
      if (insideMultiSelection) {
        // Keep the whole selection under the press so a drag-out carries every
        // selected file; collapse to just this photo only on release, if the
        // press turns out to be a plain click (see [commitPendingCollapse]).
        controller.beginPendingCollapse(photo.id);
      } else {
        controller
          ..cancelPendingCollapse()
          ..selectOnly(photo.id);
      }
    }
  }

  Future<void> _onSecondaryTap(
    BuildContext context,
    WidgetRef ref,
    TapDownDetails details,
  ) => _showContextMenuChain(context, ref, photo, details.globalPosition);

  /// Shows the thumbnail context menu for [target], then — because Flutter's
  /// menu barrier swallows the click that would dismiss it — lets a right-click
  /// on *another* thumbnail close this menu and immediately reopen on that one,
  /// so you don't have to right-click twice. A right-click off any thumbnail
  /// just closes the menu.
  ///
  /// The barrier both blocks the click from reaching the cell and blocks
  /// hit-testing *through* it, so while the menu is open we can neither see the
  /// press on the cell nor resolve which cell it hit. We instead listen on the
  /// global pointer route (which fires regardless of hit-testing) for the
  /// secondary press, close the menu ourselves, and only *then* — with the
  /// barrier gone — hit-test the press position to find the new target.
  Future<void> _showContextMenuChain(
    BuildContext context,
    WidgetRef ref,
    Photo target,
    Offset position,
  ) async {
    final navigator = Navigator.of(context);
    Photo? current = target;
    var pos = position;
    while (current != null) {
      final shown = current;
      _selectForContextMenu(ref, shown.id);
      Offset? closedAt;
      var closed = false;
      void onGlobalPointer(PointerEvent event) {
        if (closed) return;
        if (event is PointerDownEvent &&
            event.buttons & kSecondaryButton != 0) {
          closed = true;
          closedAt = event.position;
          // Close now (pre-empting the barrier's own tap-to-dismiss) so the
          // reopen below can hit-test the position with the barrier gone.
          navigator.pop();
        }
      }

      GestureBinding.instance.pointerRouter.addGlobalRoute(onGlobalPointer);
      try {
        await showThumbnailContextMenu(
          context: context,
          ref: ref,
          photo: shown,
          globalPosition: pos,
          onTransfer: onTransfer,
          onSendTo: onSendTo,
          onEditMetadata: onEditMetadata,
          onRename: onRename,
          onApplyTemplate: onApplyTemplate,
          onGeocode: onGeocode,
          onExport: onExport,
          // Only offered on a frame that actually belongs to a bracket.
          onExpandBrackets:
              ref.read(bracketGroupsProvider).memberIds.contains(shown.id)
              ? onExpandBrackets
              : null,
          onApplyMarksToBracket:
              ref.read(bracketGroupsProvider).memberIds.contains(shown.id)
              ? onApplyMarksToBracket
              : null,
          // Stack needs 2+ selected; unstack only makes sense on a member.
          onStack: ref.read(cullControllerProvider).markTargets.length >= 2
              ? onStack
              : null,
          onUnstack:
              ref.read(bracketGroupsProvider).memberIds.contains(shown.id)
              ? onUnstack
              : null,
          // Only when the ContactSheet integration is set up (warm provider,
          // gated on the base URL so no keychain prompt just to open a menu).
          onContactSheet:
              (ref.read(contactSheetConfiguredProvider).value ?? false)
              ? onContactSheet
              : null,
          onDelete: onDelete,
        );
      } finally {
        GestureBinding.instance.pointerRouter.removeGlobalRoute(
          onGlobalPointer,
        );
      }

      // Closed by something other than a right-click, or the cell is gone.
      if (closedAt == null || !context.mounted) return;
      // The pop only detaches the barrier on the next frame; wait for it so the
      // hit-test below reaches the cells instead of the (now-closing) barrier.
      await WidgetsBinding.instance.endOfFrame;
      if (!context.mounted) return;
      final id = _photoIdAt(context, closedAt!);
      // Off any thumbnail, or the same one → just stay closed.
      if (id == null || id == shown.id) return;
      final next = _photoById(ref, id);
      if (next == null) return;
      current = next;
      pos = closedAt!;
    }
  }

  /// Right-click outside the selection acts on just this photo; inside it, keep
  /// the selection but focus this cell so `markTargets` covers it.
  void _selectForContextMenu(WidgetRef ref, int id) {
    final controller = ref.read(cullControllerProvider.notifier);
    if (ref.read(cullControllerProvider).selectedIds.contains(id)) {
      controller.focus(id);
    } else {
      controller.selectOnly(id);
    }
  }

  /// The photo currently shown in the grid with [id], or null if it has been
  /// filtered out or removed since.
  Photo? _photoById(WidgetRef ref, int id) {
    for (final photo in ref.read(filteredPhotosProvider)) {
      if (photo.id == id) return photo;
    }
    return null;
  }

  /// The photo id of the thumbnail under [globalPosition] (tagged via
  /// [MetaData]), or null when the point isn't over a cell.
  int? _photoIdAt(BuildContext context, Offset globalPosition) {
    final result = HitTestResult();
    GestureBinding.instance.hitTestInView(
      result,
      globalPosition,
      View.of(context).viewId,
    );
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderMetaData && target.metaData is int) {
        return target.metaData as int;
      }
    }
    return null;
  }
}
