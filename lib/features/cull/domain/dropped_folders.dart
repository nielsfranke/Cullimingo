import 'package:path/path.dart' as p;

/// Resolves filesystem [paths] dropped onto the window into the folder roots to
/// open in the grid, in drop order with duplicates removed.
///
/// A dropped directory opens itself; a dropped file opens its containing folder
/// (so dragging a photo in opens that photo's folder). [isDirectory] is
/// injected so the logic stays pure and testable — the UI passes a real
/// filesystem check.
List<String> droppedFoldersToOpen(
  Iterable<String> paths, {
  required bool Function(String path) isDirectory,
}) {
  final roots = <String>[];
  for (final path in paths) {
    if (path.isEmpty) continue;
    final root = isDirectory(path) ? path : p.dirname(path);
    if (!roots.contains(root)) roots.add(root);
  }
  return roots;
}
