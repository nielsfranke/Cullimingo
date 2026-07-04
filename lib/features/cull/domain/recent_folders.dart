/// How many recently-opened folders the "Open recent" menu remembers.
const int kMaxRecentFolders = 12;

/// Returns [current] with [added] promoted to the front: most-recent-first, no
/// duplicates (a re-opened folder moves up rather than repeating), capped at
/// [max]. A blank [added] leaves the list untouched.
List<String> promoteRecentFolder(
  List<String> current,
  String added, {
  int max = kMaxRecentFolders,
}) {
  if (added.isEmpty) return current;
  return [
    added,
    for (final path in current)
      if (path != added) path,
  ].take(max).toList();
}
