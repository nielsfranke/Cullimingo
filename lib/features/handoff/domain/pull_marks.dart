import 'package:cullimingo/features/filter/domain/filename_match.dart';
import 'package:cullimingo/features/handoff/domain/cs_models.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';

/// A client mark resolved to a local photo, ready to apply. [rating]/[color]
/// are null when the client left that axis untouched (so a pull never clobbers
/// the photographer's existing rating/colour with an empty value).
class PulledMark {
  /// Creates a resolved mark.
  const PulledMark({required this.photoId, this.rating, this.color});

  /// The local photo id this applies to.
  final int photoId;

  /// Client star rating (1–5), or null when unrated.
  final int? rating;

  /// Client colour label, or null when the client set no colour.
  final ColorLabel? color;
}

/// Maps a ContactSheet colour flag to a [ColorLabel], or null for `none`/
/// unknown. ContactSheet has no purple (clients only get 4 colours).
ColorLabel? csColorToLabel(String flag) => switch (flag) {
  'red' => ColorLabel.red,
  'yellow' => ColorLabel.yellow,
  'green' => ColorLabel.green,
  'blue' => ColorLabel.blue,
  _ => null,
};

/// Resolves client review [marks] against local [photos] (matched by filename,
/// extension-insensitive via [normalizeName] — so a JPEG proof's marks land on
/// the RAW). Emits one [PulledMark] per matched photo that carries any client
/// signal (a rating, a colour, or a like); photos the client left untouched are
/// skipped. Pure — the page applies the marks + selects the matched photos.
List<PulledMark> resolvePulledMarks(
  List<CsImageMark> marks,
  List<({int id, String path})> photos,
) {
  final idsByName = <String, List<int>>{};
  for (final photo in photos) {
    idsByName.putIfAbsent(normalizeName(photo.path), () => []).add(photo.id);
  }

  final resolved = <PulledMark>[];
  for (final mark in marks) {
    final rating = mark.rating > 0 ? mark.rating.clamp(1, 5) : null;
    final color = csColorToLabel(mark.colorFlag);
    final liked = mark.likes > 0;
    if (rating == null && color == null && !liked) continue;
    for (final id in idsByName[normalizeName(mark.filename)] ?? const <int>[]) {
      resolved.add(PulledMark(photoId: id, rating: rating, color: color));
    }
  }
  return resolved;
}
