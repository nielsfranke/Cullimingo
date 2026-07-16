import 'dart:async';

import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/core/cache/memory_budget.dart';
import 'package:cullimingo/core/files/directory_picker.dart';
import 'package:cullimingo/core/logging/app_logger.dart';
import 'package:cullimingo/core/secrets/secret_store.dart';
import 'package:cullimingo/core/settings/app_settings.dart';
import 'package:cullimingo/core/settings/performance_preset.dart';
import 'package:cullimingo/core/version/app_version.g.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/delivery/domain/delivery_server.dart';
import 'package:cullimingo/features/delivery/presentation/delivery_server_dialog.dart';
import 'package:cullimingo/features/handoff/data/cs_credentials.dart';
import 'package:cullimingo/features/handoff/domain/external_editor.dart';
import 'package:cullimingo/features/handoff/presentation/send_to_providers.dart';
import 'package:cullimingo/features/metadata/domain/code_replacements.dart';
import 'package:cullimingo/features/metadata/domain/hot_codes.dart';
import 'package:cullimingo/features/metadata/domain/iptc_template.dart';
import 'package:cullimingo/features/metadata/domain/recent_field_values.dart';
import 'package:cullimingo/features/metadata/domain/template_snapshots.dart';
import 'package:cullimingo/features/metadata/presentation/apply_template.dart';
import 'package:cullimingo/features/metadata/presentation/code_table_dialog.dart';
import 'package:cullimingo/features/metadata/presentation/hot_codes_dialog.dart';
import 'package:cullimingo/features/metadata/presentation/iptc_template_dialog.dart';
import 'package:cullimingo/features/settings/presentation/diagnostics.dart';
import 'package:cullimingo/features/settings/presentation/performance_preset_selector.dart';
import 'package:cullimingo/shared/widgets/dialog_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// The app's central **Settings** screen (`BUILD_PLAN.md` §8): one place for
/// the performance preset, the ContactSheet server credentials, and the
/// thumbnail cache — values that used to live in separate More-menu dialogs.
///
/// Returns the chosen [PerformancePreset] when the preset changed (the page
/// then prompts a restart, since it only applies at next launch), or null
/// otherwise. ContactSheet credentials are persisted on Apply; [onClearCache]
/// is run inline from the Cache section.
Future<PerformancePreset?> showSettingsDialog(
  BuildContext context, {
  required SecretStore secrets,
  required Future<void> Function() onClearCache,
}) async {
  // Load settings BEFORE building the dialog and pass the values in. Loading
  // async inside the dialog (and setState-ing) races the user: a late load can
  // overwrite a toggle they just flipped (this dropped "reopen folders").
  final creds = await loadCsCredentials(secrets);
  final settings = await AppSettings.load();
  final preset =
      PerformancePreset.fromName(settings.performancePresetName) ??
      recommendedPreset(totalBytes: totalPhysicalMemoryBytes());
  if (!context.mounted) return null;
  return showDialog<PerformancePreset>(
    context: context,
    // A form the user fills in over time — don't let a stray outside click
    // silently discard it; require Cancel or Apply.
    barrierDismissible: false,
    builder: (_) => _SettingsDialog(
      onClearCache: onClearCache,
      initialPreset: preset,
      initialBaseUrl: creds.baseUrl,
      initialToken: creds.token,
      initialReopenLastFolders: settings.reopenLastFolders,
      initialCheckForUpdates: settings.checkForUpdatesEnabled,
      initialEditors: [
        for (final raw in settings.sendToEditors) ?ExternalEditor.fromJson(raw),
      ],
      initialServers: [
        for (final raw in settings.deliveryServers)
          ?DeliveryServer.fromJson(raw),
      ],
      initialSnapshots: loadTemplateSnapshots(settings),
      initialRecentValues: settings.recentIptcValues == null
          ? const RecentFieldValues()
          : RecentFieldValues.fromJson(settings.recentIptcValues!),
      initialApplyTemplateOnIngest: settings.applyTemplateOnIngest,
      initialCodes: settings.codeReplacements == null
          ? const CodeReplacements()
          : CodeReplacements.fromJson(settings.codeReplacements!),
      initialHotCodes: settings.hotCodes == null
          ? const HotCodes()
          : HotCodes.fromJson(settings.hotCodes!),
    ),
  );
}

class _SettingsDialog extends ConsumerStatefulWidget {
  const _SettingsDialog({
    required this.onClearCache,
    required this.initialPreset,
    required this.initialBaseUrl,
    required this.initialToken,
    required this.initialReopenLastFolders,
    required this.initialCheckForUpdates,
    required this.initialEditors,
    required this.initialServers,
    required this.initialSnapshots,
    required this.initialRecentValues,
    required this.initialApplyTemplateOnIngest,
    required this.initialCodes,
    required this.initialHotCodes,
  });

  final Future<void> Function() onClearCache;
  final PerformancePreset initialPreset;
  final String initialBaseUrl;
  final String initialToken;
  final bool initialReopenLastFolders;
  final bool initialCheckForUpdates;
  final List<ExternalEditor> initialEditors;
  final List<DeliveryServer> initialServers;
  final TemplateSnapshots initialSnapshots;
  final RecentFieldValues initialRecentValues;
  final bool initialApplyTemplateOnIngest;
  final CodeReplacements initialCodes;
  final HotCodes initialHotCodes;

  @override
  ConsumerState<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<_SettingsDialog> {
  // Read once: RAM-dependent, and the preset applies at startup anyway.
  final int? _totalRam = totalPhysicalMemoryBytes();
  late final TextEditingController _baseUrl = TextEditingController(
    text: widget.initialBaseUrl,
  );
  late final TextEditingController _token = TextEditingController(
    text: widget.initialToken,
  );

  late final PerformancePreset _initialPreset = widget.initialPreset;
  late PerformancePreset _selectedPreset = widget.initialPreset;
  bool _cacheCleared = false;
  late bool _reopenLastFolders = widget.initialReopenLastFolders;
  late bool _checkForUpdates = widget.initialCheckForUpdates;
  late bool _showTooltips = ref.read(tooltipsEnabledProvider);
  late bool _autoAdvanceAfterMark = ref.read(autoAdvanceAfterMarkProvider);
  late bool _propagateMarksToStack = ref.read(propagateMarksToStackProvider);
  late bool _autoExpandBrackets = ref.read(autoExpandBracketsOnSelectProvider);
  late bool _markConfirmation = ref.read(markConfirmationEnabledProvider);
  late bool _autoOpenImportOnCard = ref.read(
    autoOpenImportOnCardInsertProvider,
  );
  late List<ExternalEditor> _editors = [...widget.initialEditors];
  late List<DeliveryServer> _servers = [...widget.initialServers];

  /// Passwords typed in this dialog session (server id → password); flushed
  /// to the secret store on Apply, so Cancel discards them.
  final Map<String, String> _serverPasswords = {};

  /// Servers removed in this session — their secrets are deleted on Apply.
  final List<String> _removedServerIds = [];
  late TemplateSnapshots _snapshots = widget.initialSnapshots;
  late RecentFieldValues _recentValues = widget.initialRecentValues;
  late bool _applyTemplateOnIngest = widget.initialApplyTemplateOnIngest;
  late CodeReplacements _codes = widget.initialCodes;
  late HotCodes _hotCodes = widget.initialHotCodes;

  /// Which settings group the left nav-rail has selected.
  _SettingsTab _tab = _SettingsTab.general;

  @override
  void dispose() {
    _baseUrl.dispose();
    _token.dispose();
    super.dispose();
  }

  void _apply() {
    final preset = _selectedPreset;
    final changed = preset != _initialPreset;
    // Tooltips + auto-advance + mark confirmation apply live (and persist) via
    // their providers.
    ref.read(tooltipsEnabledProvider.notifier).set(_showTooltips);
    ref.read(autoAdvanceAfterMarkProvider.notifier).set(_autoAdvanceAfterMark);
    ref
        .read(propagateMarksToStackProvider.notifier)
        .set(_propagateMarksToStack);
    ref
        .read(autoExpandBracketsOnSelectProvider.notifier)
        .set(_autoExpandBrackets);
    ref.read(markConfirmationEnabledProvider.notifier).set(_markConfirmation);
    ref
        .read(autoOpenImportOnCardInsertProvider.notifier)
        .set(_autoOpenImportOnCard);
    // Persist in the background and pop immediately — the page only needs the
    // result, and a settings save shouldn't block closing the dialog. Capture
    // the field values first since the controllers are disposed on pop.
    unawaited(
      _persist(
        baseUrl: _baseUrl.text.trim(),
        token: _token.text.trim(),
        preset: changed ? preset : null,
        reopenLastFolders: _reopenLastFolders,
        checkForUpdates: _checkForUpdates,
        editors: [for (final e in _editors) e.toJson()],
        servers: [for (final s in _servers) s.toJson()],
        serverPasswords: {..._serverPasswords},
        removedServerIds: [..._removedServerIds],
        secrets: ref.read(secretStoreProvider),
        snapshots: _snapshots.toJson(),
        recentValues: _recentValues.toJson(),
        applyTemplateOnIngest: _applyTemplateOnIngest,
        codes: _codes.toJson(),
        hotCodes: _hotCodes.toJson(),
      ),
    );
    // Refresh the "Send to" menu / ⌘E without a restart.
    ref.invalidate(sendToEditorsProvider);
    Navigator.of(context).pop(changed ? preset : null);
  }

  Future<void> _persist({
    required String baseUrl,
    required String token,
    required bool reopenLastFolders,
    required bool checkForUpdates,
    required List<Map<String, dynamic>> editors,
    required List<Map<String, dynamic>> servers,
    required Map<String, String> serverPasswords,
    required List<String> removedServerIds,
    required SecretStore secrets,
    required Map<String, dynamic> snapshots,
    required Map<String, dynamic> recentValues,
    required bool applyTemplateOnIngest,
    required Map<String, dynamic> codes,
    required Map<String, dynamic> hotCodes,
    PerformancePreset? preset,
  }) async {
    // Runs fire-and-forget after the dialog already popped: one failing write
    // (e.g. a keychain error in saveCsCredentials) must neither skip the
    // remaining, independent writes nor vanish as an unhandled async error —
    // it used to silently drop everything after the throwing step, including
    // the performance preset the page was already showing a restart hint for.
    Future<void> guard(String what, Future<void> Function() write) async {
      try {
        await write();
      } on Object catch (e) {
        appTalker.warning('Settings save failed ($what): $e');
      }
    }

    final settings = await AppSettings.load();
    await guard(
      'ContactSheet credentials',
      () => saveCsCredentials(secrets, baseUrl: baseUrl, token: token),
    );
    await guard(
      'reopen last folders',
      () => settings.setReopenLastFolders(reopenLastFolders),
    );
    await guard(
      'update check',
      () => settings.setCheckForUpdatesEnabled(checkForUpdates),
    );
    await guard('send-to editors', () => settings.setSendToEditors(editors));
    await guard(
      'delivery servers',
      () => settings.setDeliveryServers(servers),
    );
    for (final entry in serverPasswords.entries) {
      await guard(
        'server password',
        () => secrets.write(deliveryPasswordKey(entry.key), entry.value),
      );
    }
    for (final id in removedServerIds) {
      await guard(
        'server password removal',
        () => secrets.delete(deliveryPasswordKey(id)),
      );
    }
    await guard(
      'metadata templates',
      () => settings.setMetadataTemplates(snapshots),
    );
    await guard(
      'recent IPTC values',
      () => settings.setRecentIptcValues(recentValues),
    );
    await guard(
      'apply template on ingest',
      () => settings.setApplyTemplateOnIngest(applyTemplateOnIngest),
    );
    await guard('code replacements', () => settings.setCodeReplacements(codes));
    await guard('hot codes', () => settings.setHotCodes(hotCodes));
    if (preset != null) {
      await guard(
        'performance preset',
        () => settings.setPerformancePresetName(preset.name),
      );
    }
  }

  /// Picks an application and appends it as a "Send to" editor (label derived
  /// from the app/executable name; a duplicate path is ignored).
  Future<void> _addEditor() async {
    final path = await pickApplication();
    if (path == null || !mounted) return;
    if (_editors.any((e) => e.path == path)) return;
    setState(
      () => _editors = [
        ..._editors,
        ExternalEditor(label: p.basenameWithoutExtension(path), path: path),
      ],
    );
  }

  /// Opens the add-server dialog and appends the result.
  Future<void> _addServer() async {
    final edit = await showDeliveryServerDialog(context);
    if (edit == null || !mounted) return;
    setState(() {
      _servers = [..._servers, edit.server];
      _serverPasswords[edit.server.id] = edit.password;
    });
  }

  /// Opens the edit dialog for [server], pre-filled with its stored password.
  Future<void> _editServer(DeliveryServer server) async {
    final password =
        _serverPasswords[server.id] ??
        await ref
            .read(secretStoreProvider)
            .read(deliveryPasswordKey(server.id)) ??
        '';
    if (!mounted) return;
    final edit = await showDeliveryServerDialog(
      context,
      initial: server,
      initialPassword: password,
    );
    if (edit == null || !mounted) return;
    setState(() {
      _servers = [
        for (final s in _servers) s.id == server.id ? edit.server : s,
      ];
      _serverPasswords[server.id] = edit.password;
    });
  }

  /// Removes [server] (dialog-local until Apply, so Cancel is the undo; the
  /// stored password is deleted on Apply too).
  void _removeServer(DeliveryServer server) {
    setState(() {
      _servers = [
        for (final s in _servers)
          if (s.id != server.id) s,
      ];
      _serverPasswords.remove(server.id);
      _removedServerIds.add(server.id);
    });
  }

  Future<void> _clearCache() async {
    await widget.onClearCache();
    if (mounted) setState(() => _cacheCleared = true);
  }

  /// Number of active fields (+1 for keywords) the active snapshot stamps.
  int _templateFieldCount() {
    final template = _snapshots.active;
    return template.fields.length + (template.keywords == null ? 0 : 1);
  }

  /// Edits the active snapshot's template (creating a first snapshot when
  /// none exists yet).
  Future<void> _editTemplate() async {
    final name =
        _snapshots.activeSnapshot?.name ?? TemplateSnapshots.legacyName;
    final edited = await showTemplateEditor(
      context,
      initial: _snapshots.active,
      recent: _recentValues,
    );
    if (edited != null && mounted) {
      setState(() {
        _snapshots = _snapshots.upsert(name, edited);
        _recentValues = _recentValues.recordAll(edited.fields);
      });
    }
  }

  /// Prompts for a name, then sets up a new snapshot in the template editor.
  /// Cancelling either step adds nothing; an existing name is never
  /// overwritten from here.
  Future<void> _addSnapshot() async {
    final name = await promptForName(context, title: 'New template');
    if (name == null || name.isEmpty || !mounted) return;
    if (_snapshots.snapshots.any((s) => s.name == name)) return;
    final edited = await showTemplateEditor(
      context,
      initial: const IptcTemplate(),
      recent: _recentValues,
    );
    if (edited != null && mounted) {
      setState(() {
        _snapshots = _snapshots.upsert(name, edited);
        _recentValues = _recentValues.recordAll(edited.fields);
      });
    }
  }

  /// Renames the active snapshot (no-op on an empty or clashing name).
  Future<void> _renameSnapshot() async {
    final current = _snapshots.activeSnapshot;
    if (current == null) return;
    final name = await promptForName(
      context,
      title: 'Rename template',
      initial: current.name,
    );
    if (name == null || name.isEmpty || name == current.name || !mounted) {
      return;
    }
    if (_snapshots.snapshots.any((s) => s.name == name)) return;
    setState(() => _snapshots = _snapshots.rename(current.name, name));
  }

  /// Removes the active snapshot (dialog-local until Apply, so Cancel is the
  /// undo).
  void _deleteSnapshot() {
    final current = _snapshots.activeSnapshot;
    if (current == null) return;
    setState(() => _snapshots = _snapshots.remove(current.name));
  }

  Future<void> _editCodes() async {
    final edited = await showCodeTableEditor(context, initial: _codes);
    if (edited != null && mounted) setState(() => _codes = edited);
  }

  Future<void> _editHotCodes() async {
    final edited = await showHotCodesEditor(context, initial: _hotCodes);
    if (edited != null && mounted) setState(() => _hotCodes = edited);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
      // A fixed-size body so the nav-rail and Apply/Cancel never jump as you
      // switch groups: a left nav-rail selects the group, the right pane
      // scrolls its sections when a tab outgrows the height.
      content: SizedBox(
        width: 620,
        height: 480,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 150, child: _navRail()),
            const VerticalDivider(width: 1, color: AppColors.border),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(left: AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _sectionFor(_tab),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _apply, child: const Text('Apply')),
      ],
    );
  }

  /// The left-hand list of settings groups.
  Widget _navRail() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final tab in _SettingsTab.values)
        _NavItem(
          tab: tab,
          selected: tab == _tab,
          onSelected: () => setState(() => _tab = tab),
        ),
    ],
  );

  /// The sections shown in the right pane for [tab].
  List<Widget> _sectionFor(_SettingsTab tab) => switch (tab) {
    _SettingsTab.general => _generalSection(),
    _SettingsTab.metadata => _metadataSection(),
    _SettingsTab.delivery => _deliverySection(),
    _SettingsTab.about => _aboutSection(),
  };

  List<Widget> _generalSection() {
    final available = availablePresets(totalBytes: _totalRam);
    final recommended = recommendedPreset(totalBytes: _totalRam);
    return [
      const DialogSection('Performance'),
      PerformancePresetSelector(
        available: available,
        recommended: recommended,
        selected: _selectedPreset,
        totalRamBytes: _totalRam,
        onSelect: (p) => setState(() => _selectedPreset = p),
      ),
      const Text(
        'Applies the next time you start Cullimingo.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
      ),
      const SizedBox(height: AppSpacing.lg),
      const DialogSection('Interface'),
      DialogCheckbox(
        value: _showTooltips,
        onChanged: (v) => setState(() => _showTooltips = v ?? true),
        label: 'Show button tooltips',
      ),
      DialogCheckbox(
        value: _autoAdvanceAfterMark,
        onChanged: (v) => setState(() => _autoAdvanceAfterMark = v ?? false),
        label: 'Auto-advance to the next photo after rating or flagging',
      ),
      DialogCheckbox(
        value: _markConfirmation,
        onChanged: (v) => setState(() => _markConfirmation = v ?? true),
        label: 'Flash a confirmation over the loupe when you mark a photo',
      ),
      const SizedBox(height: AppSpacing.lg),
      const DialogSection('Exposure brackets'),
      DialogCheckbox(
        value: _propagateMarksToStack,
        onChanged: (v) => setState(() => _propagateMarksToStack = v ?? false),
        label: 'Apply ratings, flags and colours to the whole bracket',
      ),
      DialogCheckbox(
        value: _autoExpandBrackets,
        onChanged: (v) => setState(() => _autoExpandBrackets = v ?? false),
        label:
            'Expand pulled-in client picks (Find / ContactSheet) to their '
            'brackets automatically',
      ),
      const SizedBox(height: AppSpacing.lg),
      const DialogSection('Ingest'),
      DialogCheckbox(
        value: _autoOpenImportOnCard,
        onChanged: (v) => setState(() => _autoOpenImportOnCard = v ?? true),
        label: 'Open Import automatically when a memory card is inserted',
      ),
      const SizedBox(height: AppSpacing.lg),
      const DialogSection('Startup'),
      DialogCheckbox(
        value: _reopenLastFolders,
        onChanged: (v) => setState(() => _reopenLastFolders = v ?? false),
        label: 'Reopen last folders on startup',
      ),
      DialogCheckbox(
        value: _checkForUpdates,
        onChanged: (v) => setState(() => _checkForUpdates = v ?? true),
        label: 'Check for updates on startup',
      ),
      const SizedBox(height: AppSpacing.lg),
      const DialogSection('Cache'),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _cacheCleared ? null : _clearCache,
          icon: const Icon(Icons.delete_sweep_outlined, size: 16),
          label: Text(
            _cacheCleared ? 'Thumbnail cache cleared' : 'Clear thumbnail cache',
          ),
        ),
      ),
    ];
  }

  List<Widget> _metadataSection() => [
    const DialogSection('Metadata templates'),
    const Text(
      'Caption, credit, location… to stamp onto photos, saved as '
      'named templates you can switch per customer or assignment. '
      'Use {year}/{name}/{camera}… variables and =code= '
      'replacements; the active template applies with the ⋮ menu, '
      'T, or automatically on ingest.',
      style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
    ),
    const SizedBox(height: AppSpacing.sm),
    Row(
      children: [
        Expanded(
          child: DialogDropdown<String>(
            value: _snapshots.activeSnapshot?.name,
            hint: 'No saved templates',
            items: [
              for (final s in _snapshots.snapshots)
                DropdownMenuItem(value: s.name, child: Text(s.name)),
            ],
            onChanged: (name) {
              if (name != null) {
                setState(() => _snapshots = _snapshots.setActive(name));
              }
            },
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        IconButton(
          iconSize: 16,
          visualDensity: VisualDensity.compact,
          tooltip: 'New template',
          icon: const Icon(Icons.add),
          onPressed: () => unawaited(_addSnapshot()),
        ),
        IconButton(
          iconSize: 16,
          visualDensity: VisualDensity.compact,
          tooltip: 'Rename template',
          icon: const Icon(Icons.drive_file_rename_outline),
          onPressed: _snapshots.isEmpty
              ? null
              : () => unawaited(_renameSnapshot()),
        ),
        IconButton(
          iconSize: 16,
          visualDensity: VisualDensity.compact,
          tooltip: 'Delete template',
          icon: const Icon(Icons.delete_outline),
          onPressed: _snapshots.isEmpty ? null : _deleteSnapshot,
        ),
      ],
    ),
    const SizedBox(height: AppSpacing.sm),
    Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        OutlinedButton.icon(
          onPressed: () => unawaited(_editTemplate()),
          icon: const Icon(Icons.edit_note_outlined, size: 16),
          label: Text(switch (_snapshots.activeSnapshot?.name) {
            null => 'Set up template…',
            final name => 'Edit "$name" (${_templateFieldCount()} fields)…',
          }),
        ),
        OutlinedButton.icon(
          onPressed: () => unawaited(_editCodes()),
          icon: const Icon(Icons.code, size: 16),
          label: Text(
            _codes.isEmpty
                ? 'Code replacements…'
                : 'Code replacements (${_codes.codes.length})…',
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => unawaited(_editHotCodes()),
          icon: const Icon(Icons.bolt_outlined, size: 16),
          label: Text(
            _hotCodes.isEmpty
                ? 'Hot codes…'
                : 'Hot codes (${_hotCodes.codes.length})…',
          ),
        ),
      ],
    ),
    const SizedBox(height: AppSpacing.xs),
    DialogCheckbox(
      value: _applyTemplateOnIngest,
      onChanged: (v) => setState(() => _applyTemplateOnIngest = v ?? false),
      label: 'Apply to photos as they are ingested',
    ),
  ];

  List<Widget> _deliverySection() => [
    const DialogSection('ContactSheet'),
    TextField(
      controller: _baseUrl,
      decoration: dialogInputDecoration('https://contactsheet.example.com'),
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
    ),
    const SizedBox(height: AppSpacing.sm),
    TextField(
      controller: _token,
      obscureText: true,
      decoration: dialogInputDecoration('Access token (cs_pat_…)'),
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
    ),
    const SizedBox(height: AppSpacing.lg),
    const DialogSection('Send to editors'),
    const Text(
      'Hand the selected photos to another app from the right-click '
      'menu; the first editor is ⌘E.',
      style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
    ),
    const SizedBox(height: AppSpacing.sm),
    for (final editor in _editors)
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Row(
          children: [
            Expanded(
              child: Text(
                editor.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                ),
              ),
            ),
            IconButton(
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              tooltip: 'Remove',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(
                () => _editors = [
                  for (final e in _editors)
                    if (e != editor) e,
                ],
              ),
            ),
          ],
        ),
      ),
    Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: () => unawaited(_addEditor()),
        icon: const Icon(Icons.add, size: 16),
        label: const Text('Add editor…'),
      ),
    ),
    const SizedBox(height: AppSpacing.lg),
    const DialogSection('Delivery servers'),
    const Text(
      'FTP/FTPS/SFTP destinations the export dialog can upload to '
      '(wire/agency delivery). Passwords are stored in the system '
      'keychain, not in the settings file.',
      style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
    ),
    const SizedBox(height: AppSpacing.sm),
    for (final server in _servers)
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${server.name} — ${server.protocol.label} · '
                '${server.host}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                ),
              ),
            ),
            IconButton(
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              tooltip: 'Edit server',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => unawaited(_editServer(server)),
            ),
            IconButton(
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              tooltip: 'Remove server',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => _removeServer(server),
            ),
          ],
        ),
      ),
    Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: () => unawaited(_addServer()),
        icon: const Icon(Icons.add, size: 16),
        label: const Text('Add server…'),
      ),
    ),
  ];

  List<Widget> _aboutSection() => [
    const DialogSection('About'),
    const Text(
      'Cullimingo · Version $kAppVersion',
      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
    ),
    const SizedBox(height: AppSpacing.md),
    Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        OutlinedButton.icon(
          onPressed: () => showLogViewer(context),
          icon: const Icon(Icons.article_outlined, size: 16),
          label: const Text('View logs'),
        ),
        OutlinedButton.icon(
          onPressed: () => showAboutCullimingo(context),
          icon: const Icon(Icons.info_outline, size: 16),
          label: const Text('About & licenses'),
        ),
      ],
    ),
  ];
}

/// The settings groups shown in the dialog's left nav-rail.
enum _SettingsTab {
  general('General', Icons.tune),
  metadata('Metadata', Icons.sell_outlined),
  delivery('Delivery', Icons.cloud_upload_outlined),
  about('About', Icons.info_outline);

  const _SettingsTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// One selectable row in the settings nav-rail.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.selected,
    required this.onSelected,
  });

  final _SettingsTab tab;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.textPrimary : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: selected ? AppColors.surfaceElevated : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          onTap: onSelected,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(tab.icon, size: 16, color: color),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  tab.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
