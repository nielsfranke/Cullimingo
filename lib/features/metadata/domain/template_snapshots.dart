import 'package:cullimingo/features/metadata/domain/iptc_template.dart';

/// One named, saved metadata template (a "snapshot") — e.g. per customer or
/// assignment: "Weser-Kurier", "Bundesliga", "Stock".
class TemplateSnapshot {
  /// Creates a named snapshot.
  const TemplateSnapshot({required this.name, required this.template});

  /// The user-visible name (unique within a [TemplateSnapshots]).
  final String name;

  /// The template this snapshot saves.
  final IptcTemplate template;
}

/// The saved metadata templates: an ordered list of named snapshots plus which
/// one is active. The active snapshot is what the apply paths (⋮ menu /
/// `T` shortcut / apply-on-ingest) stamp; switching it is how the user changes
/// "which customer am I shooting for" without re-typing the template.
class TemplateSnapshots {
  /// Creates a snapshot list.
  const TemplateSnapshots({this.snapshots = const [], this.activeName = ''});

  /// Rebuilds the list from the map written by [toJson]. Tolerant of malformed
  /// entries (skipped) so an old settings file never crashes a newer build.
  factory TemplateSnapshots.fromJson(Map<String, dynamic> json) {
    final raw = json['templates'];
    final snapshots = <TemplateSnapshot>[];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is! Map) continue;
        final name = entry['name'];
        final template = entry['template'];
        if (name is! String || name.isEmpty || template is! Map) continue;
        snapshots.add(
          TemplateSnapshot(
            name: name,
            template: IptcTemplate.fromJson(template.cast<String, dynamic>()),
          ),
        );
      }
    }
    final active = json['active'];
    return TemplateSnapshots(
      snapshots: snapshots,
      activeName: active is String ? active : '',
    );
  }

  /// Wraps a pre-snapshots settings file's single template as one active
  /// snapshot named [legacyName] — the upgrade path from the old
  /// `metadataTemplate` key.
  factory TemplateSnapshots.fromLegacy(Map<String, dynamic> templateJson) {
    final template = IptcTemplate.fromJson(templateJson);
    if (template.isEmpty) return const TemplateSnapshots();
    return TemplateSnapshots(
      snapshots: [TemplateSnapshot(name: legacyName, template: template)],
      activeName: legacyName,
    );
  }

  /// The name the single pre-snapshots template gets when migrated.
  static const legacyName = 'Default';

  /// The saved snapshots, in user order.
  final List<TemplateSnapshot> snapshots;

  /// The name of the active snapshot. May not match any snapshot (e.g. after a
  /// delete); resolution falls back to the first snapshot.
  final String activeName;

  /// True when nothing is saved.
  bool get isEmpty => snapshots.isEmpty;

  /// The active snapshot — the one matching [activeName], else the first one,
  /// else null when the list is empty.
  TemplateSnapshot? get activeSnapshot {
    if (snapshots.isEmpty) return null;
    for (final s in snapshots) {
      if (s.name == activeName) return s;
    }
    return snapshots.first;
  }

  /// The active snapshot's template, or an empty template when none is saved.
  IptcTemplate get active => activeSnapshot?.template ?? const IptcTemplate();

  /// A JSON-friendly map for persistence in the app settings store.
  Map<String, dynamic> toJson() => {
    'active': activeName,
    'templates': [
      for (final s in snapshots)
        {'name': s.name, 'template': s.template.toJson()},
    ],
  };

  /// Returns a copy with [name] as the active snapshot.
  TemplateSnapshots setActive(String name) =>
      TemplateSnapshots(snapshots: snapshots, activeName: name);

  /// Returns a copy where the snapshot called [name] holds [template] —
  /// replaced in place when it exists, appended (and made active) when new.
  TemplateSnapshots upsert(String name, IptcTemplate template) {
    final exists = snapshots.any((s) => s.name == name);
    return TemplateSnapshots(
      snapshots: [
        for (final s in snapshots)
          if (s.name == name)
            TemplateSnapshot(name: name, template: template)
          else
            s,
        if (!exists) TemplateSnapshot(name: name, template: template),
      ],
      activeName: exists ? activeName : name,
    );
  }

  /// Returns a copy with the snapshot called [from] renamed to [to] (a no-op
  /// when [from] doesn't exist). Keeps it active if it was.
  TemplateSnapshots rename(String from, String to) => TemplateSnapshots(
    snapshots: [
      for (final s in snapshots)
        if (s.name == from)
          TemplateSnapshot(name: to, template: s.template)
        else
          s,
    ],
    activeName: activeName == from ? to : activeName,
  );

  /// Returns a copy without the snapshot called [name]. When it was active,
  /// the first remaining snapshot becomes active.
  TemplateSnapshots remove(String name) {
    final remaining = [
      for (final s in snapshots)
        if (s.name != name) s,
    ];
    return TemplateSnapshots(
      snapshots: remaining,
      activeName: activeName == name
          ? (remaining.isEmpty ? '' : remaining.first.name)
          : activeName,
    );
  }
}
