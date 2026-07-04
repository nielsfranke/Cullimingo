/// Photo Mechanic-style code replacements: type a short code between a
/// delimiter (default `=`) and it expands to stored text. A code can hold
/// several alternatives; `=code#2=` selects the second. Used to caption
/// repetitive subjects fast (e.g. `=lebron=` → "LeBron James").
class CodeReplacements {
  /// Creates a code table.
  const CodeReplacements({this.delimiter = '=', this.codes = const {}});

  /// Rebuilds a table from the map written by [toJson]. Tolerant of malformed
  /// entries so an old settings file never breaks a newer build.
  factory CodeReplacements.fromJson(Map<String, dynamic> json) {
    final raw = json['codes'];
    final codes = <String, List<String>>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        final value = entry.value;
        if (value is List) {
          codes[entry.key.toString()] = value.whereType<String>().toList();
        }
      }
    }
    final delimiter = json['delimiter'];
    return CodeReplacements(
      delimiter: delimiter is String && delimiter.isNotEmpty ? delimiter : '=',
      codes: codes,
    );
  }

  /// Parses a Photo Mechanic code file: UTF-8, tab-separated, first column the
  /// code and the rest its replacements (one per column). Blank lines and rows
  /// without a code are skipped; trailing blank replacements are dropped.
  factory CodeReplacements.fromTabText(String text, {String delimiter = '='}) {
    final codes = <String, List<String>>{};
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) continue;
      final cols = line.split('\t');
      final code = cols.first.trim();
      if (code.isEmpty || cols.length < 2) continue;
      final replacements = [for (final c in cols.skip(1)) c.trim()];
      while (replacements.isNotEmpty && replacements.last.isEmpty) {
        replacements.removeLast();
      }
      if (replacements.isNotEmpty) codes[code] = replacements;
    }
    return CodeReplacements(delimiter: delimiter, codes: codes);
  }

  /// The character wrapping a code, e.g. `=` in `=ff=`.
  final String delimiter;

  /// Code → its ordered replacements (index 0 is the default; `#n` is 1-based).
  final Map<String, List<String>> codes;

  /// True when there is nothing to expand.
  bool get isEmpty => codes.isEmpty;

  /// A JSON-friendly map for persistence in the app settings store.
  Map<String, dynamic> toJson() => {'delimiter': delimiter, 'codes': codes};
}

/// Expands every `=code=` (and `=code#n=`) in [input] using [table]. An unknown
/// code, or an out-of-range alternate, is left exactly as written so nothing is
/// silently lost.
String expandCodes(String input, CodeReplacements table) {
  if (table.codes.isEmpty) return input;
  final d = RegExp.escape(table.delimiter);
  final re = RegExp('$d([^$d#]+)(?:#(\\d+))?$d');
  return input.replaceAllMapped(re, (match) {
    final list = table.codes[match.group(1)];
    if (list == null || list.isEmpty) return match.group(0)!;
    final n = int.tryParse(match.group(2) ?? '1') ?? 1;
    if (n < 1 || n > list.length) return match.group(0)!;
    return list[n - 1];
  });
}
