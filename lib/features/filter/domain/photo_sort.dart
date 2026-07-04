import 'package:cullimingo/core/db/database.dart';
import 'package:path/path.dart' as p;

/// Which field the cull grid is ordered by (`BUILD_PLAN.md` §7 top-bar sort).
/// The set is limited to columns the `Photos` table already stores, so no
/// ingest change is needed — file size / ISO / has-crop etc. (which Photo
/// Mechanic also offers) would each need a new column and are left for later.
enum PhotoSortKey {
  /// EXIF capture time (`capturedAt`). The default, and the original fixed
  /// grid order.
  captureTime('Capture Time'),

  /// Filesystem modification time (`mtime`).
  modificationTime('Modification Time'),

  /// File name (basename), compared naturally so `IMG_2` sorts before `IMG_10`.
  filename('Filename'),

  /// Star rating (0–5).
  rating('Rating'),

  /// Colour label.
  colorClass('Color Class'),

  /// Camera model.
  camera('Camera'),

  /// Lens model.
  lens('Lens'),

  /// Pixel width.
  width('Width'),

  /// Pixel height.
  height('Height');

  const PhotoSortKey(this.label);

  /// Human label shown in the sort menu.
  final String label;
}

/// The cull grid's sort order: a [key] and a direction. Defaults to capture
/// time ascending, which reproduces the original fixed DB order.
///
/// Photos missing the sort value (e.g. no EXIF capture time, no camera) always
/// sort to the **end**, in both directions — flipping the direction shouldn't
/// bubble "unknown" frames to the top. Ties fall back to capture time, then
/// file name, then id, so the order is always deterministic.
class PhotoSort {
  /// Creates a sort. Defaults to capture time ascending.
  const PhotoSort({
    this.key = PhotoSortKey.captureTime,
    this.ascending = true,
  });

  /// The field to order by.
  final PhotoSortKey key;

  /// Ascending when true, descending when false.
  final bool ascending;

  /// Whether this is the default order (capture time ascending) — the grid can
  /// then skip re-sorting and keep the DB's order.
  bool get isDefault => key == PhotoSortKey.captureTime && ascending;

  /// Returns a copy ordered by [key] (keeping the direction).
  PhotoSort withKey(PhotoSortKey key) =>
      PhotoSort(key: key, ascending: ascending);

  /// Returns a copy with the direction flipped.
  PhotoSort toggled() => PhotoSort(key: key, ascending: !ascending);

  /// Returns [photos] ordered by this key/direction (a new list; the input is
  /// left untouched).
  List<Photo> sort(List<Photo> photos) => [...photos]..sort(_compare);

  int _compare(Photo a, Photo b) {
    // Missing values sink to the end regardless of direction.
    final aMissing = _isMissing(a);
    final bMissing = _isMissing(b);
    if (aMissing != bMissing) return aMissing ? 1 : -1;

    final primary = aMissing ? 0 : _compareKey(a, b);
    final signed = ascending ? primary : -primary;
    if (signed != 0) return signed;
    return _tiebreak(a, b);
  }

  bool _isMissing(Photo photo) => switch (key) {
    PhotoSortKey.captureTime => photo.capturedAt == null,
    PhotoSortKey.camera => (photo.camera ?? '').isEmpty,
    PhotoSortKey.lens => (photo.lens ?? '').isEmpty,
    PhotoSortKey.width => photo.width == null,
    PhotoSortKey.height => photo.height == null,
    // mtime / rating / colour / filename always have a value.
    _ => false,
  };

  int _compareKey(Photo a, Photo b) => switch (key) {
    PhotoSortKey.captureTime => a.capturedAt!.compareTo(b.capturedAt!),
    PhotoSortKey.modificationTime => a.mtime.compareTo(b.mtime),
    PhotoSortKey.filename => _compareFilename(a.path, b.path),
    PhotoSortKey.rating => a.rating.compareTo(b.rating),
    PhotoSortKey.colorClass => a.colorLabel.index.compareTo(b.colorLabel.index),
    PhotoSortKey.camera => a.camera!.toLowerCase().compareTo(
      b.camera!.toLowerCase(),
    ),
    PhotoSortKey.lens => a.lens!.toLowerCase().compareTo(b.lens!.toLowerCase()),
    PhotoSortKey.width => a.width!.compareTo(b.width!),
    PhotoSortKey.height => a.height!.compareTo(b.height!),
  };

  // Deterministic, always-ascending tiebreak so equal keys never reorder
  // arbitrarily between rebuilds.
  int _tiebreak(Photo a, Photo b) {
    final byDate = switch ((a.capturedAt, b.capturedAt)) {
      (final da?, final db?) => da.compareTo(db),
      (null, null) => 0,
      (null, _) => 1,
      (_, null) => -1,
    };
    if (byDate != 0) return byDate;
    final byName = _compareFilename(a.path, b.path);
    if (byName != 0) return byName;
    return a.id.compareTo(b.id);
  }
}

int _compareFilename(String pathA, String pathB) => _naturalCompare(
  p.basename(pathA).toLowerCase(),
  p.basename(pathB).toLowerCase(),
);

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

/// Compares two strings "naturally": runs of digits compare by numeric value,
/// so `img2` < `img10` and `img09` == `img9` in magnitude (`img9` wins on the
/// shorter raw run only as a final tiebreak). Everything else is code-unit
/// order on the already-lower-cased input.
int _naturalCompare(String a, String b) {
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    final ca = a.codeUnitAt(i);
    final cb = b.codeUnitAt(j);
    if (_isDigit(ca) && _isDigit(cb)) {
      final startA = i;
      final startB = j;
      while (i < a.length && _isDigit(a.codeUnitAt(i))) {
        i++;
      }
      while (j < b.length && _isDigit(b.codeUnitAt(j))) {
        j++;
      }
      final numA = a.substring(startA, i);
      final numB = b.substring(startB, j);
      final trimA = numA.replaceFirst(RegExp(r'^0+(?=\d)'), '');
      final trimB = numB.replaceFirst(RegExp(r'^0+(?=\d)'), '');
      // Longer digit string ⇒ larger number (both have no significant leading
      // zeros after trimming).
      if (trimA.length != trimB.length) return trimA.length - trimB.length;
      final byValue = trimA.compareTo(trimB);
      if (byValue != 0) return byValue;
      // Equal value: fewer raw digits (fewer leading zeros) sorts first.
      if (numA.length != numB.length) return numA.length - numB.length;
    } else {
      if (ca != cb) return ca - cb;
      i++;
      j++;
    }
  }
  return (a.length - i) - (b.length - j);
}
