/// Parsing for the comma-separated keyword field (`dc:subject`, Phase 4).
///
/// Keeps the keyword editor's text ⇄ list conversion pure so it can be unit
/// tested without a widget.
library;

/// Splits a comma-separated [text] into trimmed, de-duplicated keywords,
/// dropping blanks while preserving first-seen order.
List<String> parseKeywords(String text) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in text.split(',')) {
    final k = raw.trim();
    if (k.isEmpty || !seen.add(k)) continue;
    out.add(k);
  }
  return out;
}

/// Joins [keywords] back into the comma-separated form shown in the editor.
String formatKeywords(List<String> keywords) => keywords.join(', ');
