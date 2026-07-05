part of 'cull_page.dart';

/// Keyboard dispatch and the compare overlay.
mixin _CullKeyboard on _CullJobs {
  // Fullscreen compare overlay: the snapshot of photo ids being compared (taken
  // from the selection when it opens), independent of later selection changes.
  bool _compareOpen = false;

  List<int> _compareIds = const [];

  // The compare tile the cull keys (1-5/P/X/colours) act on (§8); also drawn
  // with an accent ring. Null until compare opens.
  int? _compareFocusedId;

  // App-level keyboard shortcuts (⌘/Ctrl + key), wired through CallbackShortcuts
  // so they work whether or not the grid has focus (e.g. on the empty state).
  Map<ShortcutActivator, VoidCallback> _appShortcuts() {
    void both(
      LogicalKeyboardKey key,
      VoidCallback action,
      Map<ShortcutActivator, VoidCallback> m,
    ) {
      m[SingleActivator(key, meta: true)] = action;
      m[SingleActivator(key, control: true)] = action;
    }

    final m = <ShortcutActivator, VoidCallback>{};
    both(LogicalKeyboardKey.keyO, () => unawaited(_openFolder()), m);
    both(LogicalKeyboardKey.keyT, () => unawaited(_openFolder()), m);
    both(LogicalKeyboardKey.keyW, _closeActiveTab, m);
    both(LogicalKeyboardKey.keyA, _selectAllVisible, m);
    both(LogicalKeyboardKey.keyR, () => unawaited(_refreshFolder()), m);
    both(LogicalKeyboardKey.keyF, () => unawaited(_findByList()), m);
    both(LogicalKeyboardKey.keyS, () => unawaited(_export()), m);
    both(LogicalKeyboardKey.keyE, () => unawaited(_sendToPrimary()), m);
    // ⌘/Ctrl+Backspace = delete rejected photos (the Lightroom key). Plain
    // Backspace stays the colour-purple cull key — no clash, cull keys ignore
    // modifier combos.
    both(LogicalKeyboardKey.backspace, () => unawaited(_deleteRejects()), m);
    // Undo/redo for mark changes. `both` binds plain ⌘/Ctrl+Z (shift: false),
    // so the Shift variants below don't collide with it.
    both(LogicalKeyboardKey.keyZ, () => unawaited(_undoMarks()), m);
    m[const SingleActivator(
      LogicalKeyboardKey.keyZ,
      meta: true,
      shift: true,
    )] = () =>
        unawaited(_redoMarks());
    m[const SingleActivator(
      LogicalKeyboardKey.keyZ,
      control: true,
      shift: true,
    )] = () =>
        unawaited(_redoMarks());
    // `?` is handled in _onKey via the typed character (layout-independent).
    return m;
  }

  Future<void> _undoMarks() async {
    final undone = await ref.read(cullControllerProvider.notifier).undo();
    _notify(undone == null ? 'Nothing to undo' : 'Undid $undone');
  }

  Future<void> _redoMarks() async {
    final redone = await ref.read(cullControllerProvider.notifier).redo();
    _notify(redone == null ? 'Nothing to redo' : 'Redid $redone');
  }

  void _showShortcuts() => showKeyboardShortcuts(context);

  /// Pops the keyboard cheat sheet once, the first time the app is ever run, so
  /// new users discover the keyboard-first workflow. Persisted via
  /// [ShortcutsHintSeen] so it never shows again. No-op when already seen —
  /// which includes widget tests, whose seed defaults to "seen".
  void _maybeShowFirstRunShortcuts() {
    if (!mounted || ref.read(shortcutsHintSeenProvider)) return;
    ref.read(shortcutsHintSeenProvider.notifier).markSeen();
    showKeyboardShortcuts(context, firstRun: true);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    // `?` opens the shortcuts sheet. Match the character, not Shift+/, so it
    // works on layouts where `?` isn't Shift+Slash (e.g. German QWERTZ).
    if (event.character == '?') {
      _showShortcuts();
      return KeyEventResult.handled;
    }
    // Navigate over the filtered set the user actually sees.
    final photos = ref.read(filteredPhotosProvider);
    if (photos.isEmpty) return KeyEventResult.ignored;

    final controller = ref.read(cullControllerProvider.notifier);

    // ⌘/Ctrl combos are app-level shortcuts (open/new-tab/close/select-all):
    // let them bubble to the CallbackShortcuts ancestor instead of acting as
    // cull keys (e.g. ⌘P must not toggle the pick flag).
    if (HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed) {
      return KeyEventResult.ignored;
    }

    final focusedId = ref.read(cullControllerProvider).focusedId;
    if (focusedId == null) {
      controller.focus(photos.first.id);
      return KeyEventResult.handled;
    }
    final index = photos
        .indexWhere((p) => p.id == focusedId)
        .clamp(
          0,
          photos.length - 1,
        );
    final photo = photos[index];
    final id = photo.id;
    final key = event.logicalKey;

    // Resolve the pressed key to a (rebindable) cull action. Arrows, Esc,
    // Enter, `[`/`]`, numpad and Delete stay fixed and are checked directly.
    final action = ref.read(cullShortcutsControllerProvider).actionFor(key);

    if (_compareOpen) {
      // Esc, or the compare/group keys, toggle it shut. Cull keys mark the
      // focused tile; arrows move the focus. Everything else is swallowed so it
      // can't leak to the grid underneath.
      if (key == LogicalKeyboardKey.escape ||
          action == CullAction.compare ||
          action == CullAction.compareBurst) {
        setState(() => _compareOpen = false);
        return KeyEventResult.handled;
      }
      _handleCompareKey(key, action);
      return KeyEventResult.handled;
    }
    if (!_loupeOpen && action == CullAction.compare) {
      _openCompare();
      return KeyEventResult.handled;
    }
    if (!_loupeOpen && action == CullAction.compareBurst) {
      _compareBurst();
      return KeyEventResult.handled;
    }
    // Grid-only: grow the selection to each bracket's ±EV siblings. Acts on the
    // whole selection, so it runs before the per-photo mark handling below.
    if (!_loupeOpen && action == CullAction.expandBrackets) {
      _expandSelectionToBrackets();
      return KeyEventResult.handled;
    }

    if (_loupeOpen) {
      // Esc / Enter / loupe-key leave the loupe; `[`/`]` and arrows blit.
      if (key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.enter ||
          action == CullAction.loupe) {
        setState(() => _loupeOpen = false);
        return KeyEventResult.handled;
      }
      final step = loupeStepFor(key);
      if (step != null) {
        final next = (index + step).clamp(0, photos.length - 1);
        controller.focus(photos[next].id);
        _ensureRowVisible(next); // keep the grid in sync for when we exit
        return KeyEventResult.handled;
      }
      // Fall through: rate/flag/colour/select also work inside the loupe.
    } else {
      final direction = gridDirectionFor(key);
      if (direction != null) {
        final next = moveFocus(
          current: index,
          count: photos.length,
          columns: _columns,
          direction: direction,
        );
        controller.focus(photos[next].id);
        _ensureRowVisible(next);
        return KeyEventResult.handled;
      }
      // Enter or the loupe key: videos open externally, photos open the loupe.
      if (key == LogicalKeyboardKey.enter || action == CullAction.loupe) {
        if (isVideoPath(photo.path)) {
          unawaited(openExternally(photo.path));
        } else {
          setState(() => _loupeOpen = true);
        }
        return KeyEventResult.handled;
      }
    }

    // Rate/flag/colour: in the grid these apply to the whole selection (batch
    // marking); in the loupe you're viewing one photo, so they affect just it.
    // The toggle value is always computed from the focused photo.
    // In the loupe, a mark also flashes an ephemeral confirmation (event-driven
    // so it fires even when auto-advance blits to the next photo).
    Future<void> rate(int r) {
      if (!_loupeOpen) return controller.applyRating(r);
      ref.read(loupeMarkFlashProvider.notifier).rating(r);
      return controller.setRating(id, r);
    }

    Future<void> flagAs(PickFlag f) {
      if (!_loupeOpen) return controller.applyFlag(f);
      ref.read(loupeMarkFlashProvider.notifier).flag(f);
      return controller.setFlag(id, f);
    }

    Future<void> colorAs(ColorLabel c) {
      if (!_loupeOpen) return controller.applyColor(c);
      ref.read(loupeMarkFlashProvider.notifier).color(c);
      return controller.setColor(id, c);
    }

    Future<void> rotateBy(int turns) => _loupeOpen
        ? controller.rotate(id, turns)
        : controller.applyRotation(turns);

    // Numpad 1–5 stays a fixed secondary alongside the (rebindable) digits.
    final rating = ratingForAction(action) ?? numpadRatingFor(key);
    if (rating != null) {
      unawaited(rate(photo.rating == rating ? 0 : rating));
      _advanceAfterMark(index, photos);
      return KeyEventResult.handled;
    }
    // Delete stays fixed alongside the (rebindable) clear-rating key.
    if (action == CullAction.clearRating || key == LogicalKeyboardKey.delete) {
      unawaited(rate(0));
      _advanceAfterMark(index, photos);
      return KeyEventResult.handled;
    }
    if (action == CullAction.pick) {
      unawaited(
        flagAs(photo.flag == PickFlag.pick ? PickFlag.none : PickFlag.pick),
      );
      _advanceAfterMark(index, photos);
      return KeyEventResult.handled;
    }
    if (action == CullAction.reject) {
      unawaited(
        flagAs(
          photo.flag == PickFlag.reject ? PickFlag.none : PickFlag.reject,
        ),
      );
      _advanceAfterMark(index, photos);
      return KeyEventResult.handled;
    }
    final color = colorForAction(action);
    if (color != null) {
      unawaited(colorAs(photo.colorLabel == color ? ColorLabel.none : color));
      _advanceAfterMark(index, photos);
      return KeyEventResult.handled;
    }
    if (action == CullAction.select) {
      controller.toggleSelect(id);
      return KeyEventResult.handled;
    }
    if (action == CullAction.keywords) {
      // A dialog, so typing doesn't trip cull keys. Restore grid focus after.
      unawaited(
        showKeywordEditor(context, ref).then((_) => _gridFocus.requestFocus()),
      );
      return KeyEventResult.handled;
    }
    if (action == CullAction.metadata) {
      unawaited(
        showIptcEditor(context, ref).then((_) => _gridFocus.requestFocus()),
      );
      return KeyEventResult.handled;
    }
    if (action == CullAction.applyTemplate) {
      unawaited(_applyTemplate());
      return KeyEventResult.handled;
    }
    if (action == CullAction.rename) {
      unawaited(_rename());
      return KeyEventResult.handled;
    }
    if (action == CullAction.rotateRight) {
      unawaited(rotateBy(1));
      return KeyEventResult.handled;
    }
    if (action == CullAction.rotateLeft) {
      unawaited(rotateBy(-1));
      return KeyEventResult.handled;
    }
    if (action == CullAction.inspector) {
      ref.read(inspectorOpenProvider.notifier).toggle();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Photo-Mechanic-style auto-advance: after marking a *single* photo, step
  /// focus to the next one (blitting the loupe forward when it's open). Batch
  /// marks — a multi-photo selection — stay put, since the user is deliberately
  /// tagging a group. No-op unless enabled in Settings, or already on the last
  /// photo. [index] is the just-marked photo's position in [photos].
  void _advanceAfterMark(int index, List<Photo> photos) {
    if (!ref.read(autoAdvanceAfterMarkProvider)) return;
    if (!_loupeOpen &&
        ref.read(cullControllerProvider).markTargets.length > 1) {
      return;
    }
    final next = index + 1;
    if (next >= photos.length) return; // already on the last photo
    ref.read(cullControllerProvider.notifier).focus(photos[next].id);
    _ensureRowVisible(next);
  }

  /// Opens the compare view on the current selection (≥2 photos), grid order.
  void _openCompare() {
    final selected = ref.read(cullControllerProvider).selectedIds;
    final ordered = [
      for (final p in ref.read(filteredPhotosProvider))
        if (selected.contains(p.id)) p.id,
    ];
    if (ordered.length < 2) {
      _notify('Select 2+ photos to compare', kind: NoticeKind.warning);
      return;
    }
    final focused = ref.read(cullControllerProvider).focusedId;
    setState(() {
      _compareIds = ordered;
      _compareFocusedId = ordered.contains(focused) ? focused : ordered.first;
      _compareOpen = true;
    });
  }

  /// Opens the compare view on the focused photo's group — the perceptual-hash
  /// similarity group when computed, else its capture-time burst (§8).
  void _compareBurst() {
    final focusedId = ref.read(cullControllerProvider).focusedId;
    if (focusedId == null) return;
    final group = ref.read(effectiveGroupsProvider).groupOf(focusedId);
    if (group.length < 2) {
      _notify('This photo isn’t part of a group', kind: NoticeKind.warning);
      return;
    }
    setState(() {
      _compareIds = group;
      _compareFocusedId = group.contains(focusedId) ? focusedId : group.first;
      _compareOpen = true;
    });
  }

  /// Routes a key inside the compare overlay (§8 keyboard culling): arrows move
  /// the focused tile, the cull keys (1-5/0/P/X/colours/K/M/T) mark its
  /// photo — single-tile, like the loupe.
  void _handleCompareKey(LogicalKeyboardKey key, CullAction? action) {
    if (_compareIds.isEmpty) return;
    final all = ref.read(photosProvider).value ?? const <Photo>[];
    final byId = {for (final p in all) p.id: p};
    final focusedId =
        (_compareFocusedId != null && _compareIds.contains(_compareFocusedId))
        ? _compareFocusedId!
        : _compareIds.first;

    final direction = gridDirectionFor(key);
    if (direction != null) {
      final next = compareFocusAfterMove(
        ids: _compareIds,
        focusedId: focusedId,
        columns: CompareView.columnsFor(_compareIds.length),
        direction: direction,
      );
      setState(() => _compareFocusedId = next);
      return;
    }

    final photo = byId[focusedId];
    if (photo == null) return;
    final controller = ref.read(cullControllerProvider.notifier);

    final rating = ratingForAction(action) ?? numpadRatingFor(key);
    if (rating != null) {
      unawaited(
        controller.setRating(photo.id, photo.rating == rating ? 0 : rating),
      );
      return;
    }
    if (action == CullAction.clearRating || key == LogicalKeyboardKey.delete) {
      unawaited(controller.setRating(photo.id, 0));
      return;
    }
    if (action == CullAction.pick) {
      unawaited(
        controller.setFlag(
          photo.id,
          photo.flag == PickFlag.pick ? PickFlag.none : PickFlag.pick,
        ),
      );
      return;
    }
    if (action == CullAction.reject) {
      unawaited(
        controller.setFlag(
          photo.id,
          photo.flag == PickFlag.reject ? PickFlag.none : PickFlag.reject,
        ),
      );
      return;
    }
    final color = colorForAction(action);
    if (color != null) {
      unawaited(
        controller.setColor(
          photo.id,
          photo.colorLabel == color ? ColorLabel.none : color,
        ),
      );
      return;
    }
    if (action == CullAction.keywords) {
      // Keyword editor targets the focused photo; point it at this tile first.
      controller.selectOnly(photo.id);
      unawaited(
        showKeywordEditor(context, ref).then((_) => _gridFocus.requestFocus()),
      );
    }
    if (action == CullAction.metadata) {
      controller.selectOnly(photo.id);
      unawaited(
        showIptcEditor(context, ref).then((_) => _gridFocus.requestFocus()),
      );
    }
    if (action == CullAction.applyTemplate) {
      // The template stamps the mark targets; point them at this tile first.
      controller.selectOnly(photo.id);
      unawaited(_applyTemplate());
    }
  }

  /// Drops one photo from the open comparison; closes it when none remain.
  void _removeFromCompare(int photoId) {
    setState(() {
      _compareFocusedId = compareFocusAfterRemove(
        ids: _compareIds,
        removedId: photoId,
        focusedId: _compareFocusedId,
      );
      _compareIds = _compareIds.where((e) => e != photoId).toList();
      if (_compareIds.isEmpty) _compareOpen = false;
    });
  }
}
