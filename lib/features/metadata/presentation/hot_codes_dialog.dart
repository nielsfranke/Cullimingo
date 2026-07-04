import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/features/metadata/domain/hot_codes.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:flutter/material.dart';

/// Opens the hot-code table editor seeded from [initial]; returns the edited
/// table or null if cancelled.
Future<HotCodes?> showHotCodesEditor(
  BuildContext context, {
  required HotCodes initial,
}) => showDialog<HotCodes>(
  context: context,
  // A form — an outside click must not discard the codes being edited.
  barrierDismissible: false,
  builder: (_) => HotCodesDialog(initial: initial),
);

/// One field row of a hot code being edited: which IPTC field, what value.
class _FieldRow {
  _FieldRow(this.field, String value)
    : value = TextEditingController(text: value);

  IptcField field;
  final TextEditingController value;

  void dispose() => value.dispose();
}

/// One hot code being edited: its name plus the fields it stamps.
class _CodeEntry {
  _CodeEntry(String name, Map<IptcField, String> fields)
    : name = TextEditingController(text: name),
      rows = [for (final e in fields.entries) _FieldRow(e.key, e.value)];

  final TextEditingController name;
  final List<_FieldRow> rows;

  void dispose() {
    name.dispose();
    for (final row in rows) {
      row.dispose();
    }
  }
}

/// The hot-code table editor: each code names a set of IPTC fields it stamps
/// when its `=code=` is typed in the Metadata editor — one keystroke fills a
/// whole venue/customer block. Values may use `=text codes=` and
/// `{variables}`.
class HotCodesDialog extends StatefulWidget {
  /// Creates the editor over an [initial] table.
  const HotCodesDialog({required this.initial, super.key});

  /// The table to seed the form from.
  final HotCodes initial;

  @override
  State<HotCodesDialog> createState() => _HotCodesDialogState();
}

class _HotCodesDialogState extends State<HotCodesDialog> {
  late final List<_CodeEntry> _entries = [
    for (final e in widget.initial.codes.entries) _CodeEntry(e.key, e.value),
  ];

  @override
  void initState() {
    super.initState();
    if (_entries.isEmpty) _addCode();
  }

  @override
  void dispose() {
    for (final entry in _entries) {
      entry.dispose();
    }
    super.dispose();
  }

  void _addCode() => setState(
    () => _entries.add(_CodeEntry('', {IptcField.city: ''})),
  );

  void _removeCode(int index) {
    setState(() => _entries.removeAt(index).dispose());
  }

  void _addField(_CodeEntry entry) {
    // Prefill with the first field the code doesn't set yet.
    final used = {for (final row in entry.rows) row.field};
    final next = IptcField.values.firstWhere(
      (f) => !used.contains(f),
      orElse: () => IptcField.caption,
    );
    setState(() => entry.rows.add(_FieldRow(next, '')));
  }

  void _removeField(_CodeEntry entry, int index) {
    setState(() => entry.rows.removeAt(index).dispose());
  }

  HotCodes _build() {
    final codes = <String, Map<IptcField, String>>{};
    for (final entry in _entries) {
      final name = entry.name.text.trim();
      if (name.isEmpty) continue;
      final fields = <IptcField, String>{
        for (final row in entry.rows)
          if (row.value.text.trim().isNotEmpty) row.field: row.value.text,
      };
      if (fields.isNotEmpty) codes[name] = fields;
    }
    return HotCodes(codes: codes);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: AppColors.surfaceElevated,
    title: const Text('Hot codes'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'A hot code fills several metadata fields at once: type its '
              '=code= in any Metadata-editor field and every field below is '
              'stamped (the field you typed in keeps its other text). Values '
              'may use =text codes= and {variables}. Uses the same delimiter '
              'as the code replacements.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: AppSpacing.md),
            for (var i = 0; i < _entries.length; i++) _codeCard(i),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addCode,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add hot code'),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_build()),
        child: const Text('Save'),
      ),
    ],
  );

  Widget _codeCard(int index) {
    final entry = _entries[index];
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'Code',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: entry.name,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'e.g. arena',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                tooltip: 'Remove hot code',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _removeCode(index),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (var f = 0; f < entry.rows.length; f++) _fieldRow(entry, f),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _addField(entry),
              icon: const Icon(Icons.add, size: 14),
              label: const Text(
                'Add field',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldRow(_CodeEntry entry, int index) {
    final row = entry.rows[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<IptcField>(
              initialValue: row.field,
              isExpanded: true,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                for (final field in IptcField.values)
                  DropdownMenuItem(value: field, child: Text(field.label)),
              ],
              onChanged: (field) {
                if (field != null) setState(() => row.field = field);
              },
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: row.value,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'value',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            tooltip: 'Remove field',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => _removeField(entry, index),
          ),
        ],
      ),
    );
  }
}
