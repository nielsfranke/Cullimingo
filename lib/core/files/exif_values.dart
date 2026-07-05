import 'package:exif/exif.dart';

/// The trimmed printable of [key], or null when absent/empty.
String? exifText(Map<String, IfdTag> tags, String key) {
  final s = tags[key]?.printable.trim();
  return (s == null || s.isEmpty) ? null : s;
}

/// Parses an EXIF numeric/ratio printable (`28/10`, `2.8`, `[400]`) to a
/// double; tolerant of brackets and comma-separated lists (takes the first).
double? exifNum(Map<String, IfdTag> tags, String key) {
  var s = tags[key]?.printable.trim();
  if (s == null || s.isEmpty) return null;
  s = s.replaceAll('[', '').replaceAll(']', '').trim();
  if (s.contains(',')) s = s.split(',').first.trim();
  final slash = s.indexOf('/');
  if (slash >= 0) {
    final n = double.tryParse(s.substring(0, slash).trim());
    final d = double.tryParse(s.substring(slash + 1).trim());
    if (n == null || d == null || d == 0) return null;
    return n / d;
  }
  return double.tryParse(s);
}
