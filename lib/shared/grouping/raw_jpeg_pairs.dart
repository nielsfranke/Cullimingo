import 'package:cullimingo/core/files/filename_match.dart';
import 'package:path/path.dart' as p;

/// RAW+JPEG pairing (`BUILD_PLAN.md` §8, Photo-Mechanic style) — **no ML, no
/// timestamps**: pairs are photos that share a normalized basename where *both*
/// a RAW and a non-RAW (JPEG/HEIF) variant exist on disk (e.g. `_AIV1234.ARW`
/// + `_AIV1234.JPG`). Lets the grid badge paired files and hide the JPEG side
/// while keeping its RAW partner.

/// A photo's identity for pairing: its id, path (for the basename key) and
/// whether it is a RAW file.
typedef PairablePhoto = ({int id, String path, bool isRaw});

/// Indexed RAW+JPEG pairing over a set of photos. A "pair" is a basename group
/// holding at least one RAW *and* at least one non-RAW image; groups that are
/// all-RAW or all-JPEG are not pairs (nothing to hide).
class RawJpegPairs {
  /// Builds the pairing index from [photos].
  factory RawJpegPairs(List<PairablePhoto> photos) {
    final byName = <String, List<PairablePhoto>>{};
    for (final photo in photos) {
      byName.putIfAbsent(normalizeName(photo.path), () => []).add(photo);
    }

    final paired = <int>{};
    final hiddenJpeg = <int>{};
    final groups = <int, Set<int>>{};
    var pairCount = 0;
    for (final group in byName.values) {
      final hasRaw = group.any((photo) => photo.isRaw);
      final hasJpeg = group.any((photo) => !photo.isRaw);
      if (!hasRaw || !hasJpeg) continue; // not a RAW+JPEG pair
      pairCount++;
      for (final photo in group) {
        paired.add(photo.id);
        if (!photo.isRaw) hiddenJpeg.add(photo.id);
        // Mark-sharing partners are the same-folder members only: two cards'
        // `DSC0001` in different subfolders are different shots.
        final dir = p.dirname(photo.path);
        groups[photo.id] = {
          for (final other in group)
            if (p.dirname(other.path) == dir) other.id,
        };
      }
    }
    return RawJpegPairs._(paired, hiddenJpeg, pairCount, groups);
  }

  RawJpegPairs._(
    this.pairedIds,
    this.hiddenJpegIds,
    this.pairCount,
    this._groups,
  );

  final Map<int, Set<int>> _groups;

  /// Ids of photos that have a RAW+JPEG partner (both sides of every pair).
  final Set<int> pairedIds;

  /// Ids of the non-RAW (JPEG/HEIF) side of a pair — hidden when the "hide
  /// JPEG" filter is on; the RAW partner stays visible.
  final Set<int> hiddenJpegIds;

  /// Number of RAW+JPEG pairs found.
  final int pairCount;

  /// Whether [id] is part of a RAW+JPEG pair.
  bool isPaired(int id) => pairedIds.contains(id);

  /// Whether [id] is the JPEG side that the "hide JPEG" filter would drop.
  bool isHiddenJpeg(int id) => hiddenJpegIds.contains(id);

  /// [id] and the other files of its pair in the same folder (RAW + JPEG/HEIF)
  /// — what a mark applies to when marks follow the pair. Just `{id}` for an
  /// unpaired photo.
  Set<int> groupOf(int id) => _groups[id] ?? {id};
}
