import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cullimingo/core/logging/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Tiny JSON-file settings store (no extra dependency) for values that persist
/// across launches (last destination, window bounds, preferences, …).
///
/// Each [load] reads a fresh snapshot, but a setter only ever flushes the keys
/// *it* changed, and all writes are serialized process-wide (read-merge-write).
/// So concurrent `AppSettings.load().then((s) => s.setX())` calls — as when the
/// Settings dialog applies several preferences at once — can't clobber each
/// other's keys.
class AppSettings {
  AppSettings._(this._file, this._data);

  final File? _file;
  final Map<String, dynamic> _data;

  /// Keys this instance has changed and still needs to flush.
  final Set<String> _dirty = {};

  /// Serializes every settings write in the process so two read-merge-write
  /// cycles can't interleave and lose keys.
  static Future<void> _writeQueue = Future<void>.value();

  /// The tail of the process-wide write queue. Widget tests that trigger
  /// saves must drive this to completion before reading the settings file.
  @visibleForTesting
  static Future<void> get pendingWrites => _writeQueue;

  /// Detaches the write queue from any previous test's zone. Dart schedules a
  /// `.then` on an already-completed future as a microtask in the zone the
  /// future *completed in* — for widget tests that's the previous test's dead
  /// FakeAsync zone, where it never runs, wedging every later save. Call this
  /// from `setUp` in any widget-test file whose tests save settings.
  @visibleForTesting
  static void resetWriteQueueForTests() {
    _writeQueue = Future<void>.value();
  }

  /// Loads settings from `<appSupport>/settings.json`. Never throws — returns an
  /// empty store if the file/plugin is unavailable (e.g. in tests). Unreadable
  /// *content* (corrupt JSON) empties the data but keeps the file handle, so
  /// this instance's saves still land (merged with the on-disk state at write
  /// time) instead of silently going nowhere.
  static Future<AppSettings> load() async {
    File? file;
    try {
      final dir = await getApplicationSupportDirectory();
      file = File(p.join(dir.path, 'settings.json'));
      final data = file.existsSync()
          ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
          : <String, dynamic>{};
      return AppSettings._(file, data);
    } on Object {
      return AppSettings._(file, {});
    }
  }

  /// The last destination folder an ingest copied into, if any.
  String? get lastDestination => _data['lastDestination'] as String?;

  /// Remembers [path] as the last ingest destination.
  Future<void> setLastDestination(String path) =>
      _setAll({'lastDestination': path});

  /// The last window size, or `null` if never saved (record kept Flutter-free).
  ({double width, double height})? get windowSize {
    final w = _data['windowWidth'];
    final h = _data['windowHeight'];
    if (w is num && h is num) {
      return (width: w.toDouble(), height: h.toDouble());
    }
    return null;
  }

  /// Remembers the window size so the next launch reopens at the same size.
  Future<void> setWindowSize(double width, double height) =>
      _setAll({'windowWidth': width, 'windowHeight': height});

  /// The last window position (top-left), or `null` if never saved.
  ({double x, double y})? get windowPosition {
    final x = _data['windowX'];
    final y = _data['windowY'];
    if (x is num && y is num) return (x: x.toDouble(), y: y.toDouble());
    return null;
  }

  /// Remembers the window position so the next launch reopens in place.
  Future<void> setWindowPosition(double x, double y) =>
      _setAll({'windowX': x, 'windowY': y});

  /// The ContactSheet base URL (e.g. `https://contactsheet.example.com`), or
  /// null if never set (`BUILD_PLAN.md` §7b).
  String? get contactSheetBaseUrl => _data['csBaseUrl'] as String?;

  /// The ContactSheet `cs_pat_…` token as stored by builds before 2026-07.
  /// **Legacy, read-only**: the token lives in the platform secret store now
  /// (`contactSheetTokenKey`); this getter only feeds the one-time migration
  /// in `cs_credentials.dart`, which then calls
  /// [clearLegacyContactSheetToken].
  String? get contactSheetToken => _data['csToken'] as String?;

  /// Remembers the ContactSheet base URL for next time. The token is **not**
  /// settings material — it goes to the secret store.
  Future<void> setContactSheetBaseUrl(String baseUrl) =>
      _setAll({'csBaseUrl': baseUrl});

  /// Blanks the plaintext token of a pre-secret-store settings file (the key
  /// stays, as `null`) once it has been migrated.
  Future<void> clearLegacyContactSheetToken() => _setAll({'csToken': null});

  /// The last-used ContactSheet dialog settings (size, quality, gallery), or
  /// null when never sent. Reopens the dialog where the user left off.
  Map<String, dynamic>? get lastContactSheet {
    final raw = _data['lastContactSheet'];
    return raw is Map ? raw.cast<String, dynamic>() : null;
  }

  /// Remembers the last-used ContactSheet dialog settings.
  Future<void> setLastContactSheet(Map<String, dynamic> settings) =>
      _setAll({'lastContactSheet': settings});

  /// The configured "Send to" editors as raw persisted maps (`{label, path}`);
  /// empty when none set. The handoff layer parses these into `ExternalEditor`s
  /// (`BUILD_PLAN.md` §7).
  List<Map<String, dynamic>> get sendToEditors =>
      (_data['sendToEditors'] as List<dynamic>?)
          ?.map((e) => (e as Map).cast<String, dynamic>())
          .toList() ??
      const [];

  /// Remembers the "Send to" editor list.
  Future<void> setSendToEditors(List<Map<String, dynamic>> editors) =>
      _setAll({'sendToEditors': editors});

  /// The configured delivery servers (export upload targets) as raw persisted
  /// maps; empty when none set. The delivery layer parses these into
  /// `DeliveryServer`s (`BUILD_PLAN.md` §11). Passwords are **not** in here —
  /// they live in the platform secret store, keyed by server id.
  List<Map<String, dynamic>> get deliveryServers =>
      (_data['deliveryServers'] as List<dynamic>?)
          ?.map((e) => (e as Map).cast<String, dynamic>())
          .toList() ??
      const [];

  /// Remembers the delivery-server list.
  Future<void> setDeliveryServers(List<Map<String, dynamic>> servers) =>
      _setAll({'deliveryServers': servers});

  /// The user-saved naming presets (Capture-One-style filename/folder schemes)
  /// as raw persisted maps; empty when none saved. The naming layer parses
  /// these into `NamePreset`s and merges them after the built-ins.
  List<Map<String, dynamic>> get namePresets =>
      (_data['namePresets'] as List<dynamic>?)
          ?.map((e) => (e as Map).cast<String, dynamic>())
          .toList() ??
      const [];

  /// Remembers the user's saved naming presets.
  Future<void> setNamePresets(List<Map<String, dynamic>> presets) =>
      _setAll({'namePresets': presets});

  /// The last-used Export dialog settings (naming scheme, size, quality, …), or
  /// null when the user has never exported. Reopens the dialog where they left.
  Map<String, dynamic>? get lastExport {
    final raw = _data['lastExport'];
    return raw is Map ? raw.cast<String, dynamic>() : null;
  }

  /// Remembers the last-used Export dialog settings.
  Future<void> setLastExport(Map<String, dynamic> settings) =>
      _setAll({'lastExport': settings});

  /// The last-used Import dialog settings (naming scheme, verify, videos), or
  /// null when the user has never imported.
  Map<String, dynamic>? get lastImport {
    final raw = _data['lastImport'];
    return raw is Map ? raw.cast<String, dynamic>() : null;
  }

  /// Remembers the last-used Import dialog settings.
  Future<void> setLastImport(Map<String, dynamic> settings) =>
      _setAll({'lastImport': settings});

  /// The stored performance preset name (e.g. `balanced`), or null when the
  /// user has never chosen one (then the recommended preset is used).
  String? get performancePresetName => _data['perfPreset'] as String?;

  /// Remembers the chosen performance preset (applied at next launch).
  Future<void> setPerformancePresetName(String name) =>
      _setAll({'perfPreset': name});

  /// Custom cull-shortcut overrides (action name → `LogicalKeyboardKey.keyId`).
  /// Empty when the user hasn't rebound anything (defaults apply).
  Map<String, int> get shortcutOverrides {
    final raw = _data['shortcuts'];
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        if (e.value is num) e.key.toString(): (e.value as num).toInt(),
    };
  }

  /// Remembers the cull-shortcut overrides.
  Future<void> setShortcutOverrides(Map<String, int> overrides) =>
      _setAll({'shortcuts': overrides});

  /// The pre-snapshots single IPTC metadata template as a raw persisted map,
  /// or null. **Legacy, read-only**: kept so an old settings file migrates
  /// into `TemplateSnapshots` (as the "Default" snapshot); new saves go
  /// through [setMetadataTemplates].
  Map<String, dynamic>? get metadataTemplate {
    final raw = _data['metadataTemplate'];
    return raw is Map ? raw.cast<String, dynamic>() : null;
  }

  /// The saved named template snapshots as a raw persisted map, or null when
  /// never saved (then [metadataTemplate] is the migration source). The
  /// metadata layer parses it into a `TemplateSnapshots`
  /// (`BUILD_PLAN.md` Phase 4b / Phase 9 Layer 2).
  Map<String, dynamic>? get metadataTemplates {
    final raw = _data['metadataTemplates'];
    return raw is Map ? raw.cast<String, dynamic>() : null;
  }

  /// Remembers the named template snapshots.
  Future<void> setMetadataTemplates(Map<String, dynamic> snapshots) =>
      _setAll({'metadataTemplates': snapshots});

  /// Whether the saved metadata template is stamped onto photos as they're
  /// ingested (default false).
  bool get applyTemplateOnIngest =>
      _data['applyTemplateOnIngest'] as bool? ?? false;

  /// Sets whether ingest applies the metadata template.
  // ignore: avoid_positional_boolean_parameters — simple flag setter.
  Future<void> setApplyTemplateOnIngest(bool value) =>
      _setAll({'applyTemplateOnIngest': value});

  /// The saved code-replacement table as a raw persisted map, or null when none
  /// is set. The metadata layer parses it into a `CodeReplacements`.
  Map<String, dynamic>? get codeReplacements {
    final raw = _data['codeReplacements'];
    return raw is Map ? raw.cast<String, dynamic>() : null;
  }

  /// Remembers the code-replacement table.
  Future<void> setCodeReplacements(Map<String, dynamic> table) =>
      _setAll({'codeReplacements': table});

  /// The saved hot-code table (one code fills several IPTC fields) as a raw
  /// persisted map, or null when none is set.
  Map<String, dynamic>? get hotCodes {
    final raw = _data['hotCodes'];
    return raw is Map ? raw.cast<String, dynamic>() : null;
  }

  /// Remembers the hot-code table.
  Future<void> setHotCodes(Map<String, dynamic> table) =>
      _setAll({'hotCodes': table});

  /// The per-field recent-values history (the template editor's ▼ menu) as a
  /// raw persisted map, or null when nothing has been stamped yet. The metadata
  /// layer parses it into a `RecentFieldValues`.
  Map<String, dynamic>? get recentIptcValues {
    final raw = _data['recentIptcValues'];
    return raw is Map ? raw.cast<String, dynamic>() : null;
  }

  /// Remembers the per-field recent-values history.
  Future<void> setRecentIptcValues(Map<String, dynamic> values) =>
      _setAll({'recentIptcValues': values});

  /// The saved filter presets as a raw persisted list, or null when none saved.
  /// The filter layer parses each entry into a `FilterPreset`.
  List<dynamic>? get filterPresets {
    final raw = _data['filterPresets'];
    return raw is List ? raw : null;
  }

  /// Remembers the saved filter presets.
  Future<void> setFilterPresets(List<Map<String, dynamic>> presets) =>
      _setAll({'filterPresets': presets});

  /// Whether the first-run keyboard cheat sheet has been shown (default false,
  /// so a real first launch pops it once).
  bool get hasSeenShortcutsHint =>
      _data['hasSeenShortcutsHint'] as bool? ?? false;

  /// Records that the first-run keyboard cheat sheet has been shown.
  // ignore: avoid_positional_boolean_parameters — simple flag setter.
  Future<void> setHasSeenShortcutsHint(bool value) =>
      _setAll({'hasSeenShortcutsHint': value});

  /// Whether the loupe flashes an ephemeral confirmation ("★★★", "Rejected", …)
  /// over the photo when a mark is applied (default true).
  bool get markConfirmationOverlay =>
      _data['markConfirmationOverlay'] as bool? ?? true;

  /// Sets the mark-confirmation-overlay preference.
  // ignore: avoid_positional_boolean_parameters — simple flag setter.
  Future<void> setMarkConfirmationOverlay(bool value) =>
      _setAll({'markConfirmationOverlay': value});

  /// Whether button tooltips are shown (default true).
  bool get showTooltips => _data['showTooltips'] as bool? ?? true;

  /// Sets the show-tooltips preference.
  // ignore: avoid_positional_boolean_parameters — simple flag setter.
  Future<void> setShowTooltips(bool value) => _setAll({'showTooltips': value});

  /// Whether marking (rate/flag/colour) a single photo advances focus to the
  /// next one, Photo-Mechanic style (default false).
  bool get autoAdvanceAfterMark =>
      _data['autoAdvanceAfterMark'] as bool? ?? false;

  /// Sets the auto-advance-after-mark preference.
  // ignore: avoid_positional_boolean_parameters — simple flag setter.
  Future<void> setAutoAdvanceAfterMark(bool value) =>
      _setAll({'autoAdvanceAfterMark': value});

  /// Whether marking (rate/flag/colour/rotate) a photo also applies the mark to
  /// the rest of its exposure bracket (default false).
  bool get propagateMarksToStack =>
      _data['propagateMarksToStack'] as bool? ?? false;

  /// Sets the propagate-marks-to-stack preference.
  // ignore: avoid_positional_boolean_parameters — simple flag setter.
  Future<void> setPropagateMarksToStack(bool value) =>
      _setAll({'propagateMarksToStack': value});

  /// Whether pulling client picks in (Find-by-list / ContactSheet) auto-expands
  /// the selection to each pick's exposure bracket (default false).
  bool get autoExpandBracketsOnSelect =>
      _data['autoExpandBracketsOnSelect'] as bool? ?? false;

  /// Sets the auto-expand-brackets-on-select preference.
  // ignore: avoid_positional_boolean_parameters — simple flag setter.
  Future<void> setAutoExpandBracketsOnSelect(bool value) =>
      _setAll({'autoExpandBracketsOnSelect': value});

  /// Whether to reopen the last session's folders on startup (default false).
  bool get reopenLastFolders => _data['reopenLastFolders'] as bool? ?? false;

  /// Sets the reopen-last-folders preference.
  // ignore: avoid_positional_boolean_parameters — simple flag setter.
  Future<void> setReopenLastFolders(bool value) =>
      _setAll({'reopenLastFolders': value});

  /// The source paths of the folders open last session (tab order), for the
  /// reopen-on-startup feature. Empty when none.
  List<String> get lastFolders =>
      (_data['lastFolders'] as List?)?.cast<String>() ?? const [];

  /// Remembers the currently open folders so the next launch can reopen them.
  Future<void> setLastFolders(List<String> paths) =>
      _setAll({'lastFolders': paths});

  /// The index of the active tab among [lastFolders] last session (0 default).
  int get lastActiveTab => (_data['lastActiveTab'] as num?)?.toInt() ?? 0;

  /// Remembers the open folders and which one was active, in one write.
  Future<void> setLastFoldersWithActive(List<String> paths, int activeIndex) =>
      _setAll({'lastFolders': paths, 'lastActiveTab': activeIndex});

  /// Recently opened folder paths, most-recent-first, for the "Open recent"
  /// menu. Empty until a folder has been opened.
  List<String> get recentFolders =>
      (_data['recentFolders'] as List?)?.cast<String>() ?? const [];

  /// Persists the recent-folders list (the provider caps + dedupes it).
  Future<void> setRecentFolders(List<String> paths) =>
      _setAll({'recentFolders': paths});

  /// Whether the loupe shows the thumbnail filmstrip along its bottom edge
  /// (default true). Toggled from the loupe; persisted.
  bool get filmstripVisible => _data['filmstripVisible'] as bool? ?? true;

  /// Sets the loupe filmstrip visibility.
  // ignore: avoid_positional_boolean_parameters — simple flag setter.
  Future<void> setFilmstripVisible(bool value) =>
      _setAll({'filmstripVisible': value});

  /// Whether the loupe's RGB histogram panel was on when last toggled
  /// (default false). Sticky across photos, loupe sessions and relaunches.
  bool get loupeHistogram => _data['loupeHistogram'] as bool? ?? false;

  /// Sets the loupe histogram-panel stickiness.
  // ignore: avoid_positional_boolean_parameters — simple flag setter.
  Future<void> setLoupeHistogram(bool value) =>
      _setAll({'loupeHistogram': value});

  /// Whether the loupe's clipping-warning overlay was on when last toggled
  /// (default false). Sticky, like [loupeHistogram].
  bool get loupeClipping => _data['loupeClipping'] as bool? ?? false;

  /// Sets the loupe clipping-overlay stickiness.
  // ignore: avoid_positional_boolean_parameters — simple flag setter.
  Future<void> setLoupeClipping(bool value) =>
      _setAll({'loupeClipping': value});

  /// Whether the loupe's focus-peaking overlay was on when last toggled
  /// (default false). Sticky, like [loupeHistogram].
  bool get loupeFocusPeaking => _data['loupeFocusPeaking'] as bool? ?? false;

  /// Sets the loupe focus-peaking stickiness.
  // ignore: avoid_positional_boolean_parameters — simple flag setter.
  Future<void> setLoupeFocusPeaking(bool value) =>
      _setAll({'loupeFocusPeaking': value});

  /// Whether inserting a memory card opens the Import dialog directly instead
  /// of only showing a "card detected" notice (default true).
  bool get autoOpenImportOnCardInsert =>
      _data['autoOpenImportOnCardInsert'] as bool? ?? true;

  /// Sets the auto-open-Import-on-card-insert preference.
  // ignore: avoid_positional_boolean_parameters — simple flag setter.
  Future<void> setAutoOpenImportOnCardInsert(bool value) =>
      _setAll({'autoOpenImportOnCardInsert': value});

  /// The stored "Find similar" sensitivity preset name, or null when never
  /// chosen (then the balanced default is used).
  String? get similaritySensitivity =>
      _data['similaritySensitivity'] as String?;

  /// Remembers the chosen "Find similar" sensitivity preset.
  Future<void> setSimilaritySensitivity(String name) =>
      _setAll({'similaritySensitivity': name});

  /// Whether Cullimingo checks GitHub for a newer release on startup
  /// (default true; opt-out in Settings → General). The check is throttled to
  /// once a day via [lastUpdateCheckAt].
  bool get checkForUpdatesEnabled => _data['checkForUpdates'] as bool? ?? true;

  /// Sets the check-for-updates-on-startup preference.
  // ignore: avoid_positional_boolean_parameters — simple flag setter.
  Future<void> setCheckForUpdatesEnabled(bool value) =>
      _setAll({'checkForUpdates': value});

  /// When the last startup update check ran, or null if it never has. Used to
  /// throttle the check to once a day.
  DateTime? get lastUpdateCheckAt {
    final ms = _data['lastUpdateCheckAt'];
    return ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null;
  }

  /// Records when the startup update check last ran.
  Future<void> setLastUpdateCheckAt(DateTime when) =>
      _setAll({'lastUpdateCheckAt': when.millisecondsSinceEpoch});

  /// The saved grid thumbnail size (cell width in logical px), or null when
  /// never set. Restored globally on next launch.
  double? get gridCellWidth => (_data['gridCellWidth'] as num?)?.toDouble();

  /// Remembers the grid thumbnail size globally.
  Future<void> setGridCellWidth(double width) =>
      _setAll({'gridCellWidth': width});

  /// Applies [values] to the in-memory store, marks them dirty, and flushes.
  Future<void> _setAll(Map<String, Object?> values) {
    _data.addAll(values);
    _dirty.addAll(values.keys);
    return _save();
  }

  Future<void> _save() {
    final file = _file;
    if (file == null) return Future<void>.value();
    // Flush only the keys this instance changed, merged into the latest on-disk
    // state — so a concurrent writer's keys survive.
    final updates = {for (final k in _dirty) k: _data[k]};
    _dirty.clear();
    final next = _writeQueue.then((_) async {
      try {
        Map<String, dynamic> current;
        try {
          current = file.existsSync()
              ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
              : <String, dynamic>{};
        } on Object {
          // Corrupt on-disk JSON: better to rewrite it from this save than to
          // silently drop the save because the merge source won't parse.
          current = {};
        }
        // Write-to-temp + rename, so no reader can ever see a half-written
        // file. A plain writeAsString truncates first — a concurrent load()
        // hitting that window got broken JSON, fell back to a file-less
        // store, and its next save silently went nowhere (verified live
        // 2026-07-03: the ContactSheet dialog's two submit-time saves).
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(
          jsonEncode({...current, ...updates}),
          flush: true,
        );
        tmp.renameSync(file.path);
      } on Object catch (e) {
        // Best effort — a missing setting just means no pre-fill next time.
        // Logged, though: a *persistently* failing write (read-only config
        // dir, full disk) would otherwise be invisible.
        appTalker.warning('Settings write failed: $e');
      }
    });
    _writeQueue = next;
    return next;
  }
}

/// Loads the settings and applies [change] — the one-liner for the very
/// common fire-and-forget UI persistence (`unawaited(updateSettings((s) =>
/// s.setX(...)))`), which used to be spelled `AppSettings.load().then(...)`
/// at every call site.
Future<void> updateSettings(
  FutureOr<void> Function(AppSettings settings) change,
) async => change(await AppSettings.load());
