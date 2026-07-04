import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/files/supported_files.dart';
import 'package:path/path.dart' as p;

/// Normalises a filename/path for matching: basename without extension,
/// lower-cased. So `/cards/DSC_0001.ARW`, `DSC_0001.JPG` and `dsc_0001.jpeg`
/// all collapse to `dsc_0001` — letting a JPEG-named list select RAW files
/// (`BUILD_PLAN.md` §5).
String normalizeName(String pathOrName) =>
    p.basenameWithoutExtension(pathOrName.trim()).toLowerCase();

final RegExp _tokenSeparators = RegExp('[\\s,;|"\']+');
final RegExp _alphanumeric = RegExp('[a-z0-9]', caseSensitive: false);

bool _looksLikeName(String token) =>
    token.length >= 2 && _alphanumeric.hasMatch(token);

/// Splits free-form list text — a Picdrop / ContactSheet / Photo-Mechanic
/// export, a pasted column, or prose — into candidate filename tokens to match
/// against the library (`BUILD_PLAN.md` §5). Separators are whitespace, commas,
/// semicolons, pipes and quotes; path separators are left for [normalizeName].
///
/// Two-tier, so structured *and* bare lists both work:
///   1. If any token carries a known photo extension (`name.JPG`), only those
///      are returned — a clean list that ignores rating/comment columns.
///   2. Otherwise every alphanumeric token is a candidate, so a Photo-Mechanic
///      paste (`_AIV9551 _AIV9552`) or a ContactSheet "exclude extensions"
///      export still selects — matching RAWs too, since [normalizeName] drops
///      the extension on both sides.
///
/// Results are de-duplicated by normalised name, first occurrence kept.
List<String> parseNameTokens(String content) {
  final raw = content
      .split(_tokenSeparators)
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty);

  final withExt = raw.where(isSupportedPhoto).toList();
  final candidates = withExt.isNotEmpty
      ? withExt
      : raw.where(_looksLikeName).toList();

  final seen = <String>{};
  final tokens = <String>[];
  for (final token in candidates) {
    final norm = normalizeName(token);
    if (norm.isEmpty) continue;
    // Emit the basename (drop any leading path) for clean display; matching is
    // by [normalizeName] regardless.
    if (seen.add(norm)) tokens.add(p.basename(token));
  }
  return tokens;
}

/// Returns the ids of [photos] whose names match any in [names] (extension-,
/// case- and path-insensitive). A name that matches both a RAW and its JPEG
/// sibling selects both.
Set<int> matchPhotoIds(Iterable<String> names, List<Photo> photos) {
  final byName = <String, List<int>>{};
  for (final photo in photos) {
    byName.putIfAbsent(normalizeName(photo.path), () => []).add(photo.id);
  }

  final ids = <int>{};
  for (final name in names) {
    final hit = byName[normalizeName(name)];
    if (hit != null) ids.addAll(hit);
  }
  return ids;
}
