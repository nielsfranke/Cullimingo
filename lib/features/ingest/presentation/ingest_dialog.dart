import 'dart:async';

import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/core/files/directory_picker.dart';
import 'package:cullimingo/core/settings/app_settings.dart';
import 'package:cullimingo/features/ingest/data/ingest_service.dart';
import 'package:cullimingo/features/ingest/data/verified_copy.dart';
import 'package:cullimingo/features/ingest/data/volume_detector.dart';
import 'package:cullimingo/features/ingest/domain/rename_template.dart';
import 'package:cullimingo/features/naming/domain/name_preset.dart';
import 'package:cullimingo/features/naming/presentation/name_builder.dart';
import 'package:cullimingo/shared/widgets/dialog_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// The Phase 3 ingest dialog (`BUILD_PLAN.md` §5): pick a source card and one
/// or two destinations, choose a rename template, preview the resulting paths,
/// then run a verified copy with live progress. Pops the primary destination
/// root on success so the caller can open it in the grid.
class IngestDialog extends ConsumerStatefulWidget {
  /// Creates the ingest dialog. [initialSource] preselects a source (e.g. a
  /// just-inserted card); [volumeSearchRoots] overrides volume discovery for
  /// tests.
  const IngestDialog({this.initialSource, this.volumeSearchRoots, super.key});

  /// Source path to preselect, if any.
  final String? initialSource;

  /// Override for [listVolumes] search roots (tests).
  final List<String>? volumeSearchRoots;

  @override
  ConsumerState<IngestDialog> createState() => _IngestDialogState();
}

class _IngestDialogState extends ConsumerState<IngestDialog> {
  final TextEditingController _shoot = TextEditingController();

  /// The naming scheme being edited (starts on the dated-shoot preset).
  NamePreset _naming = NamePreset.builtIns[1];

  /// User-saved naming presets (from settings), shown with the built-ins.
  List<NamePreset> _savedNaming = const [];

  List<Volume> _volumes = const [];
  String? _source;
  String? _dest;
  String? _dest2;
  bool _backup = false;
  bool _verify = true;
  bool _includeVideos = true;
  IngestPlan? _plan;
  // Cached scan of the source, plus the key it was scanned with, so typing a
  // shoot name only re-runs the (instant, pure) buildPlan — no re-scan, no
  // flicker. Re-scan only when source / includeVideos / camera-need changes.
  List<IngestSource>? _sources;
  String? _scannedKey;
  bool _scanning = false;
  // True when the source is a whole drive (not a card) — we don't scan those.
  bool _wholeDrive = false;

  bool _running = false;
  bool _cancelled = false;
  IngestProgress? _progress;
  IngestSummary? _summary;
  final Stopwatch _stopwatch = Stopwatch();

  RenameTemplate get _template => _naming.toTemplate();

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
      AppSettings.load().then(
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
      AppSettings.load().then(
        (s) => s.setNamePresets([for (final p in _savedNaming) p.toJson()]),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _source = widget.initialSource;
    unawaited(_init());
  }

  @override
  void dispose() {
    _shoot.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    // Pre-fill the last-used destination so it's remembered next time.
    final settings = await AppSettings.load();
    if (mounted) {
      setState(() {
        if (_dest == null && settings.lastDestination != null) {
          _dest = settings.lastDestination;
        }
        _savedNaming = [
          for (final raw in settings.namePresets) NamePreset.fromJson(raw),
        ];
        final last = settings.lastImport;
        if (last != null) {
          final naming = last['naming'];
          if (naming is Map) _naming = NamePreset.fromJson(naming.cast());
          final verify = last['verify'];
          if (verify is bool) _verify = verify;
          final videos = last['includeVideos'];
          if (videos is bool) _includeVideos = videos;
        }
      });
    }
    await _loadVolumes();
  }

  Future<void> _loadVolumes() async {
    final vols = await listVolumes(searchRoots: widget.volumeSearchRoots);
    if (!mounted) return;
    setState(() {
      _volumes = vols;
      // Auto-select a likely camera card as the source.
      _source ??= vols.where((v) => v.hasDcim).map((v) => v.path).firstOrNull;
    });
    await _refresh();
  }

  /// Scans the source only when needed (source/videos/camera-need changed),
  /// then rebuilds the plan. Cheap calls (shoot/template tweaks) skip the scan.
  // A whole-drive root in the volume list that isn't a camera card — scanning
  // an entire disk (e.g. an external drive) is never wanted and can OOM.
  bool _isWholeDriveRoot(String path) =>
      _volumes.any((v) => v.path == path && !v.hasDcim);

  Future<void> _refresh() async {
    final source = _source;
    if (source == null) {
      setState(() {
        _sources = null;
        _plan = null;
        _wholeDrive = false;
      });
      return;
    }
    if (_isWholeDriveRoot(source)) {
      setState(() {
        _sources = null;
        _plan = null;
        _wholeDrive = true;
      });
      return;
    }
    _wholeDrive = false;
    final needsCamera = _template.pattern.contains('{camera}');
    final key = '$source|$_includeVideos|$needsCamera';
    if (_sources == null || _scannedKey != key) {
      setState(() => _scanning = true);
      final sources = await scanSources(
        source,
        includeVideos: _includeVideos,
        withCamera: needsCamera,
      );
      if (!mounted) return;
      _sources = sources;
      _scannedKey = key;
      setState(() => _scanning = false);
    }
    _rebuildPlan();
  }

  /// Rebuilds the plan from the cached sources — pure and instant (no I/O).
  void _rebuildPlan() {
    final sources = _sources;
    if (sources == null) return;
    setState(() {
      _plan = buildPlan(
        sources: sources,
        template: _template,
        shoot: _shoot.text.trim(),
      );
    });
  }

  Future<void> _pickSource() async {
    final dir = await pickDirectory(initialDirectory: _source);
    if (dir == null) return;
    setState(() => _source = dir);
    await _refresh();
  }

  Future<void> _pickDest({required bool backup}) async {
    final dir = await pickDirectory(initialDirectory: backup ? _dest2 : _dest);
    if (dir == null) return;
    setState(() => backup ? _dest2 = dir : _dest = dir);
  }

  bool get _canRun =>
      !_running &&
      _source != null &&
      _dest != null &&
      (!_backup || _dest2 != null) &&
      (_plan?.items.isNotEmpty ?? false);

  Future<void> _run() async {
    final plan = _plan;
    final dest = _dest;
    if (plan == null || dest == null) return;
    // Remember this run's naming + options for the next import.
    unawaited(
      AppSettings.load().then(
        (s) => s.setLastImport({
          'naming': _naming.toJson(),
          'verify': _verify,
          'includeVideos': _includeVideos,
        }),
      ),
    );
    setState(() {
      _running = true;
      _cancelled = false;
      _summary = null;
      _progress = null;
    });
    _stopwatch
      ..reset()
      ..start();
    final roots = [dest, if (_backup && _dest2 != null) _dest2!];
    final results = <CopyResult>[];
    await for (final tick in runIngest(
      plan: plan,
      destinationRoots: roots,
      verify: _verify,
    )) {
      results.add(tick.last);
      if (!mounted) return;
      setState(() => _progress = tick);
      // Stop between files (each copy is atomic + verified, so this is safe).
      if (_cancelled) break;
    }
    _stopwatch.stop();
    if (!mounted) return;
    setState(() {
      _summary = IngestSummary(results);
      _running = false;
    });
    // Remember the destination so it's pre-filled next time.
    unawaited(AppSettings.load().then((s) => s.setLastDestination(dest)));
  }

  void _cancel() => setState(() => _cancelled = true);

  @override
  Widget build(BuildContext context) {
    // Cap to the window so the dialog never gets clipped; content scrolls.
    final maxHeight = MediaQuery.of(context).size.height * 0.9;
    return Dialog(
      backgroundColor: AppColors.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 640, maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Import photos',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Flexible(
                child: SingleChildScrollView(
                  child: _summary != null ? _summaryView() : _form(),
                ),
              ),
              // Progress lives outside the scroll area so it's always visible.
              if (_running) ...[
                const SizedBox(height: AppSpacing.md),
                _progressView(),
              ],
              const SizedBox(height: AppSpacing.lg),
              _actions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DialogSection('Source'),
        Row(
          children: [
            Expanded(child: _sourceDropdown()),
            const SizedBox(width: AppSpacing.sm),
            OutlinedButton(
              onPressed: _pickSource,
              child: const Text('Browse…'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const DialogSection('Destination'),
        DialogPathRow(
          path: _dest,
          onPick: () => _pickDest(backup: false),
          hint: 'Choose destination…',
        ),
        DialogCheckbox(
          value: _backup,
          onChanged: (v) => setState(() => _backup = v ?? false),
          label: 'Also copy to a backup destination (verified, one pass)',
        ),
        if (_backup)
          DialogPathRow(
            path: _dest2,
            onPick: () => _pickDest(backup: true),
            hint: 'Choose backup…',
          ),
        DialogCheckbox(
          value: _includeVideos,
          onChanged: (v) {
            setState(() => _includeVideos = v ?? true);
            unawaited(_refresh());
          },
          label: 'Include video files (copied alongside photos)',
        ),
        const SizedBox(height: AppSpacing.lg),
        const DialogSection('Organise'),
        TextField(
          controller: _shoot,
          // Pure, instant rebuild from the cached scan — no re-scan/flicker.
          onChanged: (_) => _rebuildPlan(),
          decoration: dialogInputDecoration('Job name (the Job-name element)'),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
        ),
        const SizedBox(height: AppSpacing.sm),
        NameBuilder(
          initial: _naming,
          savedPresets: _savedNaming,
          onChanged: (p) {
            setState(() => _naming = p);
            // Changing the pattern can add/remove {camera}, which drives whether
            // the scan must read EXIF — so re-run the (cached) refresh.
            unawaited(_refresh());
          },
          onSavePreset: _saveNaming,
          onDeletePreset: _deleteNaming,
          sampleShoot: _shoot.text.trim().isEmpty
              ? 'Shoot'
              : _shoot.text.trim(),
        ),
        const SizedBox(height: AppSpacing.sm),
        DialogCheckbox(
          value: _verify,
          onChanged: (v) => setState(() => _verify = v ?? true),
          label: 'Verify each copy by checksum (recommended)',
        ),
        const SizedBox(height: AppSpacing.lg),
        const DialogSection('Preview'),
        _preview(),
      ],
    );
  }

  Widget _sourceDropdown() {
    final items = [
      for (final v in _volumes)
        DropdownMenuItem(
          value: v.path,
          child: Text(
            v.hasDcim ? '${v.name}  •  card' : v.name,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      if (_source != null && _volumes.every((v) => v.path != _source))
        DropdownMenuItem(value: _source, child: Text(p.basename(_source!))),
    ];
    return DialogDropdown<String>(
      value: _source,
      hint: 'Select a card or folder',
      items: items,
      onChanged: (v) {
        setState(() => _source = v);
        unawaited(_refresh());
      },
    );
  }

  Widget _preview() {
    if (_wholeDrive) {
      return const Text(
        'That looks like a whole drive. Choose a folder on it with Browse… '
        '(or insert a camera card) to scan.',
        style: TextStyle(color: AppColors.textSecondary),
      );
    }
    if (_scanning) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppSpacing.sm),
            Text(
              'Scanning…',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }
    final plan = _plan;
    if (plan == null || plan.items.isEmpty) {
      return const Text(
        'No photos found in the source.',
        style: TextStyle(color: AppColors.textSecondary),
      );
    }
    final sample = plan.items.take(6).toList();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.bgBase,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${plan.items.length} photos · ${_formatBytes(plan.totalBytes)}',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final item in sample)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(
                '${p.basename(item.source)}  →  ${item.relPath}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          if (plan.items.length > sample.length)
            Text(
              '…and ${plan.items.length - sample.length} more',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  Widget _progressView() {
    final pr = _progress;
    final value = (pr == null || pr.total == 0) ? null : pr.done / pr.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(value: value),
        const SizedBox(height: AppSpacing.xs),
        Text(
          pr == null
              ? 'Starting…'
              : 'Copying ${pr.done} / ${pr.total}  ·  ${_speed(pr)}  —  '
                    '${p.basename(pr.last.source)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  String _speed(IngestProgress pr) {
    final ms = _stopwatch.elapsedMilliseconds;
    if (ms <= 0 || pr.bytesDone <= 0) return '…';
    final mbPerSec = pr.bytesDone / 1e6 / (ms / 1000);
    return '${mbPerSec.toStringAsFixed(0)} MB/s';
  }

  Widget _summaryView() {
    final s = _summary!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              s.allOk ? Icons.check_circle : Icons.warning_amber_rounded,
              color: s.allOk ? AppColors.selection : AppColors.labelYellow,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              s.allOk ? 'Import complete' : 'Import finished with issues',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _statRow('Copied & verified', s.copied),
        _statRow('Already present (skipped)', s.skipped),
        if (s.conflicts > 0) _statRow('Conflicts (kept existing)', s.conflicts),
        if (s.failed > 0) _statRow('Failed', s.failed),
        if (s.conflicts > 0 || s.failed > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          for (final r in s.results.where((r) => !r.ok).take(8))
            Text(
              '• ${p.basename(r.source)}: ${r.message ?? r.outcome.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
        ],
      ],
    );
  }

  Widget _statRow(String label, int n) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        Text(
          '$n',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _actions() {
    if (_summary != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FilledButton(
            // Pop the destination so the grid opens the ingested folder.
            onPressed: () => Navigator.of(context).pop(_dest),
            child: const Text('Open in library'),
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          // During a run, Cancel stops after the current file; otherwise it
          // closes the dialog.
          onPressed: _running
              ? (_cancelled ? null : _cancel)
              : () => Navigator.of(context).pop(),
          child: Text(_cancelled ? 'Cancelling…' : 'Cancel'),
        ),
        const SizedBox(width: AppSpacing.sm),
        FilledButton(
          onPressed: _canRun ? _run : null,
          child: Text(_running ? 'Importing…' : 'Import'),
        ),
      ],
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var size = bytes / 1024;
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size >= 10 ? 0 : 1)} ${units[unit]}';
  }
}
