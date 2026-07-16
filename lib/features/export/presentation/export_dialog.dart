import 'dart:async';

import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/core/files/directory_picker.dart';
import 'package:cullimingo/core/settings/app_settings.dart';
import 'package:cullimingo/core/vips/vips_encoder.dart';
import 'package:cullimingo/features/delivery/domain/delivery_server.dart';
import 'package:cullimingo/features/export/domain/export_plan.dart';
import 'package:cullimingo/features/export/domain/export_preset.dart';
import 'package:cullimingo/features/naming/domain/name_preset.dart';
import 'package:cullimingo/features/naming/presentation/name_builder.dart';
import 'package:cullimingo/shared/widgets/dialog_kit.dart';
import 'package:flutter/material.dart';

/// A confirmed export, returned by [showExportDialog] when the user presses
/// Export. The actual run happens non-modally outside the dialog (so the grid
/// stays scrollable during a background export, `BUILD_PLAN.md` §6).
class ExportRequest {
  /// Creates a request.
  const ExportRequest({
    required this.plan,
    required this.destinationRoot,
    required this.preset,
    required this.openWhenDone,
    this.nextToOriginals = false,
    this.subfolder = '',
    this.server,
  });

  /// The resolved plan (ordered, named, de-duped).
  final List<ExportItem> plan;

  /// Destination root, including the optional subfolder. Null when
  /// [nextToOriginals] is set (each file goes beside its source), or when
  /// [server] is set and no local copy is kept — then the page renders into
  /// a temp dir it cleans up after the upload (`BUILD_PLAN.md` §11).
  final String? destinationRoot;

  /// Export each file beside its own source instead of into one folder. When
  /// set, [destinationRoot] is null and [subfolder] names the optional
  /// per-source subfolder.
  final bool nextToOriginals;

  /// The subfolder placed beside each source under [nextToOriginals] (e.g.
  /// `Exports`); empty writes directly alongside the originals.
  final String subfolder;

  /// The settings to render with.
  final ExportPreset preset;

  /// Whether to open the destination folder once the run finishes (local
  /// destinations only).
  final bool openWhenDone;

  /// Upload target — the rendered files are delivered here after the render.
  /// Null = plain local export.
  final DeliveryServer? server;
}

/// Long-edge size choices. [_originalSize] keeps the original (no upscale);
/// [_customSize] reveals a free-entry pixel field (Photo-Mechanic's "fit box").
const int _originalSize = 1000000;
const int _customSize = -1;
const List<({String label, int value})> _sizeChoices = [
  (label: '1024 px', value: 1024),
  (label: '2048 px', value: 2048),
  (label: '3072 px', value: 3072),
  (label: '4096 px', value: 4096),
  (label: 'Original', value: _originalSize),
  (label: 'Custom…', value: _customSize),
];

/// Shows the export dialog for [sources] (the current selection or the whole
/// filtered set). Returns the confirmed [ExportRequest] when the user presses
/// Export, or null if they cancel. The caller runs the export non-modally so
/// the grid stays usable during the run (`BUILD_PLAN.md` §6).
Future<ExportRequest?> showExportDialog(
  BuildContext context, {
  required List<ExportSource> sources,
  bool? altFormats,
}) {
  return showDialog<ExportRequest>(
    context: context,
    builder: (_) => _ExportDialog(sources: sources, altFormats: altFormats),
  );
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.sources, this.altFormats});

  final List<ExportSource> sources;

  /// Whether WebP/AVIF are offered; null probes libvips (tests inject).
  final bool? altFormats;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  /// WebP/AVIF need libvips; probing here (UI isolate) also performs the one
  /// thread-sensitive vips_init before any export worker spawns.
  late final bool _altFormats = widget.altFormats ?? VipsEncoder.available;

  ExportPreset _preset = const ExportPreset();

  /// The naming scheme being edited (starts on "Keep filenames").
  NamePreset _naming = NamePreset.builtIns.first;

  /// User-saved naming presets (from settings), shown with the built-ins.
  List<NamePreset> _savedNaming = const [];

  int _sizeValue = 2048;
  String? _destination;

  /// Export beside each source (in [_subfolder]), not into [_destination].
  bool _nextToOriginals = false;
  final TextEditingController _subfolder = TextEditingController(
    text: 'Exports',
  );
  bool _limitSize = false;
  bool _openWhenDone = true;

  /// Configured delivery servers (Settings); empty hides the target dropdown.
  List<DeliveryServer> _servers = const [];

  /// The chosen upload target, or null for a plain local export.
  DeliveryServer? _server;

  /// When uploading: also keep the rendered files in a local folder.
  bool _keepLocalCopy = false;
  final TextEditingController _shoot = TextEditingController();
  final TextEditingController _customEdge = TextEditingController(text: '1800');
  final TextEditingController _maxMb = TextEditingController(text: '2');

  @override
  void initState() {
    super.initState();
    unawaited(
      AppSettings.load().then((s) {
        if (mounted) {
          setState(() {
            _destination = s.lastDestination;
            _servers = [
              for (final raw in s.deliveryServers)
                ?DeliveryServer.fromJson(raw),
            ];
            _savedNaming = [
              for (final raw in s.namePresets) NamePreset.fromJson(raw),
            ];
            _restoreLast(s.lastExport);
          });
        }
      }),
    );
  }

  /// Restores the last-used export settings into the form (called inside the
  /// initState [setState]). Guards every field so a partial/old blob is safe.
  void _restoreLast(Map<String, dynamic>? last) {
    if (last == null) return;
    final naming = last['naming'];
    if (naming is Map) _naming = NamePreset.fromJson(naming.cast());
    final size = last['sizeValue'];
    if (size is num) _sizeValue = size.toInt();
    final customEdge = last['customEdge'];
    if (customEdge is String) _customEdge.text = customEdge;
    final quality = last['quality'];
    if (quality is num) _preset = _preset.copyWith(quality: quality.toInt());
    final sharpen = last['sharpen'];
    if (sharpen is bool) _preset = _preset.copyWith(sharpen: sharpen);
    final format = last['format'];
    if (format is String) {
      final f = ExportFormat.values.where((e) => e.name == format).firstOrNull;
      // Only restore an alt format when libvips is actually available.
      if (f != null && (f == ExportFormat.jpeg || _altFormats)) {
        _preset = _preset.copyWith(format: f);
      }
    }
    final limit = last['limitSize'];
    if (limit is bool) _limitSize = limit;
    final maxMb = last['maxMb'];
    if (maxMb is String) _maxMb.text = maxMb;
    final open = last['openWhenDone'];
    if (open is bool) _openWhenDone = open;
    final nextTo = last['nextToOriginals'];
    if (nextTo is bool) _nextToOriginals = nextTo;
    final subfolder = last['subfolder'];
    if (subfolder is String) _subfolder.text = subfolder;
  }

  /// The current form as a persistable blob for next time.
  Map<String, dynamic> _asLastExport() => {
    'naming': _naming.toJson(),
    'sizeValue': _sizeValue,
    'customEdge': _customEdge.text,
    'quality': _preset.quality,
    'sharpen': _preset.sharpen,
    'format': _preset.format.name,
    'limitSize': _limitSize,
    'maxMb': _maxMb.text,
    'openWhenDone': _openWhenDone,
    'nextToOriginals': _nextToOriginals,
    'subfolder': _subfolder.text,
  };

  @override
  void dispose() {
    _shoot.dispose();
    _customEdge.dispose();
    _maxMb.dispose();
    _subfolder.dispose();
    super.dispose();
  }

  /// Whether the "same folder as originals" mode is offered — local exports
  /// only (an upload always renders into a chosen/temp folder first).
  bool get _nextToOriginalsAvailable => _server == null;

  /// Effective mode after availability: never next-to-originals for uploads.
  bool get _useNextToOriginals => _nextToOriginals && _nextToOriginalsAvailable;

  int get _effectiveLongEdge => _sizeValue == _customSize
      ? (int.tryParse(_customEdge.text.trim()) ?? 2048).clamp(16, 100000)
      : _sizeValue;

  int? get _effectiveMaxBytes {
    if (!_limitSize) return null;
    final mb = double.tryParse(_maxMb.text.trim().replaceAll(',', '.'));
    return (mb == null || mb <= 0) ? null : (mb * 1024 * 1024).round();
  }

  ExportPreset get _effectivePreset => _preset.copyWith(
    longEdge: _effectiveLongEdge,
    shoot: _shoot.text.trim(),
    maxBytes: () => _effectiveMaxBytes,
    template: _naming.toTemplate(),
  );

  /// Persists a new/updated saved naming preset and reflects it locally.
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
      updateSettings(
        (s) => s.setNamePresets([for (final p in _savedNaming) p.toJson()]),
      ),
    );
  }

  /// Deletes a saved naming preset by name.
  void _deleteNaming(String name) {
    setState(() {
      _savedNaming = [
        for (final p in _savedNaming)
          if (p.name != name) p,
      ];
    });
    unawaited(
      updateSettings(
        (s) => s.setNamePresets([for (final p in _savedNaming) p.toJson()]),
      ),
    );
  }

  /// The destination root. Sub-folder structure now comes from the naming
  /// **Folder** row (with tokens), not a separate plain-text field.
  String? _resolvedDestination() => _destination;

  /// The output path of the first photo, as a live preview.
  String get _previewName {
    final plan = buildExportPlan(
      widget.sources,
      _effectivePreset,
      perSourceDir: _useNextToOriginals,
    );
    return plan.isEmpty ? '—' : plan.first.relPath;
  }

  Future<void> _pickDestination() async {
    final dir = await pickDirectory(initialDirectory: _destination);
    if (dir != null && mounted) setState(() => _destination = dir);
  }

  /// Whether the current target/destination combination can be exported.
  bool get _canSubmit => _server != null
      ? (!_keepLocalCopy || _destination != null)
      : (_useNextToOriginals || _destination != null);

  /// Resolves the plan + destination and pops with an [ExportRequest]; the page
  /// runs it non-modally so the grid stays scrollable during the export.
  void _submit() {
    if (!_canSubmit) return;
    final nextTo = _useNextToOriginals;
    // A specific folder is needed unless we're exporting beside the originals.
    final needsFolder = !nextTo && (_server == null || _keepLocalCopy);
    final root = needsFolder ? _resolvedDestination() : null;
    if (needsFolder && root == null) return;
    final preset = _effectivePreset;
    final plan = buildExportPlan(widget.sources, preset, perSourceDir: nextTo);
    final blob = _asLastExport();
    unawaited(
      AppSettings.load().then((s) async {
        if (needsFolder) await s.setLastDestination(_destination!);
        await s.setLastExport(blob);
      }),
    );
    Navigator.of(context).pop(
      ExportRequest(
        plan: plan,
        destinationRoot: root,
        preset: preset,
        openWhenDone: (needsFolder || nextTo) && _openWhenDone,
        nextToOriginals: nextTo,
        subfolder: _subfolder.text.trim(),
        server: _server,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.sources.length;
    return AlertDialog(
      title: Text('Export $count photo${count == 1 ? '' : 's'}'),
      content: SizedBox(
        width: 780,
        child: SingleChildScrollView(child: _form()),
      ),
      actions: _actions(),
    );
  }

  /// The dialog body: two columns of titled cards (Photo-Mechanic style) with a
  /// full-width Output card beneath. Left column groups where the files go and
  /// how they're rendered; the taller Naming card takes the right column.
  Widget _form() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _destinationCard(),
                const SizedBox(height: AppSpacing.lg),
                _sizeQualityCard(),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(child: _namingCard()),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
      _outputCard(),
    ],
  );

  /// The Destination card: upload target or local folder.
  Widget _destinationCard() => DialogCard(
    title: 'Destination',
    children: [
      if (_servers.isNotEmpty) ...[
        DialogDropdown<String>(
          value: _server?.id ?? '',
          onChanged: (id) => setState(
            () => _server = _servers.where((s) => s.id == id).firstOrNull,
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Local folder')),
            for (final server in _servers)
              DropdownMenuItem(
                value: server.id,
                child: Text(
                  'Upload to ${server.name} (${server.protocol.label})',
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      if (_server != null)
        DialogCheckbox(
          value: _keepLocalCopy,
          onChanged: (v) => setState(() => _keepLocalCopy = v ?? false),
          label: 'Also keep a local copy',
        ),
      // Local export: pick between one chosen folder and beside-each-original.
      if (_nextToOriginalsAvailable) ...[
        DialogDropdown<bool>(
          value: _nextToOriginals,
          onChanged: (v) => setState(() => _nextToOriginals = v ?? false),
          items: const [
            DropdownMenuItem(value: false, child: Text('Choose a folder…')),
            DropdownMenuItem(
              value: true,
              child: Text('Same folder as originals'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      if (_useNextToOriginals)
        DialogField(
          label: 'Subfolder',
          child: TextField(
            controller: _subfolder,
            decoration: dialogInputDecoration('Exports (blank = alongside)'),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            onChanged: (_) => setState(() {}),
          ),
        )
      else if (_server == null || _keepLocalCopy)
        DialogPathRow(
          path: _destination,
          onPick: _pickDestination,
          hint: 'Choose a folder…',
        ),
      if (_server == null || _keepLocalCopy)
        DialogCheckbox(
          value: _openWhenDone,
          onChanged: (v) => setState(() => _openWhenDone = v ?? true),
          label: 'Open folder when done',
        ),
    ],
  );

  /// The Size & quality card: long edge, quality, format, and size limits.
  Widget _sizeQualityCard() => DialogCard(
    title: 'Size & quality',
    children: [
      DialogField(
        label: 'Long edge',
        child: Row(
          children: [
            Expanded(
              child: DialogDropdown<int>(
                value: _sizeValue,
                onChanged: (v) => setState(() => _sizeValue = v!),
                items: [
                  for (final s in _sizeChoices)
                    DropdownMenuItem(value: s.value, child: Text(s.label)),
                ],
              ),
            ),
            if (_sizeValue == _customSize) ...[
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 88,
                child: TextField(
                  controller: _customEdge,
                  keyboardType: TextInputType.number,
                  decoration: dialogInputDecoration('px').copyWith(
                    suffixText: 'px',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ],
        ),
      ),
      DialogField(
        label: 'Quality',
        child: Row(
          children: [
            Expanded(
              child: Slider(
                value: _preset.quality.toDouble(),
                min: 50,
                max: 100,
                divisions: 50,
                label: '${_preset.quality}',
                onChanged: (v) => setState(
                  () => _preset = _preset.copyWith(quality: v.round()),
                ),
              ),
            ),
            SizedBox(
              width: 28,
              child: Text(
                '${_preset.quality}',
                style: const TextStyle(color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
      if (_altFormats)
        DialogField(
          label: 'Format',
          child: DialogDropdown<ExportFormat>(
            value: _preset.format,
            onChanged: (f) =>
                setState(() => _preset = _preset.copyWith(format: f)),
            items: [
              for (final f in ExportFormat.values)
                // AVIF needs the vips-heif runtime module; hide it where the
                // probe encode fails (e.g. a bundle without the module).
                if (f != ExportFormat.avif ||
                    (VipsEncoder.instance()?.supportsAvif ?? true))
                  DropdownMenuItem(value: f, child: Text(f.label)),
            ],
          ),
        ),
      DialogCheckbox(
        value: _preset.sharpen,
        onChanged: (v) =>
            setState(() => _preset = _preset.copyWith(sharpen: v ?? false)),
        label: 'Sharpen after resize',
      ),
      DialogCheckbox(
        value: _limitSize,
        onChanged: (v) => setState(() => _limitSize = v ?? false),
        label: 'Limit file size to',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 60,
              child: TextField(
                controller: _maxMb,
                enabled: _limitSize,
                keyboardType: TextInputType.number,
                decoration: dialogInputDecoration('2'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            const Text(
              'MB',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    ],
  );

  /// The Naming card: the pattern builder, which renders the job-name row
  /// inline (right under the preset picker, only while the pattern uses it).
  Widget _namingCard() => DialogCard(
    title: 'Naming',
    children: [
      NameBuilder(
        initial: _naming,
        savedPresets: _savedNaming,
        onChanged: (p) => setState(() => _naming = p),
        onSavePreset: _saveNaming,
        onDeletePreset: _deleteNaming,
        sampleShoot: _shoot.text.trim().isEmpty ? 'Shoot' : _shoot.text.trim(),
        shootController: _shoot,
        onShootChanged: (_) => setState(() {}),
      ),
    ],
  );

  /// The full-width Output card: the live filename preview and a look caveat.
  Widget _outputCard() => DialogCard(
    title: 'Output',
    children: [
      Text(
        'e.g.  $_previewName',
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      ),
      const SizedBox(height: AppSpacing.xs),
      const Text(
        'Embedded-preview export — the in-camera look (great for proofs/web), '
        'not a Capture One / Lightroom render.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
      ),
    ],
  );

  List<Widget> _actions() => [
    TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Cancel'),
    ),
    FilledButton(
      onPressed: _canSubmit ? _submit : null,
      child: Text(
        _server == null
            ? 'Export ${widget.sources.length}'
            : 'Export & upload ${widget.sources.length}',
      ),
    ),
  ];
}
