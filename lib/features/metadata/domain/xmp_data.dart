import 'package:cullimingo/features/metadata/domain/crop_rect.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';

/// The cull marks that travel in an XMP sidecar. Rating + colour + keywords
/// round-trip with Capture One / Lightroom; the pick/reject flag does not (no
/// universal standard) and lives in a private namespace (`BUILD_PLAN.md` §6.3).
///
/// [iptc] carries the descriptive IPTC Core fields (caption, creator, credit,
/// location…) for the journalist captioning track (Phase 9, Layer 1); it is
/// empty for a plain cull.
class XmpData {
  /// Creates an XMP payload.
  const XmpData({
    this.rating = 0,
    this.color = ColorLabel.none,
    this.flag = PickFlag.none,
    this.keywords = const [],
    this.iptc = const IptcCore(),
    this.dateCreated,
    this.orientation,
    this.crop,
    this.stackId,
  });

  /// Star rating 0–5 (`xmp:Rating`).
  final int rating;

  /// Colour label (`xmp:Label`).
  final ColorLabel color;

  /// Pick/reject flag (private `cullimingo:flag`).
  final PickFlag flag;

  /// Keywords (`dc:subject` bag).
  final List<String> keywords;

  /// Descriptive IPTC Core fields (caption, creator, credit, location…).
  final IptcCore iptc;

  /// IPTC Date Created (`photoshop:DateCreated`, IIM 2:55/2:60) — the capture
  /// time from EXIF, written explicitly so date-sorting wire/DAM systems don't
  /// have to fall back to EXIF (`BUILD_PLAN.md` Phase 9 backlog). Derived, not
  /// user-edited; null = don't write it.
  final DateTime? dateCreated;

  /// Effective EXIF orientation (1–8) after the user's rotate, written as
  /// `tiff:Orientation` so Lightroom / Photo Mechanic pick up a rotation done
  /// here. Null (or 1) = don't write it; a normal photo needs no override.
  final int? orientation;

  /// Non-destructive Lightroom/Camera-Raw crop (`crs:`), when the source has
  /// one. Read-only — surfaced in the inspector + loupe, never written.
  final CropRect? crop;

  /// Manual exposure-bracket stack override (private `cullimingo:StackId`).
  /// Only the user's *manual* decisions travel in XMP (automatic detection
  /// re-runs on import): a non-empty id = manually stacked; the empty string =
  /// manually unstacked; null = no manual decision (don't write it).
  final String? stackId;
}
