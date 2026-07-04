import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Produces a small JPEG thumbnail for a photo file. Implementations must do
/// the heavy decode/resize off the UI isolate (`BUILD_PLAN.md` rule §0.6).
///
/// RAW files use their embedded preview (LibRaw); other formats are decoded
/// directly. Returns `null` when no preview could be produced.
// ignore: one_member_abstracts — deliberate seam with multiple implementations.
abstract interface class PreviewExtractor {
  /// Returns encoded JPEG bytes for [path], downscaled so the long edge is
  /// about [longEdge] px, or `null` on failure.
  ///
  /// If [cancel] is given and fires before the work starts, the implementation
  /// may skip it and return `null` (so the cells the user is actually looking
  /// at jump the queue — `BUILD_PLAN.md` §2).
  ///
  /// [priority] lets on-screen ([JobPriority.visible]) requests jump ahead of
  /// off-screen prefetch batches ([JobPriority.prefetch]) in implementations
  /// that queue work (the isolate pool).
  Future<Uint8List?> thumbnail(
    String path, {
    int longEdge,
    CancelToken? cancel,
    JobPriority priority,
  });
}

/// Relative urgency of a preview request. Cells the user is actually looking at
/// ([visible]) jump ahead of [prefetch] batches warming the cache off-screen,
/// so a fast scroll still fills the viewport first (`BUILD_PLAN.md` §2).
enum JobPriority {
  /// An on-screen cell / the loupe photo — serve first.
  visible,

  /// A cache warm-up for cells just outside the viewport — serve when idle.
  prefetch,
}

/// A one-shot cancellation flag. A caller cancels a request it no longer needs
/// — e.g. a cell that scrolled off-screen, or a superseded prefetch batch — so
/// the pool skips it and reaches the visible cells first (`BUILD_PLAN.md` §2).
class CancelToken {
  bool _cancelled = false;

  /// Whether the request has been cancelled.
  bool get isCancelled => _cancelled;

  /// Marks the request cancelled. Idempotent.
  void cancel() => _cancelled = true;
}

/// Lower-case RAW file extensions we route to the LibRaw path (no leading dot).
const Set<String> kRawExtensions = {
  'arw', 'sr2', 'srf', // Sony
  'cr2', 'cr3', 'crw', // Canon
  'nef', 'nrw', // Nikon
  'raf', // Fujifilm
  'rw2', // Panasonic
  'orf', // Olympus
  'pef', // Pentax
  'srw', // Samsung
  'dng', // Adobe / generic
  'raw', '3fr', 'iiq', 'erf', 'mef', 'mos', 'mrw', 'x3f',
};

/// Whether [path] looks like a RAW file based on its extension.
bool isRawPath(String path) {
  final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
  return kRawExtensions.contains(ext);
}
