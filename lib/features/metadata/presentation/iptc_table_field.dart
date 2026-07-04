import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/shared/widgets/dialog_kit.dart';
import 'package:flutter/material.dart';

/// A compact, add/remove-row editor for a repeatable structured IPTC table
/// (locations shown, artwork, image creators, copyright owners, licensors,
/// registry entries). Owns a [TextEditingController] per cell and reports the
/// current string matrix through [onChanged] on each edit. Shared by the
/// metadata-template editor and the per-photo IPTC (M) editor.
class IptcTableField extends StatefulWidget {
  /// Creates a table editor titled [title] with the given [columns], seeded
  /// from [rows] (each a cell list matching [columns] length).
  const IptcTableField({
    required this.title,
    required this.columns,
    required this.rows,
    required this.onChanged,
    super.key,
  });

  /// The section title shown above the table.
  final String title;

  /// Column headers (also the cell count per row).
  final List<String> columns;

  /// The seed rows (each a cell list matching [columns] length).
  final List<List<String>> rows;

  /// Reports the current matrix after any add/remove/edit.
  final ValueChanged<List<List<String>>> onChanged;

  @override
  State<IptcTableField> createState() => _IptcTableFieldState();
}

class _IptcTableFieldState extends State<IptcTableField> {
  late final List<List<TextEditingController>> _rows = [
    for (final row in widget.rows)
      [for (final cell in row) TextEditingController(text: cell)],
  ];

  @override
  void dispose() {
    for (final row in _rows) {
      for (final c in row) {
        c.dispose();
      }
    }
    super.dispose();
  }

  void _emit() => widget.onChanged([
    for (final row in _rows) [for (final c in row) c.text],
  ]);

  void _addRow() {
    setState(
      () => _rows.add([
        for (var i = 0; i < widget.columns.length; i++) TextEditingController(),
      ]),
    );
    _emit();
  }

  void _removeRow(int index) {
    for (final c in _rows[index]) {
      c.dispose();
    }
    setState(() => _rows.removeAt(index));
    _emit();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DialogSection(widget.title),
        if (_rows.isNotEmpty)
          Row(
            children: [
              for (final col in widget.columns)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.xs,
                      bottom: AppSpacing.xs,
                    ),
                    child: Text(
                      col,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 32),
            ],
          ),
        for (var i = 0; i < _rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: [
                for (final c in _rows[i])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: TextField(
                        controller: c,
                        style: const TextStyle(fontSize: 13),
                        onChanged: (_) => _emit(),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.sm,
                          ),
                        ),
                      ),
                    ),
                  ),
                SizedBox(
                  width: 32,
                  child: IconButton(
                    tooltip: 'Remove row',
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.remove_circle_outline,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => _removeRow(i),
                  ),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addRow,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add row'),
          ),
        ),
      ],
    ),
  );
}
