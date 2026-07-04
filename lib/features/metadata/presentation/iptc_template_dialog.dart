import 'dart:async';

import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/features/metadata/data/template_file.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/features/metadata/domain/iptc_structured.dart';
import 'package:cullimingo/features/metadata/domain/iptc_template.dart';
import 'package:cullimingo/features/metadata/domain/keyword_text.dart';
import 'package:cullimingo/features/metadata/domain/recent_field_values.dart';
import 'package:cullimingo/features/metadata/presentation/iptc_table_field.dart';
import 'package:cullimingo/shared/widgets/dialog_kit.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

/// Opens the metadata-template editor seeded from [initial] and returns the
/// edited template, or null if cancelled. [recent] powers the per-field ▼
/// recent-values menu.
Future<IptcTemplate?> showTemplateEditor(
  BuildContext context, {
  required IptcTemplate initial,
  RecentFieldValues recent = const RecentFieldValues(),
}) => showDialog<IptcTemplate>(
  context: context,
  // A form — an outside click must not discard the template being edited.
  barrierDismissible: false,
  builder: (_) => IptcTemplateDialog(initial: initial, recent: recent),
);

/// The Photo Mechanic "stationery pad": pick which fields to stamp (the
/// per-field checkbox), type their values, and choose how caption and keywords
/// merge. Only ticked fields end up in the saved [IptcTemplate]. Typing into a
/// field ticks it automatically, so the common case needs no extra clicks.
/// Constructed directly with [initial] so it is widget-testable without
/// providers.
class IptcTemplateDialog extends StatefulWidget {
  /// Creates the template editor over an [initial] template, with [recent]
  /// per-field history for the ▼ menu.
  const IptcTemplateDialog({
    required this.initial,
    this.recent = const RecentFieldValues(),
    this.pickLoadPath,
    this.pickSavePath,
    super.key,
  });

  /// The template to seed the form from (empty for a fresh template).
  final IptcTemplate initial;

  /// Per-field recent-values history powering the ▼ menu.
  final RecentFieldValues recent;

  /// Picks the XMP file "Load XMP…" reads (null → the real file picker).
  /// Injectable so widget tests run without a native dialog.
  final Future<String?> Function()? pickLoadPath;

  /// Picks the path "Save XMP…" writes to (null → the real file picker).
  final Future<String?> Function()? pickSavePath;

  @override
  State<IptcTemplateDialog> createState() => _IptcTemplateDialogState();
}

class _IptcTemplateDialogState extends State<IptcTemplateDialog> {
  late final Map<IptcField, bool> _active = {
    for (final field in IptcField.values)
      field: widget.initial.fields.containsKey(field),
  };
  late final Map<IptcField, TextEditingController> _controllers = {
    for (final field in IptcField.values)
      field: TextEditingController(text: widget.initial.fields[field] ?? ''),
  };
  late final Map<IptcField, TextApplyMode> _modes = {
    for (final field in IptcField.values) field: widget.initial.modeFor(field),
  };
  late bool _keywordsActive = widget.initial.keywords != null;
  late final TextEditingController _keywords = TextEditingController(
    text: formatKeywords(widget.initial.keywords ?? const []),
  );
  late KeywordApplyMode _keywordMode = widget.initial.keywordMode;

  // Structured tables as row/cell string matrices (converted to records on
  // save). Columns match _*Columns below.
  late List<List<String>> _locationsShown = [
    for (final l in widget.initial.locationsShown)
      [
        l.sublocation,
        l.city,
        l.state,
        l.country,
        l.countryCode,
        l.worldRegion,
        l.locationId,
      ],
  ];
  late List<List<String>> _artwork = [
    for (final a in widget.initial.artwork)
      [a.title, a.creator, a.source, a.copyrightNotice],
  ];
  late List<List<String>> _imageCreators = [
    for (final e in widget.initial.imageCreators) [e.name, e.identifier],
  ];
  late List<List<String>> _copyrightOwners = [
    for (final e in widget.initial.copyrightOwners) [e.name, e.identifier],
  ];
  late List<List<String>> _licensors = [
    for (final l in widget.initial.licensors)
      [l.name, l.id, l.phone, l.email, l.url],
  ];
  late List<List<String>> _registryEntries = [
    for (final r in widget.initial.registryEntries)
      [r.itemId, r.organisationId],
  ];

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _keywords.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_current());

  /// The template the form currently describes (what Save would return).
  IptcTemplate _current() {
    final fields = <IptcField, String>{
      for (final field in IptcField.values)
        if (_active[field]!) field: _controllers[field]!.text,
    };
    final textModes = <IptcField, TextApplyMode>{
      for (final field in IptcField.values)
        if (field.mergeable && _modes[field] != TextApplyMode.replace)
          field: _modes[field]!,
    };
    return IptcTemplate(
      fields: fields,
      textModes: textModes,
      keywords: _keywordsActive ? parseKeywords(_keywords.text) : null,
      keywordMode: _keywordMode,
      locationsShown: [
        for (final r in _locationsShown)
          IptcLocation(
            sublocation: _cell(r, 0),
            city: _cell(r, 1),
            state: _cell(r, 2),
            country: _cell(r, 3),
            countryCode: _cell(r, 4),
            worldRegion: _cell(r, 5),
            locationId: _cell(r, 6),
          ),
      ].where((l) => !l.isEmpty).toList(),
      artwork: [
        for (final r in _artwork)
          IptcArtwork(
            title: r[0].trim(),
            creator: r[1].trim(),
            source: r[2].trim(),
            copyrightNotice: r[3].trim(),
          ),
      ].where((a) => !a.isEmpty).toList(),
      imageCreators: [
        for (final r in _imageCreators)
          IptcEntity(name: r[0].trim(), identifier: r[1].trim()),
      ].where((e) => !e.isEmpty).toList(),
      copyrightOwners: [
        for (final r in _copyrightOwners)
          IptcEntity(name: r[0].trim(), identifier: r[1].trim()),
      ].where((e) => !e.isEmpty).toList(),
      licensors: [
        for (final r in _licensors)
          IptcLicensor(
            name: r[0].trim(),
            id: r[1].trim(),
            phone: r[2].trim(),
            email: r[3].trim(),
            url: r[4].trim(),
          ),
      ].where((l) => !l.isEmpty).toList(),
      registryEntries: [
        for (final r in _registryEntries)
          IptcRegistryEntry(itemId: r[0].trim(), organisationId: r[1].trim()),
      ].where((r) => !r.isEmpty).toList(),
    );
  }

  /// Re-seeds the whole form from [template]: field values, active ticks,
  /// merge modes, keywords and tables. Bumps [_generation] so the mounted
  /// table editors (which copy their seed rows) rebuild from the new matrices.
  void _seedFrom(IptcTemplate template) => setState(() {
    for (final field in IptcField.values) {
      _controllers[field]!.text = template.fields[field] ?? '';
      _active[field] = template.fields.containsKey(field);
      _modes[field] = template.modeFor(field);
    }
    _keywordsActive = template.keywords != null;
    _keywords.text = formatKeywords(template.keywords ?? const []);
    _keywordMode = template.keywordMode;
    _locationsShown = [
      for (final l in template.locationsShown)
        [
          l.sublocation,
          l.city,
          l.state,
          l.country,
          l.countryCode,
          l.worldRegion,
          l.locationId,
        ],
    ];
    _artwork = [
      for (final a in template.artwork)
        [a.title, a.creator, a.source, a.copyrightNotice],
    ];
    _imageCreators = [
      for (final e in template.imageCreators) [e.name, e.identifier],
    ];
    _copyrightOwners = [
      for (final e in template.copyrightOwners) [e.name, e.identifier],
    ];
    _licensors = [
      for (final l in template.licensors)
        [l.name, l.id, l.phone, l.email, l.url],
    ];
    _registryEntries = [
      for (final r in template.registryEntries) [r.itemId, r.organisationId],
    ];
    _generation++;
  });

  /// Photo Mechanic's "Clear": empty the whole pad.
  void _clear() => _seedFrom(const IptcTemplate());

  /// Loads an XMP template file (Photo Mechanic / Bridge interop) into the
  /// pad, replacing its contents — the PM "Load…" semantics.
  Future<void> _loadXmp() async {
    final path = await (widget.pickLoadPath ?? _pickXmpOpen)();
    if (path == null) return;
    final IptcTemplate template;
    try {
      template = await readTemplateXmpFile(path);
    } on Exception catch (e) {
      if (mounted) {
        await showErrorNotice(
          context,
          title: 'Could not load the template',
          message: e is TemplateFileException ? e.message : '$e',
        );
      }
      return;
    }
    if (mounted) _seedFrom(template);
  }

  /// Saves the pad's current values as an XMP template file that Photo
  /// Mechanic and Bridge can load. Merge modes don't travel (no XMP form).
  Future<void> _saveXmp() async {
    final path = await (widget.pickSavePath ?? _pickXmpSave)();
    if (path == null) return;
    try {
      await writeTemplateXmpFile(path, _current());
    } on Exception catch (e) {
      if (mounted) {
        await showErrorNotice(
          context,
          title: 'Could not save the template',
          message: e is TemplateFileException ? e.message : '$e',
        );
      }
    }
  }

  static const XTypeGroup _xmpGroup = XTypeGroup(
    label: 'XMP templates',
    extensions: ['xmp', 'XMP'],
  );

  static Future<String?> _pickXmpOpen() async =>
      (await openFile(acceptedTypeGroups: [_xmpGroup]))?.path;

  static Future<String?> _pickXmpSave() async => (await getSaveLocation(
    acceptedTypeGroups: [_xmpGroup],
    suggestedName: 'metadata-template.xmp',
  ))?.path;

  /// Bumped whenever the form is re-seeded wholesale (Clear / Load XMP), so
  /// the table editors — which copy their seed — remount with fresh rows.
  int _generation = 0;

  /// Trimmed cell [i] of a table row, tolerating short rows (older saved
  /// templates predate the extra location columns).
  static String _cell(List<String> r, int i) => i < r.length ? r[i].trim() : '';

  /// Which section the left nav-rail has selected.
  _TemplateTab _tab = _TemplateTab.content;

  static const List<String> _locationColumns = [
    'Sublocation',
    'City',
    'State',
    'Country',
    'ISO',
    'World region',
    'Location ID',
  ];
  static const List<String> _artworkColumns = [
    'Title',
    'Creator',
    'Source',
    'Copyright',
  ];
  static const List<String> _entityColumns = ['Name', 'Identifier'];
  static const List<String> _licensorColumns = [
    'Name',
    'ID',
    'Phone',
    'Email',
    'URL',
  ];
  static const List<String> _registryColumns = ['Item ID', 'Org ID'];

  /// The `_TemplateField` rows for every field in [groups], in enum order.
  /// Date Created is skipped: stamping one fixed capture date onto a batch of
  /// photos makes no sense — it belongs in the per-photo M editor only.
  List<Widget> _groupFields(List<IptcFieldGroup> groups) => [
    for (final field in IptcField.values)
      if (groups.contains(field.group) && field != IptcField.dateCreated)
        _TemplateField(
          key: ValueKey(field),
          field: field,
          active: _active[field]!,
          controller: _controllers[field]!,
          onActiveChanged: (v) => setState(() => _active[field] = v),
          mode: field.mergeable ? _modes[field] : null,
          onModeChanged: (m) => setState(() => _modes[field] = m),
          recent: widget.recent.forField(field),
          onPickRecent: (value) => setState(() {
            _controllers[field]!.text = value;
            _active[field] = true;
          }),
        ),
  ];

  /// The right-pane content for [tab].
  List<Widget> _sectionFor(_TemplateTab tab) => switch (tab) {
    _TemplateTab.content => _groupFields([IptcFieldGroup.description]),
    _TemplateTab.location => _groupFields([IptcFieldGroup.location]),
    _TemplateTab.rights => _groupFields([IptcFieldGroup.credit]),
    _TemplateTab.status => _groupFields([
      IptcFieldGroup.status,
      IptcFieldGroup.releases,
    ]),
    _TemplateTab.ai => _groupFields([IptcFieldGroup.ai]),
    _TemplateTab.keywords => [
      _KeywordsField(
        active: _keywordsActive,
        controller: _keywords,
        mode: _keywordMode,
        onActiveChanged: (v) => setState(() => _keywordsActive = v),
        onModeChanged: (m) => setState(() => _keywordMode = m),
      ),
    ],
    _TemplateTab.tables => [
      IptcTableField(
        key: ValueKey('locations-$_generation'),
        title: 'Locations shown',
        columns: _locationColumns,
        rows: _locationsShown,
        onChanged: (r) => _locationsShown = r,
      ),
      IptcTableField(
        key: ValueKey('artwork-$_generation'),
        title: 'Artwork or object',
        columns: _artworkColumns,
        rows: _artwork,
        onChanged: (r) => _artwork = r,
      ),
      IptcTableField(
        key: ValueKey('creators-$_generation'),
        title: 'Image creators',
        columns: _entityColumns,
        rows: _imageCreators,
        onChanged: (r) => _imageCreators = r,
      ),
      IptcTableField(
        key: ValueKey('owners-$_generation'),
        title: 'Copyright owners',
        columns: _entityColumns,
        rows: _copyrightOwners,
        onChanged: (r) => _copyrightOwners = r,
      ),
      IptcTableField(
        key: ValueKey('licensors-$_generation'),
        title: 'Licensors',
        columns: _licensorColumns,
        rows: _licensors,
        onChanged: (r) => _licensors = r,
      ),
      IptcTableField(
        key: ValueKey('registry-$_generation'),
        title: 'Registry entries',
        columns: _registryColumns,
        rows: _registryEntries,
        onChanged: (r) => _registryEntries = r,
      ),
    ],
  };

  @override
  Widget build(BuildContext context) {
    // Scale the dialog to the window: big enough to show a section without
    // scrolling, but clamped so it never exceeds (or underflows) the window.
    // The window itself is OS-resizable, so this is how the dialog "resizes".
    final media = MediaQuery.of(context).size;
    final w = (media.width * 0.7).clamp(560.0, media.width - 80);
    final h = (media.height * 0.75).clamp(
      400.0,
      media.height - 100 < 400 ? 400.0 : media.height - 100,
    );
    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      title: const Text('Metadata template'),
      content: SizedBox(
        width: w,
        height: h,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Hint(
              'Tick the fields to stamp onto photos. Unticked fields are left '
              'untouched. Use {year} {date} {name} {camera} variables and '
              '=code= replacements — they expand per photo when applied.',
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 150, child: _navRail()),
                  const VerticalDivider(width: 1, color: AppColors.border),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(
                        left: AppSpacing.lg,
                        right: AppSpacing.md,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: AppSpacing.xs),
                          ..._sectionFor(_tab),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      // The Photo Mechanic stationery-pad trio parks muted on the left (Clear
      // the pad, Load/Save XMP template files — the PM/Bridge interchange
      // format); Cancel/Save keep the right edge and the visual weight.
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DialogUtilityButton(
              label: 'Clear',
              tooltip: 'Empty every field, keyword and table',
              onPressed: _clear,
            ),
            DialogUtilityButton(
              label: 'Load XMP…',
              tooltip: 'Load an XMP template file (Photo Mechanic / Bridge)',
              onPressed: () => unawaited(_loadXmp()),
            ),
            DialogUtilityButton(
              label: 'Save XMP…',
              tooltip: 'Save these values as an XMP template file',
              onPressed: () => unawaited(_saveXmp()),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
      ],
    );
  }

  /// The left-hand list of template sections (scrolls if the dialog is short).
  Widget _navRail() => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final tab in _TemplateTab.values)
          DialogNavItem(
            icon: tab.icon,
            label: tab.label,
            selected: tab == _tab,
            onSelected: () => setState(() => _tab = tab),
          ),
      ],
    ),
  );
}

/// The sections of the metadata-template editor, shown in the left nav-rail.
enum _TemplateTab {
  content('Content', Icons.subject),
  location('Location', Icons.place_outlined),
  rights('Rights', Icons.copyright_outlined),
  status('Status', Icons.assignment_outlined),
  ai('AI', Icons.auto_awesome_outlined),
  tables('Tables', Icons.table_rows_outlined),
  keywords('Keywords', Icons.tag);

  const _TemplateTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(
      text,
      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
    ),
  );
}

/// One template field: an "active" checkbox, the value input, and — for
/// mergeable (free-text) fields — the Replace/Prefix/Append mode picker. Typing
/// ticks the field.
class _TemplateField extends StatelessWidget {
  const _TemplateField({
    required this.field,
    required this.active,
    required this.controller,
    required this.onActiveChanged,
    required this.mode,
    required this.onModeChanged,
    required this.recent,
    required this.onPickRecent,
    super.key,
  });

  final IptcField field;
  final bool active;
  final TextEditingController controller;
  final ValueChanged<bool> onActiveChanged;

  /// The field's Replace/Prefix/Append mode, or null for a non-mergeable field
  /// (bag / controlled code) where only Replace applies.
  final TextApplyMode? mode;
  final ValueChanged<TextApplyMode> onModeChanged;

  /// Previously-stamped values for this field (newest first); the ▼ menu.
  final List<String> recent;

  /// Called with a value the user picked from the ▼ menu.
  final ValueChanged<String> onPickRecent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _ActiveBox(active: active, onChanged: onActiveChanged),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                field.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            if (mode != null)
              _ModeDropdown<TextApplyMode>(
                value: mode!,
                values: TextApplyMode.values,
                labelOf: (m) => m.label,
                onChanged: onModeChanged,
              ),
            if (recent.isNotEmpty)
              _RecentMenu(recent: recent, onPick: onPickRecent),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: controller,
          minLines: field.multiline ? 2 : 1,
          maxLines: field.multiline ? 3 : 1,
          style: const TextStyle(fontSize: 13),
          onChanged: (v) {
            if (v.isNotEmpty && !active) onActiveChanged(true);
          },
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
      ],
    ),
  );
}

/// The ▼ "recent values" menu for a field: picking an entry fills and ticks it.
class _RecentMenu extends StatelessWidget {
  const _RecentMenu({required this.recent, required this.onPick});

  final List<String> recent;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Recent values',
    icon: const Icon(
      Icons.arrow_drop_down,
      size: 20,
      color: AppColors.textSecondary,
    ),
    padding: EdgeInsets.zero,
    splashRadius: 16,
    color: AppColors.surfaceElevated,
    onSelected: onPick,
    itemBuilder: (_) => [
      for (final value in recent)
        PopupMenuItem<String>(
          value: value,
          height: 32,
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
        ),
    ],
  );
}

class _KeywordsField extends StatelessWidget {
  const _KeywordsField({
    required this.active,
    required this.controller,
    required this.mode,
    required this.onActiveChanged,
    required this.onModeChanged,
  });

  final bool active;
  final TextEditingController controller;
  final KeywordApplyMode mode;
  final ValueChanged<bool> onActiveChanged;
  final ValueChanged<KeywordApplyMode> onModeChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          _ActiveBox(active: active, onChanged: onActiveChanged),
          const SizedBox(width: AppSpacing.xs),
          const Text(
            'Keywords',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const Spacer(),
          _ModeDropdown<KeywordApplyMode>(
            value: mode,
            values: KeywordApplyMode.values,
            labelOf: (m) => m.label,
            onChanged: onModeChanged,
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.xs),
      TextField(
        controller: controller,
        style: const TextStyle(fontSize: 13),
        onChanged: (v) {
          if (v.isNotEmpty && !active) onActiveChanged(true);
        },
        decoration: const InputDecoration(
          isDense: true,
          hintText: 'sport, munich, final',
          border: OutlineInputBorder(),
        ),
      ),
    ],
  );
}

/// The per-field "write this" checkbox, kept compact.
class _ActiveBox extends StatelessWidget {
  const _ActiveBox({required this.active, required this.onChanged});

  final bool active;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 20,
    height: 20,
    child: Checkbox(
      value: active,
      onChanged: (v) => onChanged(v ?? false),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    ),
  );
}

/// A compact enum dropdown for the caption / keyword apply modes.
class _ModeDropdown<T> extends StatelessWidget {
  const _ModeDropdown({
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  final T value;
  final List<T> values;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButton<T>(
    value: value,
    isDense: true,
    underline: const SizedBox.shrink(),
    style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
    dropdownColor: AppColors.surfaceElevated,
    items: [
      for (final v in values)
        DropdownMenuItem<T>(value: v, child: Text(labelOf(v))),
    ],
    onChanged: (v) {
      if (v != null) onChanged(v);
    },
  );
}
