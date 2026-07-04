import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/features/metadata/domain/iptc_structured.dart';

/// How a text field (caption) merges with a photo's existing value.
enum TextApplyMode {
  /// Overwrite the existing value.
  replace('Replace'),

  /// Put the template text before the existing value.
  prefix('Prefix'),

  /// Put the template text after the existing value.
  append('Append');

  const TextApplyMode(this.label);

  /// Human-readable label for the picker.
  final String label;
}

/// How a template's keywords merge with a photo's existing keywords.
enum KeywordApplyMode {
  /// Replace the whole keyword list.
  replace('Replace'),

  /// Add the template keywords to the existing ones (de-duplicated).
  append('Add to existing');

  const KeywordApplyMode(this.label);

  /// Human-readable label for the picker.
  final String label;
}

/// A reusable set of IPTC values to stamp onto photos — the Photo Mechanic
/// "stationery pad" / metadata template. Only the fields present in [fields] are
/// written (the per-field checkbox); everything else is left untouched. Each
/// text field merges per [textModes] (Replace/Prefix/Append, default replace);
/// keywords, when [keywords] is non-null, honour [keywordMode]. A null
/// [keywords] leaves a photo's keywords alone.
class IptcTemplate {
  /// Creates a template.
  const IptcTemplate({
    this.fields = const {},
    this.textModes = const {},
    this.keywords,
    this.keywordMode = KeywordApplyMode.replace,
    this.locationsShown = const [],
    this.artwork = const [],
    this.imageCreators = const [],
    this.copyrightOwners = const [],
    this.licensors = const [],
    this.registryEntries = const [],
  });

  /// Rebuilds a template from the map written by [toJson]. Tolerant of unknown
  /// field/mode names (skipped / defaulted) so an old settings file never
  /// crashes a newer build. Reads the per-field `textModes` map and migrates a
  /// legacy `captionMode` key into it.
  factory IptcTemplate.fromJson(Map<String, dynamic> json) {
    final rawFields = json['fields'];
    final fields = <IptcField, String>{};
    if (rawFields is Map) {
      for (final field in IptcField.values) {
        final value = rawFields[field.name];
        if (value is String) fields[field] = value;
      }
    }
    final textModes = <IptcField, TextApplyMode>{};
    final rawModes = json['textModes'];
    if (rawModes is Map) {
      for (final field in IptcField.values) {
        final raw = rawModes[field.name];
        if (raw is String) {
          final mode = _modeByName(TextApplyMode.values, raw, null);
          if (mode != null) textModes[field] = mode;
        }
      }
    }
    // Legacy single-field caption mode → the map.
    final legacyCaption = _modeByName(
      TextApplyMode.values,
      json['captionMode'],
      null,
    );
    if (legacyCaption != null && legacyCaption != TextApplyMode.replace) {
      textModes.putIfAbsent(IptcField.caption, () => legacyCaption);
    }
    final rawKeywords = json['keywords'];
    return IptcTemplate(
      fields: fields,
      textModes: textModes,
      keywords: rawKeywords is List
          ? rawKeywords.whereType<String>().toList()
          : null,
      keywordMode:
          _modeByName(
            KeywordApplyMode.values,
            json['keywordMode'],
            KeywordApplyMode.replace,
          ) ??
          KeywordApplyMode.replace,
      locationsShown: parseRecords(
        json['locationsShown'],
        IptcLocation.fromJson,
        (l) => l.isEmpty,
      ),
      artwork: parseRecords(
        json['artwork'],
        IptcArtwork.fromJson,
        (a) => a.isEmpty,
      ),
      imageCreators: parseRecords(
        json['imageCreators'],
        IptcEntity.fromJson,
        (e) => e.isEmpty,
      ),
      copyrightOwners: parseRecords(
        json['copyrightOwners'],
        IptcEntity.fromJson,
        (e) => e.isEmpty,
      ),
      licensors: parseRecords(
        json['licensors'],
        IptcLicensor.fromJson,
        (l) => l.isEmpty,
      ),
      registryEntries: parseRecords(
        json['registryEntries'],
        IptcRegistryEntry.fromJson,
        (r) => r.isEmpty,
      ),
    );
  }

  /// The active fields and their values (absent field = leave as-is).
  final Map<IptcField, String> fields;

  /// How each text field (when active) merges with a photo's existing value.
  /// A field absent from the map defaults to [TextApplyMode.replace].
  final Map<IptcField, TextApplyMode> textModes;

  /// How a given [field] merges with the existing value — replace unless the
  /// user picked Prefix/Append.
  TextApplyMode modeFor(IptcField field) =>
      textModes[field] ?? TextApplyMode.replace;

  /// How [IptcField.caption] merges — kept for callers that only care about it.
  TextApplyMode get captionMode => modeFor(IptcField.caption);

  /// Keywords to apply, or null to leave a photo's keywords untouched.
  final List<String>? keywords;

  /// How [keywords] (when non-null) merge with the existing list.
  final KeywordApplyMode keywordMode;

  /// Location-shown rows to stamp (replace the photo's when non-empty).
  final List<IptcLocation> locationsShown;

  /// Artwork rows to stamp (replace the photo's when non-empty).
  final List<IptcArtwork> artwork;

  /// PLUS image-creator rows to stamp (replace the photo's when non-empty).
  final List<IptcEntity> imageCreators;

  /// PLUS copyright-owner rows to stamp (replace the photo's when non-empty).
  final List<IptcEntity> copyrightOwners;

  /// PLUS licensor rows to stamp (replace the photo's when non-empty).
  final List<IptcLicensor> licensors;

  /// Registry-entry rows to stamp (replace the photo's when non-empty).
  final List<IptcRegistryEntry> registryEntries;

  /// A copy with [f] applied to every field value, keyword and table cell;
  /// merge modes and field activation stay put. Powers per-photo expansion
  /// (`expandTemplate`) and PM-variable translation on template import.
  IptcTemplate mapValues(String Function(String) f) => IptcTemplate(
    fields: {for (final e in fields.entries) e.key: f(e.value)},
    textModes: textModes,
    keywords: keywords == null ? null : [for (final k in keywords!) f(k)],
    keywordMode: keywordMode,
    locationsShown: [for (final l in locationsShown) l.mapStrings(f)],
    artwork: [for (final a in artwork) a.mapStrings(f)],
    imageCreators: [for (final e in imageCreators) e.mapStrings(f)],
    copyrightOwners: [for (final e in copyrightOwners) e.mapStrings(f)],
    licensors: [for (final l in licensors) l.mapStrings(f)],
    registryEntries: [for (final r in registryEntries) r.mapStrings(f)],
  );

  /// True when the template carries any structured-table rows.
  bool get hasStructured =>
      locationsShown.isNotEmpty ||
      artwork.isNotEmpty ||
      imageCreators.isNotEmpty ||
      copyrightOwners.isNotEmpty ||
      licensors.isNotEmpty ||
      registryEntries.isNotEmpty;

  /// True when the template would change nothing (no fields, keywords, tables).
  bool get isEmpty =>
      fields.isEmpty &&
      keywords == null &&
      locationsShown.isEmpty &&
      artwork.isEmpty &&
      imageCreators.isEmpty &&
      copyrightOwners.isEmpty &&
      licensors.isEmpty &&
      registryEntries.isEmpty;

  /// A JSON-friendly map for persistence in the app settings store. Only
  /// non-default (non-replace) field modes are written, keeping the file small.
  Map<String, dynamic> toJson() => {
    'fields': {for (final e in fields.entries) e.key.name: e.value},
    'textModes': {
      for (final e in textModes.entries)
        if (e.value != TextApplyMode.replace) e.key.name: e.value.name,
    },
    if (keywords != null) 'keywords': keywords,
    'keywordMode': keywordMode.name,
    if (locationsShown.isNotEmpty)
      'locationsShown': [for (final l in locationsShown) l.toJson()],
    if (artwork.isNotEmpty) 'artwork': [for (final a in artwork) a.toJson()],
    if (imageCreators.isNotEmpty)
      'imageCreators': [for (final e in imageCreators) e.toJson()],
    if (copyrightOwners.isNotEmpty)
      'copyrightOwners': [for (final e in copyrightOwners) e.toJson()],
    if (licensors.isNotEmpty)
      'licensors': [for (final l in licensors) l.toJson()],
    if (registryEntries.isNotEmpty)
      'registryEntries': [for (final r in registryEntries) r.toJson()],
  };
}

/// Converts a photo's [iptc] (+ its [keywords]) into a template: every
/// non-empty field becomes an active Replace-mode field, the structured tables
/// are copied, and non-empty keywords become a Replace keyword set (empty →
/// the template leaves keywords alone). Powers "Save as template" in the M
/// editor and XMP template files (Photo Mechanic / Bridge interop) — both
/// carry values only, never merge modes. Date Created is skipped for the same
/// reason the template editor hides it: stamping one fixed capture date onto
/// other photos is never right.
IptcTemplate templateFromIptc(
  IptcCore iptc, {
  List<String> keywords = const [],
}) => IptcTemplate(
  fields: {
    for (final field in IptcField.values)
      if (field != IptcField.dateCreated && iptc.valueFor(field).isNotEmpty)
        field: iptc.valueFor(field),
  },
  keywords: keywords.isEmpty ? null : keywords,
  locationsShown: iptc.locationsShown,
  artwork: iptc.artwork,
  imageCreators: iptc.imageCreators,
  copyrightOwners: iptc.copyrightOwners,
  licensors: iptc.licensors,
  registryEntries: iptc.registryEntries,
);

/// The [IptcCore] a template's values describe — active fields over an empty
/// record, plus the structured tables. The inverse of [templateFromIptc] (both
/// drop merge modes, which have no XMP form).
IptcCore iptcFromTemplate(IptcTemplate template) => const IptcCore()
    .withOverrides(template.fields)
    .withStructured(
      locationsShown: template.locationsShown,
      artwork: template.artwork,
      imageCreators: template.imageCreators,
      copyrightOwners: template.copyrightOwners,
      licensors: template.licensors,
      registryEntries: template.registryEntries,
    );

T? _modeByName<T extends Enum>(List<T> values, Object? raw, T? fallback) {
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return fallback;
}

/// The result of stamping an [IptcTemplate] onto a photo.
typedef TemplateApplication = ({IptcCore iptc, List<String> keywords});

/// Applies [template] to a photo's current [existing] IPTC and its
/// [existingKeywords], returning the new values. Pure — the caller persists and
/// mirrors to the sidecar. Fields absent from the template are preserved; each
/// active text field honours its [IptcTemplate.modeFor] merge mode; keywords
/// are only touched when the template carries them.
TemplateApplication applyTemplate(
  IptcCore existing,
  List<String> existingKeywords,
  IptcTemplate template,
) {
  final overrides = <IptcField, String>{};
  for (final entry in template.fields.entries) {
    final mode = entry.key.mergeable
        ? template.modeFor(entry.key)
        : TextApplyMode.replace;
    overrides[entry.key] = mode == TextApplyMode.replace
        ? entry.value
        : _mergeText(existing.valueFor(entry.key), entry.value, mode);
  }

  final keywords = switch (template.keywords) {
    null => existingKeywords,
    final incoming when template.keywordMode == KeywordApplyMode.replace =>
      incoming,
    final incoming => _mergeKeywords(existingKeywords, incoming),
  };

  // Structured tables replace the photo's when the template carries any (like
  // a "replace" keyword set) — templates stamp identical boilerplate rows.
  final iptc = existing
      .withOverrides(overrides)
      .withStructured(
        locationsShown: template.locationsShown.isEmpty
            ? null
            : template.locationsShown,
        artwork: template.artwork.isEmpty ? null : template.artwork,
        imageCreators: template.imageCreators.isEmpty
            ? null
            : template.imageCreators,
        copyrightOwners: template.copyrightOwners.isEmpty
            ? null
            : template.copyrightOwners,
        licensors: template.licensors.isEmpty ? null : template.licensors,
        registryEntries: template.registryEntries.isEmpty
            ? null
            : template.registryEntries,
      );

  return (iptc: iptc, keywords: keywords);
}

/// Merges [incoming] template text into [existing] per [mode], separating the
/// two non-empty parts with a single space.
String _mergeText(String existing, String incoming, TextApplyMode mode) {
  if (existing.isEmpty || incoming.isEmpty) {
    return mode == TextApplyMode.replace ? incoming : '$existing$incoming';
  }
  return switch (mode) {
    TextApplyMode.replace => incoming,
    TextApplyMode.prefix => '$incoming $existing',
    TextApplyMode.append => '$existing $incoming',
  };
}

/// Appends [incoming] to [existing] keywords, preserving order and dropping
/// case-insensitive duplicates already present.
List<String> _mergeKeywords(List<String> existing, List<String> incoming) {
  final seen = {for (final k in existing) k.toLowerCase()};
  return [
    ...existing,
    for (final k in incoming)
      if (seen.add(k.toLowerCase())) k,
  ];
}
