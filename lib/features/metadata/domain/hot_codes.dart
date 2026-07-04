import 'package:cullimingo/features/metadata/domain/iptc_core.dart';

/// Hot codes: one `=code=` fills *several* IPTC fields at once (e.g.
/// `=arena=` → sublocation + city + state + country). Goes beyond Photo
/// Mechanic's text→text replacements — this is the "stamp a known place or
/// customer block while typing" speed trick. Shares the delimiter with the
/// plain code-replacement table.
class HotCodes {
  /// Creates a hot-code table.
  const HotCodes({this.codes = const {}});

  /// Rebuilds a table from the map written by [toJson]. Unknown field names
  /// are skipped so an old settings file never breaks a newer build.
  factory HotCodes.fromJson(Map<String, dynamic> json) {
    final raw = json['codes'];
    final codes = <String, Map<IptcField, String>>{};
    if (raw is Map) {
      final byName = {for (final f in IptcField.values) f.name: f};
      for (final entry in raw.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        final fields = <IptcField, String>{};
        for (final fieldEntry in value.entries) {
          final field = byName[fieldEntry.key.toString()];
          if (field != null && fieldEntry.value is String) {
            fields[field] = fieldEntry.value as String;
          }
        }
        if (fields.isNotEmpty) codes[entry.key.toString()] = fields;
      }
    }
    return HotCodes(codes: codes);
  }

  /// Code → the field values it stamps.
  final Map<String, Map<IptcField, String>> codes;

  /// True when there is nothing to expand.
  bool get isEmpty => codes.isEmpty;

  /// A JSON-friendly map for persistence in the app settings store.
  Map<String, dynamic> toJson() => {
    'codes': {
      for (final e in codes.entries)
        e.key: {for (final f in e.value.entries) f.key.name: f.value},
    },
  };
}

/// Scans [input] for `delimiter`-wrapped tokens naming a hot code. Returns the
/// input with those tokens removed plus the merged field values (later tokens
/// win on overlap), or null when nothing matched. Tokens naming only plain
/// text codes are left for the text expansion pass.
({String text, Map<IptcField, String> fields})? expandHotCodes(
  String input, {
  required String delimiter,
  required HotCodes hotCodes,
}) {
  if (hotCodes.isEmpty) return null;
  final d = RegExp.escape(delimiter);
  final re = RegExp('$d([^$d]+)$d');
  final fields = <IptcField, String>{};
  final text = input.replaceAllMapped(re, (match) {
    final mapped = hotCodes.codes[match.group(1)];
    if (mapped == null) return match.group(0)!;
    fields.addAll(mapped);
    return '';
  });
  if (fields.isEmpty) return null;
  return (text: text, fields: fields);
}
