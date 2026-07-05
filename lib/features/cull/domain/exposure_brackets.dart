/// Heuristic exposure-bracket detection (`BUILD_PLAN.md` §8) — **no ML**.
/// Groups the consecutive frames of an exposure-bracket series (0 / +N /
/// −N EV interior-photography set) so the culler can rate/send only the normal
/// exposure and expand the pick to its siblings on export.
///
/// The detector is signal-agnostic: it groups on an *exposure signature* that
/// is the frame's EXIF exposure-bias (EV) when known, and otherwise the base-2
/// log of its shutter speed — which puts shutter on the same additive
/// stop-scale as EV. This matters because Fuji `.RAF` files don't expose an
/// exposure-bias tag to our reader, but their shutter still cycles per bracket,
/// and a shutter-priority bracket (constant aperture/ISO) *is* a shutter sweep.
/// (In practice the scan recovers the true `.RAF` bias from the embedded
/// preview's EXIF — see `folder_scanner.dart` — so the shutter path is the
/// safety net for raws whose preview has no EXIF.)
library;

import 'dart:math' as math;

/// A photo's identity for bracket grouping.
typedef BracketablePhoto = ({
  int id,
  DateTime? capturedAt,
  String? camera,
  double? exposureBias,
  double? exposureTime,
});

/// Two exposure signatures within this many stops are treated as the *same*
/// exposure — absorbs the rational rounding of third-stops (±0.08 EV) while
/// keeping real bracket steps (≥⅓ stop = 0.33) distinct.
const double _sigEpsilon = 0.15;

/// The exposure signature of [p] on an additive stop-scale, or null when the
/// frame carries neither an exposure bias nor a usable shutter speed.
double? _signature(BracketablePhoto p) {
  if (p.exposureBias != null) return p.exposureBias;
  final t = p.exposureTime;
  if (t != null && t > 0) return _log2(t);
  return null;
}

double _log2(double x) => math.log(x) / math.ln2;

/// Groups [photos] into exposure-bracket runs: consecutive frames (in capture
/// order) from the same camera whose exposure signature keeps changing and
/// whose capture times sit within a **shutter-aware** gap of each other.
///
/// The run closes when the next frame either repeats an exposure already in the
/// run (this splits back-to-back brackets `0,+3,−3,0,+3,−3` into two, and makes
/// a constant-exposure sequence — e.g. drone frames all at 0 EV — collapse to
/// singletons) or falls outside the gap. The gap tolerance grows with the
/// neighbouring shutter speeds because a long exposure (plus in-camera
/// long-exposure NR) can push the next frame 40 s+ later.
///
/// Frames without a usable signature or capture time can't be grouped, so each
/// becomes its own singleton (appended after the timed groups). Groups —
/// including singletons — are returned in capture order; callers treat length
/// ≥ 2 as a bracket (every run is built with epsilon-distinct signatures, so a
/// run of ≥ 2 always spans ≥ 2 exposures). Pure and deterministic.
List<List<int>> groupExposureBrackets(
  List<BracketablePhoto> photos, {
  Duration baseTolerance = const Duration(seconds: 15),
  double shutterFactor = 2.0,
}) {
  final eligible = [
    for (final p in photos)
      if (p.capturedAt != null && _signature(p) != null) p,
  ];

  // Partition by camera first: a second device shooting into the same window
  // (e.g. a drone mid-flight while the camera runs a long tripod bracket) must
  // not split or join a bracket. null camera is its own partition.
  final byCamera = <String?, List<BracketablePhoto>>{};
  for (final p in eligible) {
    byCamera.putIfAbsent(p.camera, () => []).add(p);
  }

  final groups = <List<int>>[];
  for (final partition in byCamera.values) {
    partition.sort((a, b) {
      final c = a.capturedAt!.compareTo(b.capturedAt!);
      return c != 0 ? c : a.id.compareTo(b.id);
    });

    List<int>? run;
    List<double>? runSigs;
    BracketablePhoto? prev;
    for (final p in partition) {
      final sig = _signature(p)!;
      final repeats =
          runSigs != null && runSigs.any((s) => (s - sig).abs() < _sigEpsilon);
      final gapOk =
          prev != null && _withinGap(prev, p, baseTolerance, shutterFactor);
      if (run == null || repeats || !gapOk) {
        run = [p.id];
        runSigs = [sig];
        groups.add(run);
      } else {
        run.add(p.id);
        runSigs!.add(sig);
      }
      prev = p;
    }
  }

  // Frames we can't place (no signature or no capture time): each on its own.
  for (final p in photos) {
    if (p.capturedAt == null || _signature(p) == null) groups.add([p.id]);
  }
  return groups;
}

bool _withinGap(
  BracketablePhoto prev,
  BracketablePhoto next,
  Duration baseTolerance,
  double shutterFactor,
) {
  final gap = next.capturedAt!.difference(prev.capturedAt!).abs();
  final maxShutter = math.max(prev.exposureTime ?? 0, next.exposureTime ?? 0);
  final allowed =
      baseTolerance +
      Duration(milliseconds: (maxShutter * shutterFactor * 1000).round());
  return gap <= allowed;
}

/// Indexed bracket grouping for the UI: which photos belong to a bracket (a run
/// of ≥ 2 frames), each frame's bracket size, the members of any frame's
/// bracket (for "expand selection"), and which frame is the **reference** (the
/// normal exposure the culler actually reviews — the one whose signature sits
/// nearest the middle of its bracket).
///
/// RAW+JPEG siblings are folded in *after* grouping: the grouping input must
/// exclude the hidden JPEG side (a duplicated exposure would trip the
/// repeat-boundary rule), then each sibling rejoins its RAW's bracket so
/// expanding a selection grabs both files. Siblings never become the reference
/// and don't count toward [sizeOf] (the badge shows the exposure count).
class BracketGroups {
  /// Builds the index from [photos] (already excluding hidden JPEG siblings),
  /// with [siblings] mapping a member id to the ids to fold back into its
  /// bracket.
  factory BracketGroups(
    List<BracketablePhoto> photos, {
    Map<int, List<int>> siblings = const {},
  }) {
    final groups = groupExposureBrackets(photos);
    final byId = {for (final p in photos) p.id: p};

    final memberIds = <int>{};
    final referenceIds = <int>{};
    final groupById = <int, List<int>>{};
    final sizeById = <int, int>{};
    var bracketCount = 0;

    for (final group in groups) {
      if (group.length < 2) continue;
      bracketCount++;
      // Fold each primary member's siblings into the bracket's membership.
      final full = <int>[
        for (final id in group) ...[id, ...?siblings[id]],
      ];
      final reference = _referenceOf(group, byId);
      for (final id in full) {
        memberIds.add(id);
        groupById[id] = full;
        sizeById[id] = group.length; // exposure count, siblings excluded
      }
      referenceIds.add(reference);
    }

    return BracketGroups._(
      groups,
      memberIds,
      referenceIds,
      groupById,
      sizeById,
      bracketCount,
    );
  }

  BracketGroups._(
    this.groups,
    this.memberIds,
    this.referenceIds,
    this._groupById,
    this._sizeById,
    this.bracketCount,
  );

  /// All groups, including singletons, in capture order (primary ids only —
  /// siblings are not laid out separately).
  final List<List<int>> groups;

  /// Ids of every frame that belongs to a bracket (incl. folded siblings).
  final Set<int> memberIds;

  /// Ids of the reference (normal-exposure) frame of each bracket.
  final Set<int> referenceIds;

  final Map<int, List<int>> _groupById;
  final Map<int, int> _sizeById;

  /// Number of brackets (groups of ≥ 2 exposures).
  final int bracketCount;

  /// The exposure count of [id]'s bracket (1 when it stands alone). Folded
  /// siblings report their bracket's exposure count, not the inflated total.
  int sizeOf(int id) => _sizeById[id] ?? 1;

  /// The ids in [id]'s bracket incl. siblings (just `[id]` when it stands
  /// alone) — the set "expand selection to bracket" unions.
  List<int> groupOf(int id) => _groupById[id] ?? [id];

  /// Whether [id] is the reference (normal-exposure) frame of a bracket.
  bool isReference(int id) => referenceIds.contains(id);

  /// The ids of bracket members that are *not* the reference frame — the frames
  /// the "collapse brackets" filter hides so the grid shows one cell per
  /// bracket. Siblings of a hidden member are hidden too.
  Set<int> get collapsedHiddenIds => {
    for (final id in memberIds)
      if (!referenceIds.contains(id)) id,
  };
}

/// The reference frame of [group]: the member whose exposure signature is
/// nearest the middle of the bracket (median signature), ties broken by earlier
/// capture then lower id — for a symmetric 0/+N/−N set this is the 0 EV frame,
/// and for a shutter-only bracket it is the middle shutter (the normal shot).
int _referenceOf(List<int> group, Map<int, BracketablePhoto> byId) {
  final sigs = [for (final id in group) _signature(byId[id]!)!]..sort();
  final median = sigs[sigs.length ~/ 2];
  int? best;
  var bestDist = double.infinity;
  DateTime? bestAt;
  for (final id in group) {
    final p = byId[id]!;
    final dist = (_signature(p)! - median).abs();
    if (best == null ||
        dist < bestDist - 1e-9 ||
        (dist <= bestDist + 1e-9 &&
            (p.capturedAt!.isBefore(bestAt!) ||
                (p.capturedAt!.isAtSameMomentAs(bestAt) && id < best)))) {
      best = id;
      bestDist = dist;
      bestAt = p.capturedAt;
    }
  }
  return best!;
}
