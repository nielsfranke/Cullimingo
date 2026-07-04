import 'package:cullimingo/features/handoff/domain/cs_models.dart';

/// One row in the flattened gallery picker: a [gallery] plus its [depth] in the
/// tree (0 = top level), so the picker can indent sub-galleries. [hasChildren]
/// drives the collapse chevron.
class GalleryRow {
  /// Creates a flattened row.
  const GalleryRow(this.gallery, this.depth, {this.hasChildren = false});

  /// The gallery at this row.
  final CsGallery gallery;

  /// Nesting depth, 0 for a top-level gallery.
  final int depth;

  /// Whether this gallery has sub-galleries (so it can be collapsed).
  final bool hasChildren;
}

/// Flattens the nested gallery [tree] into a depth-first list of [GalleryRow]s,
/// each carrying its indent depth — so a flat list/dropdown can still show the
/// parent → child structure. Children follow their parent in order.
List<GalleryRow> flattenGalleryTree(List<CsGallery> tree, {int depth = 0}) {
  final rows = <GalleryRow>[];
  for (final g in tree) {
    rows.add(GalleryRow(g, depth, hasChildren: g.children.isNotEmpty));
    if (g.children.isNotEmpty) {
      rows.addAll(flattenGalleryTree(g.children, depth: depth + 1));
    }
  }
  return rows;
}

/// Like [flattenGalleryTree] but hides the descendants of any gallery whose id
/// is in [collapsedIds] — for a collapsible picker. The collapsed gallery
/// itself still shows (with its chevron), just not its children.
List<GalleryRow> visibleGalleryRows(
  List<CsGallery> tree,
  Set<String> collapsedIds, {
  int depth = 0,
}) {
  final rows = <GalleryRow>[];
  for (final g in tree) {
    rows.add(GalleryRow(g, depth, hasChildren: g.children.isNotEmpty));
    if (g.children.isNotEmpty && !collapsedIds.contains(g.id)) {
      rows.addAll(
        visibleGalleryRows(g.children, collapsedIds, depth: depth + 1),
      );
    }
  }
  return rows;
}

/// Filters the whole [tree] (depth-first, ignoring collapse) to galleries whose
/// name contains [query] case-insensitively — for the picker's search box.
/// Empty/blank query returns every row. Indent depth is preserved.
List<GalleryRow> searchGalleryRows(List<CsGallery> tree, String query) {
  final q = query.trim().toLowerCase();
  final all = flattenGalleryTree(tree);
  if (q.isEmpty) return all;
  return [
    for (final row in all)
      if (row.gallery.name.toLowerCase().contains(q)) row,
  ];
}

/// Resolves a gallery [coverImageUrl] against the server [baseUrl] into an
/// absolute URL. Absolute URLs (`http…`) are returned as-is; a server-relative
/// path (`/branding/…`) is prefixed with [baseUrl]. Null/empty → null.
String? resolveCoverUrl(String baseUrl, String? coverImageUrl) {
  final url = coverImageUrl?.trim();
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
  return url.startsWith('/') ? '$base$url' : '$base/$url';
}
