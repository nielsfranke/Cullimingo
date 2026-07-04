// Pure EXIF-orientation math for the editable-rotate feature.
//
// EXIF orientation is one of 8 states (1–8): four pure rotations and their
// mirrored twins. Cullimingo's rotate only ever applies 90° steps, but the
// helpers below compose correctly through the mirrored states too, so a
// mirrored original still rotates sensibly.

// Clockwise-rotation successor for each orientation: `_rotateCwOnce[o]` is the
// EXIF orientation after turning `o` 90° clockwise. Index 0 is unused.
const List<int> _rotateCwOnce = [
  0, // unused
  6, // 1 normal        → 6 rotated 90° CW
  7, // 2 mirrored      → 7 mirrored 90° CW
  8, // 3 rotated 180°  → 8 rotated 90° CCW
  5, // 4 mirrored 180° → 5 mirrored 90° CCW
  2, // 5 mirrored 90CCW→ 2 mirrored
  3, // 6 rotated 90CW  → 3 rotated 180°
  4, // 7 mirrored 90CW → 4 mirrored 180°
  1, // 8 rotated 90CCW → 1 normal
];

/// Returns the EXIF orientation after applying [quarterTurnsCW] clockwise
/// 90°-turns to [exif] (negative or >3 values wrap). Falls back to treating an
/// out-of-range [exif] as `1` (normal). Used to compose the file orientation
/// with the user's rotation for the interop write + inspector readout.
int rotateOrientation(int exif, int quarterTurnsCW) {
  var o = (exif >= 1 && exif <= 8) ? exif : 1;
  final turns = ((quarterTurnsCW % 4) + 4) % 4;
  for (var i = 0; i < turns; i++) {
    o = _rotateCwOnce[o];
  }
  return o;
}

/// Normalises a quarter-turn count to the 0–3 range (handles negatives from a
/// counter-clockwise turn). The value stored in `photos.userRotation`.
int normalizeQuarterTurns(int quarterTurnsCW) => ((quarterTurnsCW % 4) + 4) % 4;
