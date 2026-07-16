import 'dart:async';

import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/settings/app_settings.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/filter/presentation/filter_providers.dart';
import 'package:cullimingo/features/metadata/data/template_file.dart';
import 'package:cullimingo/features/metadata/domain/code_replacements.dart';
import 'package:cullimingo/features/metadata/domain/hot_codes.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/features/metadata/domain/iptc_editor_model.dart';
import 'package:cullimingo/features/metadata/domain/iptc_structured.dart';
import 'package:cullimingo/features/metadata/domain/iptc_template.dart';
import 'package:cullimingo/features/metadata/domain/media_topics.dart';
import 'package:cullimingo/features/metadata/domain/reverse_geocoder.dart';
import 'package:cullimingo/features/metadata/domain/template_expansion.dart';
import 'package:cullimingo/features/metadata/domain/template_snapshots.dart';
import 'package:cullimingo/features/metadata/domain/template_variables.dart';
import 'package:cullimingo/features/metadata/presentation/apply_template.dart';
import 'package:cullimingo/features/metadata/presentation/geocoding_providers.dart';
import 'package:cullimingo/features/metadata/presentation/iptc_clipboard.dart';
import 'package:cullimingo/features/metadata/presentation/iptc_table_field.dart';
import 'package:cullimingo/shared/widgets/dialog_kit.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// Opens the IPTC metadata editor for the current cull target(s): the
/// Space-selection if any, else the focused photo (the same target rule as the
/// keyword editor). One editor serves single and batch — its
/// only-changed-fields semantics ([iptcEditorChanges]) apply your edits to
/// every selected photo while leaving fields you didn't touch alone. A dialog,
/// not an inline panel, so its text fields take focus without fighting the grid
/// cull keys.
///
/// `=code=` replacements expand live while typing (they're photo-independent);
/// `{variables}` expand on save, per photo, so `{date}`/`{seq}` resolve to each
/// photo's own values in a batch.
///
/// Over a single photo the editor runs in **serial-captioning** mode
/// (`BUILD_PLAN.md` Phase 9): it walks the filtered set photo-by-photo,
/// auto-saving edits on navigation (⌘/Ctrl+Enter = save & next) — the Photo
/// Mechanic wire-service pattern. Pairs with the "Needs caption" filter:
/// filter, press `M`, caption straight through.
Future<void> showIptcEditor(BuildContext context, WidgetRef ref) async {
  final photos = ref.read(filteredPhotosProvider);
  if (photos.isEmpty) return;
  final selection = ref.read(cullControllerProvider);
  final targetIds = selection.markTargets.toList();
  if (targetIds.isEmpty) return;

  final byId = {for (final p in photos) p.id: p};
  final targets = <Photo>[
    for (final id in targetIds) ?byId[id],
  ];
  if (targets.isEmpty) return;

  final settings = await AppSettings.load();
  final codes = loadCodeReplacements(settings);
  final hotCodes = settings.hotCodes == null
      ? const HotCodes()
      : HotCodes.fromJson(settings.hotCodes!);
  // Lazy first-time load of the bundled vocabulary (10 KB, parsed off the UI
  // isolate, then kept alive); never blocks the editor on failure.
  var topics = const MediaTopics([]);
  try {
    topics = await ref.read(mediaTopicsProvider.future);
  } on Object {
    // Missing/corrupt asset → the field degrades to plain text.
  }
  if (!context.mounted) return;

  final controller = ref.read(cullControllerProvider.notifier);

  // The saved template snapshots power the editor's Load menu; Save as… writes
  // back through the same settings key the Settings dialog manages.
  final templates = loadTemplateSnapshots(settings);
  Future<void> saveTemplate(String name, IptcTemplate template) async {
    final s = await AppSettings.load();
    await s.setMetadataTemplates(
      loadTemplateSnapshots(s).upsert(name, template).toJson(),
    );
  }

  Future<String?> pickTemplatePath() async {
    const group = XTypeGroup(label: 'XMP templates', extensions: ['xmp']);
    return (await openFile(acceptedTypeGroups: [group]))?.path;
  }

  // Codes are expanded again on save (not just live in the field), so
  // pasted-in text that slipped past the live listener still resolves — both
  // passes are non-destructive.
  Map<IptcField, String> expandFor(
    Photo photo,
    int sequence,
    Map<IptcField, String> changes,
  ) {
    final vars = templateVariables(
      path: photo.path,
      capturedAt: photo.capturedAt,
      camera: photo.camera,
      lens: photo.lens,
      sequence: sequence,
    );
    return {
      for (final e in changes.entries)
        e.key: expandTemplateText(e.value, vars: vars, codes: codes),
    };
  }

  if (targets.length == 1) {
    // Serial mode: walk the whole filtered set, starting at the target.
    final iptcs = [for (final photo in photos) photo.iptc];
    final start = photos
        .indexWhere((photo) => photo.id == targets.single.id)
        .clamp(0, photos.length - 1);
    await showDialog<Map<IptcField, String>>(
      context: context,
      // A form — an outside click must not discard the edits being typed.
      barrierDismissible: false,
      builder: (_) => IptcEditorDialog(
        targets: [iptcs[start]],
        count: 1,
        codes: codes,
        hotCodes: hotCodes,
        topics: topics,
        templates: templates,
        onSaveTemplate: saveTemplate,
        pickTemplatePath: pickTemplatePath,
        serial: SerialCaptioning(
          iptcs: iptcs,
          filenames: [for (final photo in photos) p.basename(photo.path)],
          initialIndex: start,
          onApply: (index, changes, applyTables) async {
            final photo = photos[index];
            final next = applyTables(
              iptcs[index].withOverrides(expandFor(photo, index + 1, changes)),
            );
            iptcs[index] = next;
            await controller.setIptc(photo.id, next);
            return next;
          },
          // Keep the grid oriented: its focus follows the walk.
          onShow: (index) => controller.focus(photos[index].id),
          preview: (index) => _SerialPreview(
            key: ValueKey(photos[index].path),
            path: photos[index].path,
          ),
          hasGps: [
            for (final photo in photos)
              photo.latitude != null && photo.longitude != null,
          ],
          onGeocode: (index) async {
            final photo = photos[index];
            final (lat, lon) = (photo.latitude, photo.longitude);
            if (lat == null || lon == null) return null;
            // Loads the gazetteer lazily on first use (parsed off the UI
            // isolate, then kept alive).
            final geocoder = await ref.read(reverseGeocoderProvider.future);
            return geocoder.lookup(lat, lon);
          },
          captureTimes: [for (final photo in photos) photo.capturedAt],
        ),
      ),
    );
    return;
  }

  final changes = await showDialog<Map<IptcField, String>>(
    context: context,
    // A form — an outside click must not discard the edits being typed.
    barrierDismissible: false,
    builder: (_) => IptcEditorDialog(
      targets: [for (final photo in targets) photo.iptc],
      count: targets.length,
      codes: codes,
      hotCodes: hotCodes,
      topics: topics,
      templates: templates,
      onSaveTemplate: saveTemplate,
      pickTemplatePath: pickTemplatePath,
    ),
  );
  if (changes == null || changes.isEmpty) return;

  for (var i = 0; i < targets.length; i++) {
    final photo = targets[i];
    final expanded = expandFor(photo, i + 1, changes);
    await controller.setIptc(photo.id, photo.iptc.withOverrides(expanded));
  }
}

/// Wiring for the serial-captioning mode (`BUILD_PLAN.md` Phase 9): the editor
/// walks a whole photo list one at a time, auto-saving edits on navigation —
/// the Photo Mechanic pattern for captioning a shoot straight through. All
/// side effects are injected so the dialog stays constructible without
/// providers in tests.
class SerialCaptioning {
  /// Creates the serial wiring over the photos being walked (grid order).
  const SerialCaptioning({
    required this.iptcs,
    required this.filenames,
    required this.initialIndex,
    required this.onApply,
    this.onShow,
    this.preview,
    this.hasGps = const [],
    this.onGeocode,
    this.captureTimes = const [],
  });

  /// Every photo's current IPTC payload, in grid order.
  final List<IptcCore> iptcs;

  /// Display name per photo — the header's orientation cue.
  final List<String> filenames;

  /// EXIF capture time per photo, prefilling the Date Created field when it has
  /// no explicit IPTC value. Empty = unknown.
  final List<DateTime?> captureTimes;

  /// Where the walk starts (the photo the editor was opened on).
  final int initialIndex;

  /// Writes `changes` through to the photo at an index (expanding
  /// codes/variables with that photo's values), then applies `applyTables` (the
  /// structured tables the editor holds) on top, and returns the photo's new
  /// payload — which the editor shows when navigating back to it.
  final Future<IptcCore> Function(
    int index,
    Map<IptcField, String> changes,
    IptcCore Function(IptcCore base) applyTables,
  )
  onApply;

  /// Called when the editor lands on a photo, so the grid can follow.
  final void Function(int index)? onShow;

  /// Builds a small preview of the photo at an index for the header
  /// (null = no preview).
  final Widget Function(int index)? preview;

  /// Whether the photo at an index carries a GPS position (drives the
  /// "From GPS" button). Empty = geocoding unavailable.
  final List<bool> hasGps;

  /// Reverse-geocodes the photo at an index (null = no geocoder wired, or —
  /// at call time — nothing near the position).
  final Future<GeoPlace?> Function(int index)? onGeocode;
}

/// The IPTC editor form. Prefills each field from [targets] (a shared value, or
/// blank + "Mixed" when they disagree) and, on save, pops only the fields whose
/// text changed. Constructed directly with [targets] so it is widget-testable
/// without providers.
class IptcEditorDialog extends StatefulWidget {
  /// Creates the editor over the given targets' current IPTC values.
  const IptcEditorDialog({
    required this.targets,
    required this.count,
    this.codes = const CodeReplacements(),
    this.hotCodes = const HotCodes(),
    this.topics = const MediaTopics([]),
    this.templates = const TemplateSnapshots(),
    this.onSaveTemplate,
    this.pickTemplatePath,
    this.serial,
    super.key,
  });

  /// The current IPTC payload of each target photo.
  final List<IptcCore> targets;

  /// How many photos the edit will apply to (drives the batch banner).
  final int count;

  /// The code-replacement table for live `=code=` expansion while typing
  /// (empty = expansion off).
  final CodeReplacements codes;

  /// The hot-code table: a typed `=code=` fills several fields at once
  /// (empty = off). Shares [codes]' delimiter.
  final HotCodes hotCodes;

  /// The Media Topics vocabulary behind the Subject-codes autocomplete
  /// (empty = plain text field).
  final MediaTopics topics;

  /// The saved metadata templates for the Load menu (empty = no snapshots to
  /// offer). Loading stamps a template onto the current field values, exactly
  /// like ⋮ → Apply — but editable before Save writes anything.
  final TemplateSnapshots templates;

  /// Persists "Save as template…" (null hides the button). Injected so the
  /// dialog stays constructible without settings in tests.
  final Future<void> Function(String name, IptcTemplate template)?
  onSaveTemplate;

  /// Picks the XMP template file for Load → "From XMP file…" (null hides the
  /// entry). Injected so widget tests run without a native dialog.
  final Future<String?> Function()? pickTemplatePath;

  /// Serial-captioning wiring — non-null puts the editor in walk mode with
  /// prev/next navigation that auto-saves. [targets] then supplies the starting
  /// photo's payload; navigation reads [SerialCaptioning.iptcs].
  final SerialCaptioning? serial;

  @override
  State<IptcEditorDialog> createState() => _IptcEditorDialogState();
}

class _IptcEditorDialogState extends State<IptcEditorDialog> {
  late Map<IptcField, IptcFieldInit> _init = iptcEditorInit(
    widget.targets,
  );
  late final Map<IptcField, TextEditingController> _controllers = {
    for (final field in IptcField.values)
      field: TextEditingController(text: _init[field]!.value),
  };

  // Serial mode: the walked photos' payloads (local copy, updated after each
  // apply so navigating back shows what was written) and the current position.
  late final List<IptcCore> _serialIptcs = [...?widget.serial?.iptcs];
  late int _index = widget.serial?.initialIndex ?? 0;

  // The current photo's structured tables as string matrices (like the template
  // editor). Only shown/applied in serial mode; [_tablesDirty] gates whether an
  // otherwise-untouched photo gets rewritten.
  late List<List<String>> _locationsShown;
  late List<List<String>> _artwork;
  late List<List<String>> _imageCreators;
  late List<List<String>> _copyrightOwners;
  late List<List<String>> _licensors;
  late List<List<String>> _registryEntries;
  bool _tablesDirty = false;

  /// Refocused after each navigation so typing continues without a click.
  final FocusNode _captionFocus = FocusNode();

  /// Guards against the listener re-entering while it rewrites the text.
  bool _expanding = false;

  /// The IptcCore whose tables seed the editor (the current serial photo, else
  /// the single target).
  IptcCore get _tablesSource =>
      widget.serial != null && _index < _serialIptcs.length
      ? _serialIptcs[_index]
      : (widget.targets.length == 1 ? widget.targets.first : const IptcCore());

  /// (Re)seeds the table matrices from [c] and clears the dirty flag.
  void _seedTables(IptcCore c) {
    _locationsShown = [
      for (final l in c.locationsShown)
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
      for (final a in c.artwork)
        [a.title, a.creator, a.source, a.copyrightNotice],
    ];
    _imageCreators = [
      for (final e in c.imageCreators) [e.name, e.identifier],
    ];
    _copyrightOwners = [
      for (final e in c.copyrightOwners) [e.name, e.identifier],
    ];
    _licensors = [
      for (final l in c.licensors) [l.name, l.id, l.phone, l.email, l.url],
    ];
    _registryEntries = [
      for (final r in c.registryEntries) [r.itemId, r.organisationId],
    ];
    _tablesDirty = false;
  }

  /// Builds the tables-apply step for the current matrices — replaces the
  /// photo's tables with what the editor now holds (empty clears them).
  IptcCore Function(IptcCore) _tablesApplier() {
    List<String> row(List<String> r, int n) => [
      for (var i = 0; i < n; i++) (i < r.length ? r[i] : '').trim(),
    ];
    final locations = [
      for (final r in _locationsShown)
        (() {
          final c = row(r, 7);
          return IptcLocation(
            sublocation: c[0],
            city: c[1],
            state: c[2],
            country: c[3],
            countryCode: c[4],
            worldRegion: c[5],
            locationId: c[6],
          );
        })(),
    ].where((l) => !l.isEmpty).toList();
    final artwork = [
      for (final r in _artwork)
        IptcArtwork(
          title: row(r, 4)[0],
          creator: row(r, 4)[1],
          source: row(r, 4)[2],
          copyrightNotice: row(r, 4)[3],
        ),
    ].where((a) => !a.isEmpty).toList();
    final creators = [
      for (final r in _imageCreators)
        IptcEntity(name: row(r, 2)[0], identifier: row(r, 2)[1]),
    ].where((e) => !e.isEmpty).toList();
    final owners = [
      for (final r in _copyrightOwners)
        IptcEntity(name: row(r, 2)[0], identifier: row(r, 2)[1]),
    ].where((e) => !e.isEmpty).toList();
    final licensors = [
      for (final r in _licensors)
        IptcLicensor(
          name: row(r, 5)[0],
          id: row(r, 5)[1],
          phone: row(r, 5)[2],
          email: row(r, 5)[3],
          url: row(r, 5)[4],
        ),
    ].where((l) => !l.isEmpty).toList();
    final registry = [
      for (final r in _registryEntries)
        IptcRegistryEntry(itemId: row(r, 2)[0], organisationId: row(r, 2)[1]),
    ].where((r) => !r.isEmpty).toList();
    return (base) => base.withStructured(
      locationsShown: locations,
      artwork: artwork,
      imageCreators: creators,
      copyrightOwners: owners,
      licensors: licensors,
      registryEntries: registry,
    );
  }

  @override
  void initState() {
    super.initState();
    _seedTables(_tablesSource);
    // Photo Mechanic's speed trick: a defined `=code=` expands the moment its
    // closing delimiter is typed. Codes are photo-independent, so live
    // expansion is safe in batch mode too ({variables} are not — they expand
    // per photo on save instead).
    if (!widget.codes.isEmpty || !widget.hotCodes.isEmpty) {
      for (final entry in _controllers.entries) {
        final MapEntry(key: field, value: c) = entry;
        c.addListener(() => _expandCodesIn(field, c));
      }
    }
  }

  void _expandCodesIn(IptcField field, TextEditingController c) {
    if (_expanding) return;
    final text = c.text;
    // Hot codes first: the token vanishes and every field it maps fills in.
    // The typed field keeps its remaining text (its own mapping is skipped so
    // nothing the user wrote gets overwritten). Nested =text codes= in the
    // mapped values expand right here; {variables} wait for save as usual.
    final hot = expandHotCodes(
      text,
      delimiter: widget.codes.delimiter,
      hotCodes: widget.hotCodes,
    );
    var stripped = text;
    if (hot != null) {
      stripped = hot.text;
      _expanding = true;
      for (final e in hot.fields.entries) {
        if (e.key == field) continue;
        _controllers[e.key]!.text = expandCodes(e.value, widget.codes);
      }
      _expanding = false;
    }
    final expanded = expandCodes(stripped, widget.codes);
    if (expanded == text) return;
    _expanding = true;
    // The expansion sits at/before the caret (the closing delimiter was just
    // typed), so shifting by the length delta lands right after the new text.
    final base = c.selection.isValid ? c.selection.baseOffset : text.length;
    c.value = TextEditingValue(
      text: expanded,
      selection: TextSelection.collapsed(
        offset: (base + expanded.length - text.length).clamp(
          0,
          expanded.length,
        ),
      ),
    );
    _expanding = false;
  }

  @override
  void dispose() {
    _captionFocus.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<IptcField, String> _currentText() => {
    for (final field in IptcField.values) field: _controllers[field]!.text,
  };

  /// Photo Mechanic "Copy": snapshot every field into the session clipboard so
  /// it can be stamped onto another photo (here or in a later editor open).
  void _copy() => iptcClipboard.value = _currentText();

  /// Photo Mechanic "Paste": overwrite the fields with the copied snapshot.
  /// Full replace (empty copied fields clear the target), matching PM; Save
  /// then writes through only what actually changed.
  void _paste() {
    final data = iptcClipboard.value;
    if (data == null) return;
    setState(() {
      for (final entry in data.entries) {
        _controllers[entry.key]?.text = entry.value;
      }
    });
  }

  void _save() {
    if (widget.serial != null) {
      unawaited(_saveSerial());
      return;
    }
    Navigator.of(context).pop(iptcEditorChanges(_init, _currentText()));
  }

  /// Serial save: write the current photo's edits through, then close.
  Future<void> _saveSerial() async {
    await _applyCurrent();
    if (mounted) Navigator.of(context).pop(const <IptcField, String>{});
  }

  /// Writes the current photo's changed fields through [SerialCaptioning
  /// .onApply] (a no-op when nothing changed) and records the new payload.
  Future<void> _applyCurrent() async {
    final changes = iptcEditorChanges(_init, _currentText());
    if (changes.isEmpty && !_tablesDirty) return;
    final updated = await widget.serial!.onApply(
      _index,
      changes,
      _tablesApplier(),
    );
    _serialIptcs[_index] = updated;
  }

  // True while a serial navigation is applying + loading; a second ⌘Enter
  // during the await would start an overlapping walk (double-apply, skipped
  // photo), so re-entrant calls are dropped instead.
  bool _navigating = false;

  /// Moves the walk to [next]: auto-saves the current photo, then loads the
  /// next one's values into the fields.
  Future<void> _goTo(int next) async {
    if (next < 0 || next >= _serialIptcs.length || next == _index) return;
    if (_navigating) return;
    _navigating = true;
    try {
      await _applyCurrent();
    } finally {
      _navigating = false;
    }
    if (!mounted) return;
    setState(() {
      _index = next;
      // Back to the caption so serial captioning stays keyboard-only.
      _section = _EditorSection.content;
      _init = iptcEditorInit([_serialIptcs[next]]);
      for (final field in IptcField.values) {
        _controllers[field]!.text = _init[field]!.value;
      }
      _seedTables(_serialIptcs[next]);
    });
    widget.serial!.onShow?.call(next);
    _captionFocus.requestFocus();
  }

  /// ⌘/Ctrl+Enter: save & next — or save & close on the last photo.
  void _nextOrFinish() => unawaited(
    _index + 1 < _serialIptcs.length ? _goTo(_index + 1) : _saveSerial(),
  );

  /// Photo Mechanic's "green globe": reverse-geocode the current photo and
  /// prefill the location fields. The values land in the text controllers, so
  /// they're editable before the normal save path writes them.
  Future<void> _fillFromGps() async {
    final index = _index;
    final place = await widget.serial!.onGeocode!(index);
    if (place == null || !mounted) return;
    // The user may have walked on while the geocoder ran — the previous
    // photo's location must not land in the new photo's fields.
    if (index != _index) return;
    _controllers[IptcField.city]!.text = place.city;
    _controllers[IptcField.state]!.text = place.state;
    _controllers[IptcField.country]!.text = place.country;
    _controllers[IptcField.countryCode]!.text = place.countryCode;
  }

  /// Which section the left nav-rail has selected. Serial navigation snaps back
  /// to Content so the caption re-focuses for the next photo.
  _EditorSection _section = _EditorSection.content;

  /// Bumped whenever the fields are rewritten wholesale (Clear / Load), so the
  /// table editors — which copy their seed rows — remount with fresh rows.
  int _generation = 0;

  /// The IptcCore the fields + table matrices currently describe.
  IptcCore _currentIptc() =>
      _tablesApplier()(const IptcCore().withOverrides(_currentText()));

  /// Photo Mechanic "Clear": empty every field and table. In a batch, a mixed
  /// field starts blank, so clearing leaves it unchanged — each photo keeps
  /// its own value (the only-changed-fields contract).
  void _clearFields() {
    setState(() {
      for (final c in _controllers.values) {
        c.text = '';
      }
      final hadTables = _currentTablesNotEmpty;
      _seedTables(const IptcCore());
      _tablesDirty = hadTables;
      _generation++;
    });
  }

  bool get _currentTablesNotEmpty =>
      _locationsShown.isNotEmpty ||
      _artwork.isNotEmpty ||
      _imageCreators.isNotEmpty ||
      _copyrightOwners.isNotEmpty ||
      _licensors.isNotEmpty ||
      _registryEntries.isNotEmpty;

  /// Stamps [template] onto the current field values — the same semantics as
  /// ⋮ → Apply metadata template (active fields only, honouring each field's
  /// merge mode), but into the editable fields, so nothing is written until
  /// Save. Template keywords are ignored (the M editor has no keyword field);
  /// `{variables}`/`=codes=` land literally and expand on save, per photo.
  void _loadTemplate(IptcTemplate template) {
    final out = applyTemplate(_currentIptc(), const [], template);
    setState(() {
      for (final field in IptcField.values) {
        _controllers[field]!.text = out.iptc.valueFor(field);
      }
      if (template.hasStructured) {
        _seedTables(out.iptc);
        _tablesDirty = true;
        _generation++;
      }
    });
  }

  /// Load → "From XMP file…": a Photo Mechanic / Bridge XMP template file.
  Future<void> _loadTemplateFile() async {
    final path = await widget.pickTemplatePath!();
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
    if (mounted) _loadTemplate(template);
  }

  /// "Save as template…": the current non-empty fields + tables become a named
  /// snapshot (Settings → Metadata templates). An existing name is updated.
  Future<void> _saveAsTemplate() async {
    final name = await promptForName(context, title: 'Save as template');
    if (name == null || name.isEmpty || !mounted) return;
    await widget.onSaveTemplate!(name, templateFromIptc(_currentIptc()));
  }

  @override
  Widget build(BuildContext context) {
    final batch = widget.count > 1;
    final serial = widget.serial;
    // Scale the dialog to the window, like the metadata-template editor, so the
    // M editor reads as a sibling of it rather than a narrow list.
    final media = MediaQuery.of(context).size;
    final w = (media.width * 0.7).clamp(560.0, media.width - 80);
    final h = (media.height * 0.75).clamp(
      400.0,
      media.height - 100 < 400 ? 400.0 : media.height - 100,
    );
    final dialog = AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      title: const Text('Metadata'),
      content: SizedBox(
        width: w,
        height: h,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (batch) _BatchBanner(count: widget.count),
            if (serial != null)
              _SerialHeader(
                filename: serial.filenames[_index],
                index: _index,
                total: _serialIptcs.length,
                onPrev: _index > 0 ? () => unawaited(_goTo(_index - 1)) : null,
                onNext: _index + 1 < _serialIptcs.length
                    ? () => unawaited(_goTo(_index + 1))
                    : null,
              ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 150, child: _navRail()),
                  const VerticalDivider(width: 1, color: AppColors.border),
                  Expanded(
                    flex: 4,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(
                        left: AppSpacing.lg,
                        right: AppSpacing.md,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: AppSpacing.xs),
                          ..._paneFor(_section),
                        ],
                      ),
                    ),
                  ),
                  // A large photo pane on the right — captioning needs to see
                  // the frame, not a thumbnail (the Photo Mechanic layout).
                  // Serial mode only (batch has no single photo to show).
                  if (serial?.preview != null) ...[
                    const VerticalDivider(width: 1, color: AppColors.border),
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: serial!.preview!(_index),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      // Utilities park muted on the left, split into the template trio and
      // Copy/Paste; the dialog's real decision — Cancel/Save — keeps the
      // right edge and the visual weight (Photo Mechanic's layout too).
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DialogUtilityButton(
              label: 'Clear',
              tooltip: 'Empty every field and table',
              onPressed: _clearFields,
            ),
            if (widget.templates.snapshots.isNotEmpty ||
                widget.pickTemplatePath != null)
              _LoadTemplateMenu(
                snapshots: widget.templates.snapshots,
                withFileEntry: widget.pickTemplatePath != null,
                onPickSnapshot: _loadTemplate,
                onPickFile: () => unawaited(_loadTemplateFile()),
              ),
            if (widget.onSaveTemplate != null)
              DialogUtilityButton(
                label: 'Save as…',
                tooltip: 'Save these fields as a named metadata template',
                onPressed: () => unawaited(_saveAsTemplate()),
              ),
            const DialogActionsRule(),
            DialogUtilityButton(
              label: 'Copy',
              tooltip: 'Copy all IPTC fields (⌘/Ctrl+Shift+C)',
              onPressed: _copy,
            ),
            ValueListenableBuilder<Map<IptcField, String>?>(
              valueListenable: iptcClipboard,
              builder: (_, clip, _) => DialogUtilityButton(
                label: 'Paste',
                tooltip: 'Paste copied IPTC fields (⌘/Ctrl+Shift+V)',
                onPressed: clip == null ? null : _paste,
              ),
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
    // Esc cancels (discard), matching the Cancel button — the dialog is
    // barrierDismissible:false to avoid accidental loss, so without this a
    // keyboard user couldn't dismiss it. Bound above the dialog so a focused
    // text field (which doesn't consume Escape) still lets it through.
    void cancel() => Navigator.of(context).pop();
    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.escape): cancel,
      // Copy/Paste the whole IPTC record, Photo Mechanic style. Shifted so they
      // don't steal ⌘/Ctrl+C/V from the focused text field (plain-text copy).
      const SingleActivator(LogicalKeyboardKey.keyC, meta: true, shift: true):
          _copy,
      const SingleActivator(
        LogicalKeyboardKey.keyC,
        control: true,
        shift: true,
      ): _copy,
      const SingleActivator(LogicalKeyboardKey.keyV, meta: true, shift: true):
          _paste,
      const SingleActivator(
        LogicalKeyboardKey.keyV,
        control: true,
        shift: true,
      ): _paste,
    };
    if (serial != null) {
      // Serial walk keys. Enter/PageUp/PageDown+modifier are free in text
      // fields (plain Enter stays the multiline caption's newline), unlike
      // bare PageUp/Down and arrows, which EditableText consumes.
      void prev() => unawaited(_goTo(_index - 1));
      void next() => unawaited(_goTo(_index + 1));
      bindings.addAll({
        const SingleActivator(LogicalKeyboardKey.enter, meta: true):
            _nextOrFinish,
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            _nextOrFinish,
        const SingleActivator(
          LogicalKeyboardKey.enter,
          meta: true,
          shift: true,
        ): prev,
        const SingleActivator(
          LogicalKeyboardKey.enter,
          control: true,
          shift: true,
        ): prev,
        // Page-flip alternates: same walk, arguably easier to remember.
        // Auto-saves like every navigation; stops at the ends (no close).
        const SingleActivator(LogicalKeyboardKey.pageDown, meta: true): next,
        const SingleActivator(LogicalKeyboardKey.pageDown, control: true): next,
        const SingleActivator(LogicalKeyboardKey.pageUp, meta: true): prev,
        const SingleActivator(LogicalKeyboardKey.pageUp, control: true): prev,
      });
    }
    return CallbackShortcuts(bindings: bindings, child: dialog);
  }

  /// The left-hand list of editor sections (scrolls if the dialog is short).
  Widget _navRail() => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in _EditorSection.values)
          // Tables are per-photo, so only in serial mode (batch/single-flat
          // editing has no clean "only-changed table" semantics).
          if (section != _EditorSection.tables || widget.serial != null)
            DialogNavItem(
              icon: section.icon,
              label: section.label,
              selected: section == _section,
              onSelected: () => setState(() => _section = section),
            ),
      ],
    ),
  );

  /// The right-pane fields for `section`. Multi-group sections (Status) keep a
  /// per-group header; single-group sections don't repeat the nav label. The
  /// Location group grows a "From GPS" action when the serial wiring can
  /// reverse-geocode.
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

  /// The six structured-table editors for the current photo (serial mode only).
  /// Each reports its matrix back and marks the tables dirty so navigation/save
  /// writes them through; keyed by photo index so a walk remounts them fresh.
  List<Widget> _tableFields() {
    IptcTableField table(
      String title,
      List<String> columns,
      List<List<String>> rows,
      ValueChanged<List<List<String>>> assign,
    ) => IptcTableField(
      key: ValueKey('$title-$_index-$_generation'),
      title: title,
      columns: columns,
      rows: rows,
      onChanged: (r) {
        assign(r);
        _tablesDirty = true;
      },
    );

    return [
      table('Locations shown', _locationColumns, _locationsShown, (r) {
        _locationsShown = r;
      }),
      table('Artwork or object', _artworkColumns, _artwork, (r) {
        _artwork = r;
      }),
      table('Image creators', _entityColumns, _imageCreators, (r) {
        _imageCreators = r;
      }),
      table('Copyright owners', _entityColumns, _copyrightOwners, (r) {
        _copyrightOwners = r;
      }),
      table('Licensors', _licensorColumns, _licensors, (r) {
        _licensors = r;
      }),
      table('Registry entries', _registryColumns, _registryEntries, (r) {
        _registryEntries = r;
      }),
    ];
  }

  List<Widget> _paneFor(_EditorSection section) {
    if (section == _EditorSection.tables) return _tableFields();
    final serial = widget.serial;
    final labelled = section.groups.length > 1;
    return [
      for (final group in section.groups) ...[
        if (labelled) DialogSection(group.label),
        if (group == IptcFieldGroup.location && serial?.onGeocode != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Align(
              alignment: Alignment.centerRight,
              child: _FromGpsButton(
                onPressed:
                    (serial!.hasGps.length > _index && serial.hasGps[_index])
                    ? () => unawaited(_fillFromGps())
                    : null,
              ),
            ),
          ),
        for (final field in IptcField.values)
          if (field.group == group)
            if (field == IptcField.dateCreated)
              _DateCreatedField(
                key: ValueKey(field),
                controller: _controllers[field]!,
                fallback:
                    (widget.serial != null &&
                        _index < widget.serial!.captureTimes.length)
                    ? widget.serial!.captureTimes[_index]
                    : null,
              )
            else if (field == IptcField.subjectCodes &&
                widget.topics.topics.isNotEmpty)
              _SubjectCodesField(
                key: ValueKey(field),
                controller: _controllers[field]!,
                mixed: _init[field]!.mixed,
                topics: widget.topics,
              )
            else
              _Field(
                key: ValueKey(field),
                field: field,
                controller: _controllers[field]!,
                mixed: _init[field]!.mixed,
                autofocus: field == IptcField.caption,
                focusNode: field == IptcField.caption ? _captionFocus : null,
              ),
        if (labelled) const SizedBox(height: AppSpacing.md),
      ],
      const SizedBox(height: AppSpacing.sm),
    ];
  }
}

/// The sections of the IPTC (M) editor, shown in the left nav-rail. Each maps
/// to one or more [IptcFieldGroup]s; the layout mirrors the metadata-template
/// editor's rail so the two dialogs feel like one family.
enum _EditorSection {
  content('Content', Icons.subject, [IptcFieldGroup.description]),
  location('Location', Icons.place_outlined, [IptcFieldGroup.location]),
  rights('Rights', Icons.copyright_outlined, [IptcFieldGroup.credit]),
  status('Status', Icons.assignment_outlined, [
    IptcFieldGroup.status,
    IptcFieldGroup.releases,
  ]),
  ai('AI', Icons.auto_awesome_outlined, [IptcFieldGroup.ai]),

  /// The repeatable structured tables — not tied to a flat field group. Shown
  /// only in serial (per-photo) mode.
  tables('Tables', Icons.table_rows_outlined, []);

  const _EditorSection(this.label, this.icon, this.groups);

  /// Nav-rail label.
  final String label;

  /// Nav-rail icon.
  final IconData icon;

  /// The field groups shown in this section's pane.
  final List<IptcFieldGroup> groups;
}

/// The "Load" action: a menu of the saved template snapshots plus (when a file
/// picker is wired) "From XMP file…" for Photo Mechanic / Bridge templates.
class _LoadTemplateMenu extends StatelessWidget {
  const _LoadTemplateMenu({
    required this.snapshots,
    required this.withFileEntry,
    required this.onPickSnapshot,
    required this.onPickFile,
  });

  final List<TemplateSnapshot> snapshots;
  final bool withFileEntry;
  final ValueChanged<IptcTemplate> onPickSnapshot;
  final VoidCallback onPickFile;

  /// Menu values: a snapshot's name, or this sentinel for the file entry
  /// (snapshots can never be named '' — the parser skips empty names).
  static const _fileEntry = '';

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Stamp a metadata template onto the fields',
    color: AppColors.surfaceElevated,
    onSelected: (value) {
      if (value == _fileEntry) {
        onPickFile();
        return;
      }
      for (final s in snapshots) {
        if (s.name == value) {
          onPickSnapshot(s.template);
          return;
        }
      }
    },
    itemBuilder: (_) => [
      for (final s in snapshots)
        PopupMenuItem<String>(
          value: s.name,
          height: 32,
          child: Text(
            s.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
        ),
      if (snapshots.isNotEmpty && withFileEntry) const PopupMenuDivider(),
      if (withFileEntry)
        const PopupMenuItem<String>(
          value: _fileEntry,
          height: 32,
          child: Text(
            'From XMP file…',
            style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
        ),
    ],
    // Styled like a DialogUtilityButton so the whole utility group reads as
    // one muted family next to the pink Cancel/Save pair.
    child: const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Load',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          Icon(
            Icons.arrow_drop_down,
            size: 18,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    ),
  );
}

/// The "fill location from GPS" button in the Location section header.
/// Disabled (with an explaining tooltip) when the photo has no position.
class _FromGpsButton extends StatelessWidget {
  const _FromGpsButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: onPressed == null
        ? 'This photo has no GPS position'
        : 'Fill city/state/country from the photo’s GPS position',
    child: TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12),
      ),
      icon: const Icon(Icons.place_outlined, size: 14),
      label: const Text('From GPS'),
    ),
  );
}

/// The serial-walk header: filename, position, prev/next. The frame itself is
/// shown large in the dialog's right-hand pane (not here), so captioning reads
/// the photo, not a thumbnail.
class _SerialHeader extends StatelessWidget {
  const _SerialHeader({
    required this.filename,
    required this.index,
    required this.total,
    required this.onPrev,
    required this.onNext,
  });

  final String filename;
  final int index;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                filename,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${index + 1} of $total',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onPrev,
          tooltip:
              'Previous photo — saves edits '
              '(⌘/Ctrl+PgUp or ⌘/Ctrl+Shift+Enter)',
          icon: const Icon(Icons.chevron_left, size: 20),
        ),
        IconButton(
          onPressed: onNext,
          tooltip: 'Next photo — saves edits (⌘/Ctrl+PgDn or ⌘/Ctrl+Enter)',
          icon: const Icon(Icons.chevron_right, size: 20),
        ),
      ],
    ),
  );
}

/// The large provider-backed photo preview for the right-hand pane, injected
/// via [SerialCaptioning.preview] so the dialog itself stays provider-free.
/// Prefers the screen-res loupe preview and falls back to the grid thumbnail
/// while it decodes, so the frame appears instantly and then sharpens. Zoomable
/// (slider, trackpad pinch, drag-to-pan) to check focus/framing while captioning
/// without leaving the editor for the loupe.
class _SerialPreview extends ConsumerStatefulWidget {
  const _SerialPreview({required this.path, super.key});

  final String path;

  @override
  ConsumerState<_SerialPreview> createState() => _SerialPreviewState();
}

class _SerialPreviewState extends ConsumerState<_SerialPreview> {
  static const double _maxZoom = 8;

  final TransformationController _tc = TransformationController();
  double _scale = 1;
  Size _viewport = Size.zero;

  @override
  void initState() {
    super.initState();
    _tc.addListener(_syncScale);
  }

  @override
  void dispose() {
    _tc
      ..removeListener(_syncScale)
      ..dispose();
    super.dispose();
  }

  /// Keep the slider in step with pinch/drag zooming.
  void _syncScale() {
    final s = _tc.value.getMaxScaleOnAxis();
    if ((s - _scale).abs() > 0.001) setState(() => _scale = s);
  }

  /// Slider-driven zoom about the viewport centre (so the middle of the frame
  /// stays put); 1× resets pan too.
  void _setScale(double scale) {
    final c = _viewport.center(Offset.zero);
    _tc.value = Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1);
  }

  @override
  Widget build(BuildContext context) {
    final loupe = ref.watch(loupePreviewProvider(widget.path)).value;
    final thumb = ref.watch(thumbnailProvider(widget.path)).value;
    final bytes = loupe ?? thumb;
    return Column(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: bytes == null
                ? const Icon(
                    Icons.image_outlined,
                    size: 32,
                    color: AppColors.textSecondary,
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      _viewport = constraints.biggest;
                      return InteractiveViewer(
                        transformationController: _tc,
                        maxScale: _maxZoom,
                        child: Image.memory(
                          bytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      );
                    },
                  ),
          ),
        ),
        if (bytes != null) _zoomBar(),
      ],
    );
  }

  Widget _zoomBar() => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: Row(
      children: [
        const Icon(Icons.zoom_out, size: 16, color: AppColors.textSecondary),
        Expanded(
          child: Slider(
            value: _scale.clamp(1.0, _maxZoom),
            min: 1,
            max: _maxZoom,
            onChanged: _setScale,
          ),
        ),
        const Icon(Icons.zoom_in, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 36,
          child: Text(
            '${_scale.toStringAsFixed(1)}×',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The "editing N photos" hint that makes the batch semantics explicit.
class _BatchBanner extends StatelessWidget {
  const _BatchBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      border: Border.all(color: AppColors.border),
    ),
    child: Text(
      'Editing $count photos — only fields you change are applied.',
      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
    ),
  );
}

/// The Subject-codes field with Media-Topics autocomplete: type after the last
/// comma and matching topics appear underneath; picking one replaces the typed
/// fragment with its `medtop:` QCode. Codes already in the field are shown as
/// their friendly labels so the value never reads as opaque numbers.
class _SubjectCodesField extends StatefulWidget {
  const _SubjectCodesField({
    required this.controller,
    required this.mixed,
    required this.topics,
    super.key,
  });

  final TextEditingController controller;
  final bool mixed;
  final MediaTopics topics;

  @override
  State<_SubjectCodesField> createState() => _SubjectCodesFieldState();
}

class _SubjectCodesFieldState extends State<_SubjectCodesField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// The comma-separated entries; the last one is the fragment being typed.
  List<String> get _parts => widget.controller.text.split(',');

  String get _fragment => _parts.last.trim();

  /// Suggestions for the fragment, minus codes already picked.
  List<MediaTopic> get _suggestions {
    if (!_focus.hasFocus) return const [];
    final chosen = {
      for (final part in _parts.sublist(0, _parts.length - 1)) part.trim(),
    };
    return [
      for (final topic in widget.topics.search(_fragment, limit: 6))
        if (!chosen.contains(topic.qcode)) topic,
    ];
  }

  /// Replaces the typed fragment with [topic]'s QCode.
  void _pick(MediaTopic topic) {
    final kept = _parts.sublist(0, _parts.length - 1).map((p) => p.trim());
    final text = [...kept, topic.qcode].join(', ');
    widget.controller
      ..text = text
      ..selection = TextSelection.collapsed(offset: text.length);
  }

  /// Friendly names of the codes currently in the field, for the caption line.
  String get _labels {
    final names = [
      for (final part in _parts)
        if (part.trim().isNotEmpty) widget.topics.labelFor(part.trim()),
    ];
    return names.whereType<String>().join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions;
    final labels = _labels;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Media topics',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: widget.controller,
            focusNode: _focus,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.mixed
                  ? 'Mixed — leave to keep each photo’s value'
                  : 'Type to search the IPTC vocabulary…',
              hintStyle: const TextStyle(
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
                fontSize: 12,
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          if (labels.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                labels,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
          for (final topic in suggestions)
            InkWell(
              onTap: () => _pick(topic),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        topic.parent.isEmpty
                            ? topic.label
                            : '${topic.label}  ‹ ${topic.parent}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      topic.qcode,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The IPTC Date Created field: a date/time picker over the ISO string in
/// [controller]. Empty means "use the capture time" — then [fallback] (the
/// photo's EXIF capture time) is shown greyed as the effective value, and
/// clearing an explicit date returns to it. Photo Mechanic's "Time and Date".
class _DateCreatedField extends StatefulWidget {
  const _DateCreatedField({
    required this.controller,
    required this.fallback,
    super.key,
  });

  final TextEditingController controller;
  final DateTime? fallback;

  @override
  State<_DateCreatedField> createState() => _DateCreatedFieldState();
}

class _DateCreatedFieldState extends State<_DateCreatedField> {
  bool get _isSet => widget.controller.text.isNotEmpty;

  DateTime? get _current {
    final text = widget.controller.text;
    return text.isEmpty ? widget.fallback : DateTime.tryParse(text);
  }

  Future<void> _pick() async {
    final base = _current ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (!mounted) return;
    final t = time ?? TimeOfDay.fromDateTime(base);
    final dt = DateTime(date.year, date.month, date.day, t.hour, t.minute);
    setState(() => widget.controller.text = _isoNoMillis(dt));
  }

  void _clear() => setState(() => widget.controller.text = '');

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final fromCapture = !_isSet && widget.fallback != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Date created',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pick,
                  icon: const Icon(Icons.event, size: 16),
                  label: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      current == null ? 'Not set' : _formatDateTime(current),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ),
              if (_isSet)
                IconButton(
                  tooltip: 'Clear (use capture time)',
                  onPressed: _clear,
                  icon: const Icon(Icons.clear, size: 16),
                ),
            ],
          ),
          if (fromCapture)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text(
                'From capture time',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

/// Formats [dt] as `YYYY-MM-DD HH:MM` for display.
String _formatDateTime(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}

/// ISO 8601 local timestamp without milliseconds, for storage in the field.
String _isoNoMillis(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year.toString().padLeft(4, '0')}-${two(dt.month)}-'
      '${two(dt.day)}T${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
}

/// One labelled text field. Multi-line fields (caption, alt-text, instructions)
/// get a taller area; "Mixed" fields hint that leaving them keeps each value.
class _Field extends StatelessWidget {
  const _Field({
    required this.field,
    required this.controller,
    required this.mixed,
    required this.autofocus,
    this.focusNode,
    super.key,
  });

  final IptcField field;
  final TextEditingController controller;
  final bool mixed;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          field.label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          minLines: field.multiline ? 2 : 1,
          maxLines: field.multiline ? 4 : 1,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            hintText: mixed ? 'Mixed — leave to keep each photo’s value' : null,
            hintStyle: const TextStyle(
              color: AppColors.textSecondary,
              fontStyle: FontStyle.italic,
              fontSize: 12,
            ),
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    ),
  );
}
