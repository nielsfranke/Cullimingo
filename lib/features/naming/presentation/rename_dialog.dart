import 'dart:async';

import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/core/settings/app_settings.dart';
import 'package:cullimingo/features/ingest/domain/rename_template.dart';
import 'package:cullimingo/features/naming/data/rename_service.dart';
import 'package:cullimingo/features/naming/domain/name_preset.dart';
import 'package:cullimingo/features/naming/presentation/name_builder.dart';
import 'package:cullimingo/shared/widgets/dialog_kit.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// A confirmed rename: the [template] to apply to the selection, plus the
/// [shoot] name feeding the `{shoot}`/Job-name element.
class RenameRequest {
  /// Creates a rename request.
  const RenameRequest({required this.template, required this.shoot});

  /// The filename pattern (folder-less — the files stay in their folder).
  final RenameTemplate template;

  /// Job name for the `{shoot}` token (may be empty).
  final String shoot;
}

/// Shows the in-place rename dialog for [sources] (the current selection). Uses
/// the same token/preset [NameBuilder] as export naming, minus the folder
/// row — a rename keeps every file in place. Returns the [RenameRequest] on
/// Rename, or null on cancel; the caller runs the rename non-modally.
Future<RenameRequest?> showRenameDialog(
  BuildContext context, {
  required List<RenameSource> sources,
}) {
  return showDialog<RenameRequest>(
    context: context,
    builder: (_) => _RenameDialog(sources: sources),
  );
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.sources});

  final List<RenameSource> sources;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  // Start on a sensible renaming default (not "Keep filenames", which is a
  // no-op for a rename): a dated name + counter.
  NamePreset _naming = NamePreset.builtIns.firstWhere(
    (p) => p.filePattern.contains('{seq'),
    orElse: () => NamePreset.builtIns.first,
  );
  List<NamePreset> _savedNaming = const [];
  final TextEditingController _shoot = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(
      AppSettings.load().then((s) {
        if (mounted) {
          setState(() {
            _savedNaming = [
              for (final raw in s.namePresets) NamePreset.fromJson(raw),
            ];
          });
        }
      }),
    );
  }

  @override
  void dispose() {
    _shoot.dispose();
    super.dispose();
  }

  String get _shootValue => _shoot.text.trim();

  RenameTemplate get _template => _naming.toTemplate();

  void _saveNaming(NamePreset preset) {
    setState(() {
      _savedNaming = [
        for (final p in _savedNaming)
          if (p.name != preset.name) p,
        preset,
      ];
      _naming = preset;
    });
    unawaited(
      AppSettings.load().then(
        (s) => s.setNamePresets([for (final p in _savedNaming) p.toJson()]),
      ),
    );
  }

  void _deleteNaming(String name) {
    setState(() {
      _savedNaming = [
        for (final p in _savedNaming)
          if (p.name != name) p,
      ];
    });
    unawaited(
      AppSettings.load().then(
        (s) => s.setNamePresets([for (final p in _savedNaming) p.toJson()]),
      ),
    );
  }

  /// A few `old → new` preview rows, built by the very planner that does the
  /// rename — so RAW+JPEG pairs share a number here exactly as they will on
  /// disk. Disk collisions (the `_2` suffix) are resolved at apply time; the
  /// preview assumes a clean folder.
  List<({String from, String to})> get _preview => [
    for (final item in planRenames(
      widget.sources,
      template: _template,
      shoot: _shootValue,
      exists: (_) => false,
    ).take(4))
      (from: p.basename(item.source), to: p.basename(item.target)),
  ];

  void _submit() => Navigator.of(
    context,
  ).pop(RenameRequest(template: _template, shoot: _shootValue));

  @override
  Widget build(BuildContext context) {
    final count = widget.sources.length;
    return AlertDialog(
      title: Text('Rename $count photo${count == 1 ? '' : 's'}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              NameBuilder(
                initial: _naming,
                savedPresets: _savedNaming,
                showFolder: false,
                onChanged: (p) => setState(() => _naming = p),
                onSavePreset: _saveNaming,
                onDeletePreset: _deleteNaming,
                sampleShoot: _shootValue.isEmpty ? 'Shoot' : _shootValue,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _shoot,
                decoration: dialogInputDecoration(
                  'Job name (the Job-name element)',
                ),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.lg),
              const DialogSection('Preview'),
              for (final row in _preview)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: row.from,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const TextSpan(
                          text: '  →  ',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        TextSpan(
                          text: row.to,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (widget.sources.length > 4)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    '…and ${widget.sources.length - 4} more',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Renames the files in place (with their .xmp sidecars). '
                'Name clashes get a _2, _3… suffix.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
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
          onPressed: _submit,
          child: Text('Rename ${widget.sources.length}'),
        ),
      ],
    );
  }
}
