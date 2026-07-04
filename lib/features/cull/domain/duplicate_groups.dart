/// Heuristic duplicate/burst grouping (`BUILD_PLAN.md` §8) — **no ML**. Groups
/// photos shot in rapid succession (same camera, capture times within a small
/// gap) so the user can pick the keeper from a burst.
library;

/// A photo's identity for grouping: its id, capture time and camera.
typedef GroupablePhoto = ({int id, DateTime? capturedAt, String? camera});

/// Groups [photos] into capture-time **bursts**: consecutive shots (in capture
/// order) from the same camera taken within [maxGap] of the previous one.
///
/// Photos with no capture time can't be time-grouped, so each becomes its own
/// singleton group (appended after the timed groups). Groups — including
/// singletons — are returned in capture order; callers treat size ≥ 2 as a
/// burst. Pure and deterministic (ties broken by id).
List<List<int>> groupByCaptureTime(
  List<GroupablePhoto> photos, {
  Duration maxGap = const Duration(seconds: 2),
}) {
  final timed =
      [
        for (final p in photos)
          if (p.capturedAt != null) p,
      ]..sort((a, b) {
        final c = a.capturedAt!.compareTo(b.capturedAt!);
        return c != 0 ? c : a.id.compareTo(b.id);
      });

  final groups = <List<int>>[];
  GroupablePhoto? prev;
  for (final p in timed) {
    final continues =
        prev != null &&
        prev.camera == p.camera &&
        p.capturedAt!.difference(prev.capturedAt!).abs() <= maxGap;
    if (continues) {
      groups.last.add(p.id);
    } else {
      groups.add([p.id]);
    }
    prev = p;
  }

  // Undated photos: each on its own (can't be assigned to a burst).
  for (final p in photos) {
    if (p.capturedAt == null) groups.add([p.id]);
  }
  return groups;
}

/// Indexed burst grouping for the UI: which photos belong to a burst (group of
/// ≥ 2), each photo's group size, and the members of any photo's group (for
/// "compare this burst").
class BurstGroups {
  /// Indexes [groups] (as returned by [groupByCaptureTime]).
  BurstGroups(this.groups)
    : memberIds = {
        for (final g in groups)
          if (g.length >= 2) ...g,
      },
      _groupById = {
        for (final g in groups)
          for (final id in g) id: g,
      },
      _indexById = _buildIndex(groups);

  static Map<int, int> _buildIndex(List<List<int>> groups) {
    final map = <int, int>{};
    var index = 0;
    for (final g in groups) {
      if (g.length < 2) continue;
      for (final id in g) {
        map[id] = index;
      }
      index++;
    }
    return map;
  }

  /// All groups, including singletons, in capture order.
  final List<List<int>> groups;

  /// Ids of photos that are part of a burst (their group has ≥ 2 photos).
  final Set<int> memberIds;

  final Map<int, List<int>> _groupById;
  final Map<int, int> _indexById;

  /// Number of bursts (groups with ≥ 2 photos).
  int get burstCount => groups.where((g) => g.length >= 2).length;

  /// The size of [id]'s group (1 when it stands alone).
  int sizeOf(int id) => _groupById[id]?.length ?? 1;

  /// The running index of [id]'s burst among the bursts (0-based), or null when
  /// [id] stands alone. Adjacent bursts get consecutive indices, so cycling a
  /// colour palette by this index keeps neighbours visually distinct.
  int? groupIndexOf(int id) => _indexById[id];

  /// The ids in [id]'s group (just `[id]` when it stands alone).
  List<int> groupOf(int id) => _groupById[id] ?? [id];
}

/// Lays the members of multi-photo [groups] out **contiguously** — each group's
/// members together, groups in their existing order — resolving ids via [byId]
/// and keeping only items that pass [keep]. Singletons (groups of 1) are
/// dropped. Used by the grid's "Bursts/Similar" filter so grouped photos sit
/// next to each other.
List<T> groupContiguous<T>(
  List<List<int>> groups,
  Map<int, T> byId,
  bool Function(T) keep,
) => [
  for (final group in groups)
    if (group.length >= 2)
      for (final id in group)
        if (byId[id] case final item? when keep(item)) item,
];
