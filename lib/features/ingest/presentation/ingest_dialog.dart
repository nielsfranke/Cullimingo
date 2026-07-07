import 'dart:async';

import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/core/files/directory_picker.dart';
import 'package:cullimingo/core/files/supported_files.dart';
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
  bool _includeJpegs = true;
  IngestPlan? _plan;
  // Cached scan of the source, plus the key it was scanned with, so typing a
  // shoot name only re-runs the (instant, pure) buildPlan — no re-scan, no
  // flicker. Re-scan only when source / includeVideos / camera-need changes.
  List<IngestSource>? _sources;
  String? _scannedKey;
  bool _scanning = false;
  // Set when a scan fails, so the dialog shows the reason instead of spinning
  // on "Scanning…" forever.
  String? _scanError;
  // True when the source is a whole drive (not a card) — we don't scan those.
  bool _wholeDrive = false;
  // Capture dates excluded from the plan (empty = every date scanned is
  // included) — lets a card carrying more than one shoot's leftovers be
  // narrowed down before import. Reset on every fresh scan (see `_refresh`).
  final Set<DateTime> _excludedDates = {};

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
          final jpegs = last['includeJpegs'];
          if (jpegs is bool) _includeJpegs = jpegs;
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
        _excludedDates.clear();
      });
      return;
    }
    if (_isWholeDriveRoot(source)) {
      setState(() {
        _sources = null;
        _plan = null;
        _wholeDrive = true;
        _excludedDates.clear();
      });
      return;
    }
    _wholeDrive = false;
    final needsCamera = _template.pattern.contains('{camera}');
    // The scan always includes videos and caches them; the "include videos"
    // toggle just filters the plan (see `_visibleSources`), so flipping it is
    // instant and never re-scans the card. So it's not part of the scan key.
    final key = '$source|$needsCamera';
    if (_sources == null || _scannedKey != key) {
      setState(() {
        _scanning = true;
        _scanError = null;
      });
      final List<IngestSource> sources;
      try {
        // Always scans videos too (scanSources defaults includeVideos: true);
        // the toggle filters the plan, not the scan.
        sources = await scanSources(source, withCamera: needsCamera);
      } on Object catch (e) {
        // Never leave the dialog stuck on "Scanning…": surface the failure and
        // let the user pick another source or retry.
        if (!mounted) return;
        setState(() {
          _scanning = false;
          _scanError = '$e';
        });
        return;
      }
      if (!mounted) return;
      _sources = sources;
      _scannedKey = key;
      // A fresh scan may cover different capture dates than before, so any
      // earlier exclusions no longer mean anything — start unfiltered.
      _excludedDates.clear();
      setState(() => _scanning = false);
    }
    _rebuildPlan();
  }

  /// The cached scan minus videos when "include videos" is off — the set the
  /// plan and the date chips are built from. Filtering here (not in the scan)
  /// keeps the videos toggle instant.
  List<IngestSource> get _visibleSources {
    final sources = _sources;
    if (sources == null) return const [];
    if (_includeVideos && _includeJpegs) return sources;
    return [
      for (final s in sources)
        if ((_includeVideos || !isVideoPath(s.path)) &&
            (_includeJpegs || !isJpegPath(s.path)))
          s,
    ];
  }

  /// Distinct capture dates in the current scan with a photo count each,
  /// oldest first. Empty until a scan completes; a single entry means the
  /// card holds just one day, so there's nothing to narrow down.
  List<MapEntry<DateTime, int>> get _dateCounts =>
      captureDateCounts(_visibleSources);

  void _toggleDate(DateTime day) {
    setState(() {
      if (!_excludedDates.remove(day)) _excludedDates.add(day);
    });
    _rebuildPlan();
  }

  /// Bulk date selection: [included] true = keep every day, false = exclude
  /// every day (so the user can then tap back the one or two they want).
  void _setAllDatesIncluded({required bool included}) {
    setState(() {
      _excludedDates.clear();
      if (!included) {
        _excludedDates.addAll(_dateCounts.map((e) => e.key));
      }
    });
    _rebuildPlan();
  }

  /// Rebuilds the plan from the cached sources, minus videos (when off) and any
  /// excluded capture dates — pure and instant (no I/O, no re-scan).
  void _rebuildPlan() {
    if (_sources == null) return;
    final included = excludeCaptureDates(_visibleSources, _excludedDates);
    setState(() {
      _plan = buildPlan(
        sources: included,
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
          'includeJpegs': _includeJpegs,
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
        if (_dateCounts.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          _dateFilterRow(),
        ],
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
            // Instant: the videos were already scanned, this just re-filters.
            _rebuildPlan();
          },
          label: 'Include video files (copied alongside photos)',
        ),
        DialogCheckbox(
          value: _includeJpegs,
          onChanged: (v) {
            setState(() => _includeJpegs = v ?? true);
            // Instant re-filter of the cached scan (e.g. RAW+JPEG cards).
            _rebuildPlan();
          },
          label: 'Include JPEGs (uncheck to import RAW only)',
        ),
        const SizedBox(height: AppSpacing.lg),
        const DialogSection('Organise'),
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
        // Only shown when the pattern actually uses the Job-name element, so it
        // never sits there confusingly on a "Keep filenames"-style scheme.
        if (_template.pattern.contains('{shoot}')) ...[
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _shoot,
            // Pure, instant rebuild from the cached scan — no re-scan/flicker.
            onChanged: (_) => _rebuildPlan(),
            decoration: dialogInputDecoration(
              'Job name (fills the Job-name element above)',
            ),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          ),
        ],
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

  /// A day-per-chip breakdown of the scan, so a card carrying more than one
  /// shoot's leftovers (an old day mixed in with today's) can be narrowed down
  /// before import — tapping a day excludes/re-includes it. Only shown when
  /// the scan actually found more than one distinct capture date.
  Widget _dateFilterRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'This card has more than one day on it — '
                'tap to include/exclude:',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
            _dateActionButton(
              'Select all',
              () => _setAllDatesIncluded(included: true),
            ),
            _dateActionButton(
              'Clear',
              () => _setAllDatesIncluded(included: false),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final entry in _dateCounts)
              _DateChip(
                label: '${_formatDay(entry.key)} · ${entry.value}',
                selected: !_excludedDates.contains(entry.key),
                onTap: () => _toggleDate(entry.key),
              ),
          ],
        ),
      ],
    );
  }

  /// A compact accent text button for the date-filter bulk actions.
  Widget _dateActionButton(String label, VoidCallback onTap) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      minimumSize: Size.zero,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: AppColors.accent,
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
    child: Text(label),
  );

  static const List<String> _dayMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _formatDay(DateTime d) {
    final date = '${_dayMonths[d.month - 1]} ${d.day}';
    final now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (days == 0) return 'Today · $date';
    if (days == 1) return 'Yesterday · $date';
    return date;
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
    if (_scanError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text(
          "Couldn't scan this source: $_scanError",
          style: const TextStyle(color: AppColors.labelYellow),
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
            // Pop the folder this batch actually landed in (e.g. the dated
            // shoot sub-folder the naming template created), not the whole
            // destination root — falls back to the root when items span more
            // than one sub-folder (e.g. a card spanning several shoot dates).
            onPressed: () {
              final sub = _plan?.commonSubfolder;
              final dest = _dest!;
              Navigator.of(context).pop(sub == null ? dest : p.join(dest, sub));
            },
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

/// A small toggle chip for one capture date in the import dialog's date
/// filter — mirrors the cull grid's filter-bar chip styling (selected =
/// filled accent).
class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.accent : AppColors.surfaceElevated,
    borderRadius: BorderRadius.circular(AppRadius.sm),
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 4,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    ),
  );
}
