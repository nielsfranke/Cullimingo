import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/features/ingest/domain/rename_template.dart';
import 'package:cullimingo/features/naming/domain/name_element.dart';
import 'package:cullimingo/features/naming/domain/name_preset.dart';
import 'package:cullimingo/shared/widgets/dialog_kit.dart';
import 'package:flutter/material.dart';

/// The naming builder (`BUILD_PLAN.md` §5/§6), Photo-Mechanic style: pick a
/// saved preset, then build a **Filename** and **Folder** pattern in plain text
/// fields — type freely and drop/insert element tokens (`{origname}`, `{seq:3}`,
/// `{date:iso}`, …) at the caret. A live example shows the result.
///
/// The two fields collapse into one engine pattern (`folder/filename`), so the
/// preview is produced by the very engine that does the copy — preview and
/// output can't drift. Emits a [NamePreset] on every edit; the host turns it
/// into a [RenameTemplate] and persists saved presets.
class NameBuilder extends StatefulWidget {
  /// Creates the naming builder.
  const NameBuilder({
    required this.initial,
    required this.savedPresets,
    required this.onChanged,
    required this.onSavePreset,
    required this.onDeletePreset,
    this.sampleShoot = 'Shoot',
    this.showFolder = true,
    this.shootController,
    this.onShootChanged,
    this.sampleInput,
    super.key,
  });

  /// The scheme to start editing from.
  final NamePreset initial;

  /// The user's saved presets (from settings). Built-ins are prepended here.
  final List<NamePreset> savedPresets;

  /// Called with the current scheme after every edit (name empty when custom).
  final ValueChanged<NamePreset> onChanged;

  /// Called to persist a new/updated saved preset (host writes settings).
  final ValueChanged<NamePreset> onSavePreset;

  /// Called to delete the saved preset with this name.
  final ValueChanged<String> onDeletePreset;

  /// Sample job name used in the live example.
  final String sampleShoot;

  /// Whether to show the **Folder** pattern row. An in-place rename stays in
  /// the file's folder, so it hides this and uses only the filename pattern.
  final bool showFolder;

  /// When set, the builder renders a **Job name** row right under the preset
  /// picker — but only while the current pattern actually uses the Job-name
  /// element, so the field never sits there without effect. The host keeps
  /// owning the controller (it drives the host's plan/preview).
  final TextEditingController? shootController;

  /// Called on every Job-name keystroke (host rebuilds its preview).
  final ValueChanged<String>? onShootChanged;

  /// When set, the live example renders this real file instead of the built-in
  /// synthetic sample — so the host can show the first file that will actually
  /// be imported/exported.
  final RenameInput? sampleInput;

  @override
  State<NameBuilder> createState() => _NameBuilderState();
}

/// Which of the two fields an inserted element lands in.
enum _Field { folder, file }

class _NameBuilderState extends State<NameBuilder> {
  final TextEditingController _fileCtrl = TextEditingController();
  final TextEditingController _folderCtrl = TextEditingController();
  final FocusNode _fileFocus = FocusNode();
  final FocusNode _folderFocus = FocusNode();

  /// Counter start (engine keeps this; kept at the preset's value, default 1).
  int _counterStart = 1;

  /// The saved/built-in preset the editor currently matches, or null (custom).
  String? _selectedName;

  /// The field a palette insert targets (the last one the user touched).
  _Field _active = _Field.file;

  /// Whether the pattern editor (Filename/Folder fields + element palette) is
  /// expanded. Collapsed by default — most sessions just pick a preset and
  /// type a job name; the editor opens automatically for a custom scheme.
  bool _customiseOpen = false;

  RenameInput get _sample =>
      widget.sampleInput ??
      RenameInput(
        capturedAt: DateTime(2026, 7, 2, 14, 30, 5),
        originalName: 'DSC0001.ARW',
        sequence: 1,
        camera: 'ILCE-7M4',
        shoot: widget.sampleShoot,
      );

  List<NamePreset> get _presets => [
    ...NamePreset.builtIns,
    ...widget.savedPresets,
  ];

  @override
  void initState() {
    super.initState();
    _fileFocus.addListener(() {
      if (_fileFocus.hasFocus) _active = _Field.file;
    });
    _folderFocus.addListener(() {
      if (_folderFocus.hasFocus) _active = _Field.folder;
    });
    _loadFrom(widget.initial);
    // A custom scheme has no preset to stand for it — show its fields.
    _customiseOpen = _selectedName == null;
  }

  @override
  void didUpdateWidget(NameBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Adopt an externally-changed scheme (e.g. the host restoring the last
    // import's preset from settings after its async load). Guarded so the
    // host echoing our own onChanged back as `initial` never resets the
    // fields (and the caret) mid-typing: by then the editor already matches.
    if (!oldWidget.initial.sameSchemeAs(widget.initial) &&
        !widget.initial.sameSchemeAs(_current(name: ''))) {
      setState(() {
        _loadFrom(widget.initial);
        _customiseOpen = _customiseOpen || _selectedName == null;
      });
    }
  }

  @override
  void dispose() {
    _fileCtrl.dispose();
    _folderCtrl.dispose();
    _fileFocus.dispose();
    _folderFocus.dispose();
    super.dispose();
  }

  void _loadFrom(NamePreset preset) {
    _fileCtrl.text = engineToDisplay(preset.filePattern);
    _folderCtrl.text = engineToDisplay(preset.folderPattern);
    _counterStart = preset.counterStart;
    _selectedName = _matchingPresetName();
  }

  NamePreset _current({String? name}) => NamePreset(
    name: name ?? _selectedName ?? '',
    // A folder-less builder (in-place rename) never contributes a sub-folder,
    // even if a chosen preset carries one — the file stays put.
    folderPattern: widget.showFolder ? displayToEngine(_folderCtrl.text) : '',
    filePattern: displayToEngine(_fileCtrl.text),
    counterStart: _counterStart,
  );

  String? _matchingPresetName() => _presets
      .where((p) => p.sameSchemeAs(_current(name: '')))
      .map((p) => p.name)
      .firstOrNull;

  /// Recomputes the matching preset and notifies the host.
  void _emit() {
    setState(() => _selectedName = _matchingPresetName());
    widget.onChanged(_current());
  }

  /// Inserts `{token}` at the active field's caret (or its end).
  void _insert(String token) {
    final ctrl = _active == _Field.folder ? _folderCtrl : _fileCtrl;
    final focus = _active == _Field.folder ? _folderFocus : _fileFocus;
    final value = ctrl.value;
    final text = value.text;
    final sel = value.selection;
    final start = sel.start >= 0 ? sel.start : text.length;
    final end = sel.end >= 0 ? sel.end : text.length;
    final insert = displayTokenFor(token);
    ctrl.value = TextEditingValue(
      text: text.replaceRange(start, end, insert),
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
    focus.requestFocus();
    _emit();
  }

  void _selectPreset(NamePreset preset) {
    _loadFrom(preset);
    setState(() => _selectedName = preset.name);
    widget.onChanged(_current());
  }

  Future<void> _saveAs() async {
    final name = await _promptName(context, initial: _selectedName ?? '');
    if (name == null || name.trim().isEmpty) return;
    widget.onSavePreset(_current(name: name.trim()));
    setState(() => _selectedName = name.trim());
  }

  String? get _example {
    if (_fileCtrl.text.trim().isEmpty) return null;
    final path = _current(name: '').toTemplate().pathFor(_sample);
    return path.isEmpty ? null : path;
  }

  /// Whether the current pattern uses the Job-name element (drives the
  /// Job-name row's visibility).
  bool get _usesShoot =>
      _current(name: '').toTemplate().pattern.contains('{shoot}');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _presetRow(),
        if (widget.shootController != null && _usesShoot) ...[
          const SizedBox(height: AppSpacing.sm),
          _shootRow(),
        ],
        const SizedBox(height: AppSpacing.sm),
        _exampleLine(),
        const SizedBox(height: AppSpacing.xs),
        DialogDisclosure(
          label: widget.showFolder
              ? 'Customise filename & folders'
              : 'Customise filename',
          open: _customiseOpen,
          onToggle: () => setState(() => _customiseOpen = !_customiseOpen),
        ),
        if (_customiseOpen) ...[
          const SizedBox(height: AppSpacing.xs),
          _fieldRow(
            'Filename',
            _fileCtrl,
            _fileFocus,
            _Field.file,
            'Type here, or insert elements below…',
          ),
          if (widget.showFolder) ...[
            const SizedBox(height: AppSpacing.xs),
            _fieldRow(
              'Folder',
              _folderCtrl,
              _folderFocus,
              _Field.folder,
              'Optional sub-folders, e.g. {YYYY}/{MM}',
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          const DialogSection('Elements'),
          _palette(),
        ],
      ],
    );
  }

  /// The Job-name input, aligned with the Filename/Folder/Example rows. Shown
  /// right under the preset picker: it's the one thing a user types on a
  /// routine import, so it must not hide below the pattern editor.
  Widget _shootRow() => Row(
    children: [
      const SizedBox(
        width: 64,
        child: Text(
          'Job name',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ),
      Expanded(
        child: TextField(
          controller: widget.shootController,
          onChanged: widget.onShootChanged,
          decoration: dialogInputDecoration(
            'e.g. Wedding-Anna (used by the Job-name element)',
          ).copyWith(isDense: true),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
        ),
      ),
    ],
  );

  Widget _presetRow() => Row(
    children: [
      Expanded(
        child: DialogDropdown<String>(
          value: _selectedName,
          hint: 'Custom',
          items: [
            for (final p in _presets)
              DropdownMenuItem(value: p.name, child: Text(p.name)),
          ],
          onChanged: (name) {
            final preset = _presets.where((p) => p.name == name).firstOrNull;
            if (preset != null) _selectPreset(preset);
          },
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      _presetMenu(),
    ],
  );

  Widget _presetMenu() {
    final selected = _presets.where((p) => p.name == _selectedName).firstOrNull;
    final canDelete = selected != null && !selected.builtIn;
    return PopupMenuButton<String>(
      tooltip: 'Preset actions',
      popUpAnimationStyle: kMenuAnimationStyle,
      color: AppColors.surfaceElevated,
      icon: const Icon(
        Icons.more_vert,
        size: 18,
        color: AppColors.textSecondary,
      ),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'saveAs',
          child: Text('Save as new preset…'),
        ),
        if (canDelete)
          PopupMenuItem(
            value: 'delete',
            child: Text("Delete '${selected.name}'"),
          ),
      ],
      onSelected: (action) async {
        if (action == 'saveAs') {
          await _saveAs();
        } else if (action == 'delete' && selected != null) {
          widget.onDeletePreset(selected.name);
          setState(() => _selectedName = null);
        }
      },
    );
  }

  /// A label + a plain text field that also accepts dropped element tokens.
  Widget _fieldRow(
    String label,
    TextEditingController ctrl,
    FocusNode focus,
    _Field field,
    String hint,
  ) => Row(
    children: [
      SizedBox(
        width: 64,
        child: Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ),
      Expanded(
        child: DragTarget<String>(
          onAcceptWithDetails: (d) {
            setState(() => _active = field);
            _insert(d.data);
          },
          builder: (_, candidate, _) => TextField(
            controller: ctrl,
            focusNode: focus,
            onTap: () => _active = field,
            onChanged: (_) => _emit(),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontFamily: 'monospace',
            ),
            decoration: dialogInputDecoration(hint).copyWith(
              isDense: true,
              enabledBorder: candidate.isEmpty
                  ? null
                  : const OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.accent),
                    ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _exampleLine() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(
        width: 64,
        child: Text(
          'Example',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ),
      Expanded(
        child: Text(
          _example ?? '—',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontFamily: 'monospace',
          ),
        ),
      ),
    ],
  );

  Widget _palette() => Wrap(
    spacing: AppSpacing.lg,
    runSpacing: AppSpacing.sm,
    children: [
      for (final group in paletteGroups)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                group.title,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [for (final el in group.elements) _element(el)],
            ),
          ],
        ),
    ],
  );

  Widget _element(NameElement el) {
    switch (el.option) {
      case NameOption.counter:
        return _menuChip<int>(
          label: el.label,
          items: [
            for (final w in counterWidths)
              PopupMenuItem(
                value: w,
                child: Text('$w digit${w == 1 ? '' : 's'}'),
              ),
          ],
          onSelected: (w) => _insert('seq:$w'),
        );
      case NameOption.date:
        return _menuChip<String>(
          label: el.label,
          items: [
            for (final f in dateFormats)
              PopupMenuItem(value: f.key, child: Text(f.label)),
          ],
          onSelected: (key) => _insert('date:$key'),
        );
      case NameOption.none:
        // A plain element: click to insert at the caret, or drag into a field.
        return Draggable<String>(
          data: el.token,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: _DragFeedback(el.label),
          child: _PaletteButton(
            label: el.label,
            onTap: () => _insert(el.token),
          ),
        );
    }
  }

  Widget _menuChip<T>({
    required String label,
    required List<PopupMenuEntry<T>> items,
    required ValueChanged<T> onSelected,
  }) => PopupMenuButton<T>(
    tooltip: label,
    popUpAnimationStyle: kMenuAnimationStyle,
    color: AppColors.surfaceElevated,
    padding: EdgeInsets.zero,
    itemBuilder: (_) => items,
    onSelected: onSelected,
    child: _PaletteButton(label: '$label ▾', onTap: null),
  );

  static Future<String?> _promptName(
    BuildContext context, {
    required String initial,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Save naming preset'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: dialogInputDecoration('Preset name'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// A pill button in the "Elements" palette. [onTap] is null when the pill is
/// only a trigger for an enclosing menu (the enclosing button handles the tap).
class _PaletteButton extends StatelessWidget {
  const _PaletteButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceElevated,
    borderRadius: BorderRadius.circular(AppRadius.sm),
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 5,
        ),
        child: Text(
          label,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
        ),
      ),
    ),
  );
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
      ),
    ),
  );
}
