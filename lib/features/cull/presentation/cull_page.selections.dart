part of 'cull_page.dart';

/// Saved selections and paste-a-list find/import.
mixin _CullSelections on _CullWorkspace {
  Future<void> _importSelection() async {
    const group = XTypeGroup(label: 'Lists', extensions: ['csv', 'txt']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;

    final list = await CsvSelectionSource(
      name: file.name,
      content: await file.readAsString(),
    ).load();
    if (!mounted) return;
    final rawOnly = await _promptImportOptions(
      fileName: file.name,
      nameCount: list.filenames.length,
    );
    if (rawOnly == null) return; // cancelled
    final photos = ref.read(photosProvider).value ?? const <Photo>[];
    final ids = matchPhotoIds(list.filenames, photos, rawOnly: rawOnly);
    final selected = _applySelectionMaybeExpanding(ids);
    _revealFirstSelected(selected);
    _gridFocus.requestFocus();

    if (!mounted) return;
    _notify(
      'Selected ${ids.length} of ${list.filenames.length} from ${file.name}'
      '${_bracketSuffix(ids, selected)}',
    );
  }

  /// Photo-Mechanic-style "Find": paste a list of filenames (any separator,
  /// with or without extensions) and select every photo that matches
  /// (`BUILD_PLAN.md` §5). Robust to JPEG-named lists over RAW files.
  Future<void> _findByList() async {
    final photos = ref.read(photosProvider).value ?? const <Photo>[];
    if (photos.isEmpty) return;
    final result = await _promptList();
    if (result == null || result.text.trim().isEmpty) return;
    final names = parseNameTokens(result.text);
    final ids = matchPhotoIds(names, photos, rawOnly: result.rawOnly);
    final selected = _applySelectionMaybeExpanding(ids);
    _revealFirstSelected(selected);
    _gridFocus.requestFocus();
    if (!mounted) return;
    _notify(
      'Selected ${ids.length} of ${names.length} name(s)'
      '${_bracketSuffix(ids, selected)}',
      kind: ids.isEmpty ? NoticeKind.warning : NoticeKind.success,
    );
  }

  /// Replaces the selection with [ids], first growing it to each photo's
  /// exposure bracket when the auto-expand-on-select setting is on (the client
  /// only ever saw the normal exposures, so their picks re-attach the siblings
  /// automatically). Returns the ids actually selected.
  Set<int> _applySelectionMaybeExpanding(Set<int> ids) {
    var selected = ids;
    if (ids.isNotEmpty && ref.read(autoExpandBracketsOnSelectProvider)) {
      final groups = ref.read(bracketGroupsProvider);
      selected = {
        for (final id in ids) ...groups.groupOf(id),
      };
    }
    ref.read(cullControllerProvider.notifier).setSelection(selected);
    return selected;
  }

  /// A note like " (+6 bracket frames)" when auto-expand added photos.
  String _bracketSuffix(Set<int> matched, Set<int> selected) {
    final extra = selected.length - matched.length;
    return extra > 0 ? ' (+$extra bracket frames)' : '';
  }

  /// Grows the current selection to every frame of each selected photo's
  /// exposure bracket — the ±EV siblings the client never saw. The pivot of the
  /// interior-culling workflow: pull the client's picks in (⌘F paste-list or
  /// ContactSheet), then one keystroke re-attaches the bracketed exposures
  /// before export. Members hidden by the collapse filter still select — export
  /// reads the selection, not the filtered grid.
  void _expandSelectionToBrackets() {
    final selected = ref.read(cullControllerProvider).selectedIds;
    if (selected.isEmpty) {
      _notify('Select photos first', kind: NoticeKind.warning);
      return;
    }
    final groups = ref.read(bracketGroupsProvider);
    // Build the union selection-first so setSelection keeps focus on an
    // already-selected photo (it refocuses ids.first).
    final expanded = {
      ...selected,
      for (final id in selected) ...groups.groupOf(id),
    };
    if (expanded.length == selected.length) {
      _notify('No bracket members to add');
      _gridFocus.requestFocus();
      return;
    }
    ref.read(cullControllerProvider.notifier).setSelection(expanded);
    _gridFocus.requestFocus();
    _notify(
      'Expanded ${selected.length} → ${expanded.length} photos',
      kind: NoticeKind.success,
    );
  }

  /// Copies the focused frame's current rating, flag and colour onto the rest
  /// of its exposure bracket — a one-shot "match the bracket to this frame" for
  /// people who leave the propagate-to-stack setting off and only want it now
  /// and then (the context-menu entry only shows on a bracket member).
  Future<void> _applyMarksToBracket() async {
    final n = await ref
        .read(cullControllerProvider.notifier)
        .applyMarksToBracket();
    if (!mounted) return;
    _gridFocus.requestFocus();
    if (n == 0) {
      _notify('No bracket siblings to update', kind: NoticeKind.warning);
    } else {
      _notify(
        'Applied marks to $n bracket frame(s)',
        kind: NoticeKind.success,
      );
    }
  }

  /// Manually stacks the current selection into one exposure bracket,
  /// overriding automatic detection (a correction for a series the detector
  /// split or missed).
  Future<void> _stackSelection() async {
    final n = await ref.read(cullControllerProvider.notifier).stackSelection();
    if (!mounted) return;
    _gridFocus.requestFocus();
    if (n == 0) {
      _notify('Select 2+ photos to stack', kind: NoticeKind.warning);
    } else {
      _notify('Stacked $n photos', kind: NoticeKind.success);
    }
  }

  /// Manually removes the current selection from any bracket (a correction for
  /// frames the detector grouped that shouldn't be).
  Future<void> _unstackSelection() async {
    final n = await ref
        .read(cullControllerProvider.notifier)
        .unstackSelection();
    if (!mounted) return;
    _gridFocus.requestFocus();
    if (n == 0) {
      _notify('Select photos to unstack', kind: NoticeKind.warning);
    } else {
      _notify('Unstacked $n photos', kind: NoticeKind.success);
    }
  }

  /// Whether the "only RAWs" option should start checked: on when the grid is
  /// already showing RAW-only or hiding the JPEG side of pairs, so a culler in
  /// that mode gets the matching selection behaviour without an extra click.
  bool _rawOnlyDefault() {
    final filter = ref.read(photoFilterControllerProvider);
    return filter.fileType == FileTypeFilter.raw || filter.hideJpegPairs;
  }

  /// A "Only RAWs (skip JPEG twins)" checkbox row for the find/import dialogs.
  Widget _rawOnlyCheckbox({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => CheckboxListTile(
    value: value,
    onChanged: (v) => onChanged(v ?? false),
    controlAffinity: ListTileControlAffinity.leading,
    contentPadding: EdgeInsets.zero,
    dense: true,
    title: const Text(
      'Only RAWs (skip JPEG twins)',
      style: TextStyle(fontSize: 13),
    ),
    subtitle: const Text(
      'When a name has both a RAW and a JPEG, select just the RAW. A JPEG '
      'with no RAW twin is still selected.',
      style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
    ),
  );

  /// Multiline paste dialog for [_findByList]. Returns the entered text and the
  /// "only RAWs" choice, or null if cancelled.
  Future<({String text, bool rawOnly})?> _promptList() {
    final controller = TextEditingController();
    var rawOnly = _rawOnlyDefault();
    return showDialog<({String text, bool rawOnly})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Find photos by filename'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Paste a list of filenames (from Capture One, Lightroom or '
                  'ContactSheet). Any separator works, and the extension is '
                  'optional — a JPEG list still selects your RAWs.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: controller,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    hintText: '_AIV9551 _AIV9555 _AIV9562 …',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _rawOnlyCheckbox(
                  value: rawOnly,
                  onChanged: (v) => setState(() => rawOnly = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(
                (text: controller.text, rawOnly: rawOnly),
              ),
              child: const Text('Find'),
            ),
          ],
        ),
      ),
    );
  }

  /// Confirms an imported filename list and offers the "only RAWs" choice.
  /// Returns the chosen value, or null if cancelled.
  Future<bool?> _promptImportOptions({
    required String fileName,
    required int nameCount,
  }) {
    var rawOnly = _rawOnlyDefault();
    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Import selection list'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$nameCount name(s) from $fileName.',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _rawOnlyCheckbox(
                  value: rawOnly,
                  onChanged: (v) => setState(() => rawOnly = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(rawOnly),
              child: const Text('Import'),
            ),
          ],
        ),
      ),
    );
  }

  /// Saves the current grid selection under a name the user types, scoped to
  /// the open import (`BUILD_PLAN.md` §5: saved selections).
  Future<void> _saveSelection() async {
    final importId = ref.read(currentImportProvider);
    final ids = ref.read(cullControllerProvider).selectedIds;
    if (importId == null) return;
    if (ids.isEmpty) {
      _notify(
        'Select photos first to save a selection',
        kind: NoticeKind.warning,
      );
      return;
    }
    final name = await _promptText(
      title: 'Save selection',
      hint: 'Selection name',
    );
    if (name == null || name.trim().isEmpty) return;
    await ref
        .read(appDatabaseProvider)
        .saveSelection(
          importId: importId,
          name: name.trim(),
          photoIds: ids.toList(),
        );
    if (!mounted) return;
    _notify(
      'Saved "${name.trim()}" (${ids.length} photo(s))',
      kind: NoticeKind.success,
    );
    _gridFocus.requestFocus();
  }

  /// Replaces the grid selection with a previously saved one.
  void _loadSelection(SavedSelection selection) {
    ref
        .read(cullControllerProvider.notifier)
        .setSelection(
          selection.photoIds.toSet(),
        );
    _gridFocus.requestFocus();
    _notify('Loaded "${selection.name}" (${selection.photoIds.length})');
  }

  /// Deletes a saved selection.
  Future<void> _deleteSelection(SavedSelection selection) async {
    await ref.read(appDatabaseProvider).deleteSavedSelection(selection.id);
    if (!mounted) return;
    _notify('Deleted "${selection.name}"');
  }

  /// Shows a single-line text dialog and returns the entered text (or null if
  /// cancelled). Used for naming a saved selection.
  Future<String?> _promptText({
    required String title,
    required String hint,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
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
