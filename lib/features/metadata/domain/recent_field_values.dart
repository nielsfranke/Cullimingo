import 'package:cullimingo/features/metadata/domain/iptc_core.dart';

/// Per-field history of values the user has stamped, powering the template
/// editor's ▼ "recent values" menu (Photo Mechanic's per-field dropdown). Most
/// recent first, de-duplicated case-sensitively, capped per field so the store
/// stays small. Pure and immutable — [record] returns a new instance.
class RecentFieldValues {
  /// Creates a history from a field → values map (ordered newest-first).
  const RecentFieldValues([this.byField = const {}]);

  /// Rebuilds from the map written by [toJson]. Tolerant of unknown field names
  /// and malformed entries (skipped) so an old settings file never crashes.
  factory RecentFieldValues.fromJson(Map<String, dynamic> json) {
    final byField = <IptcField, List<String>>{};
    for (final field in IptcField.values) {
      final raw = json[field.name];
      if (raw is List) {
        final values = raw
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .toList();
        if (values.isNotEmpty) byField[field] = values;
      }
    }
    return RecentFieldValues(byField);
  }

  /// How many values are kept per field.
  static const int cap = 10;

  /// The stored values per field, newest first.
  final Map<IptcField, List<String>> byField;

  /// The remembered values for [field], newest first (empty when none).
  List<String> forField(IptcField field) => byField[field] ?? const [];

  /// Returns a copy with [value] recorded as [field]'s most-recent value:
  /// moved/added to the front, older duplicates dropped, capped at [cap]. A
  /// blank value is ignored (returns this unchanged).
  RecentFieldValues record(IptcField field, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return this;
    final existing = forField(field);
    final next = [
      trimmed,
      for (final v in existing)
        if (v != trimmed) v,
    ];
    if (next.length > cap) next.removeRange(cap, next.length);
    return RecentFieldValues({...byField, field: next});
  }

  /// Records every entry of [fields] (a template's active values) at once.
  RecentFieldValues recordAll(Map<IptcField, String> fields) {
    var out = this;
    for (final entry in fields.entries) {
      out = out.record(entry.key, entry.value);
    }
    return out;
  }

  /// A JSON-friendly map for persistence in the app settings store.
  Map<String, dynamic> toJson() => {
    for (final entry in byField.entries)
      if (entry.value.isNotEmpty) entry.key.name: entry.value,
  };
}
