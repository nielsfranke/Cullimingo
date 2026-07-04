import 'package:cullimingo/features/ingest/domain/rename_template.dart';

/// Output container for an export (`BUILD_PLAN.md` §6). JPEG encodes via the
/// `image` package (with the proven XMP/IIM byte splicing); WebP and AVIF
/// encode via the bundled libvips and are offered only when it loads.
enum ExportFormat {
  /// Baseline JPEG.
  jpeg,

  /// WebP (libvips).
  webp,

  /// AVIF — AV1 in a HEIF container (libvips).
  avif;

  /// Lower-case file extension (no dot).
  String get extension => switch (this) {
    ExportFormat.jpeg => 'jpg',
    ExportFormat.webp => 'webp',
    ExportFormat.avif => 'avif',
  };

  /// Dropdown label.
  String get label => switch (this) {
    ExportFormat.jpeg => 'JPEG',
    ExportFormat.webp => 'WebP',
    ExportFormat.avif => 'AVIF',
  };
}

/// A reusable set of export settings: output size, quality, sharpening, the
/// filename template and the container (`BUILD_PLAN.md` §6). Defaults match the
/// DoD spot-check (2048 px long edge, Q85 JPEG).
class ExportPreset {
  /// Creates a preset.
  const ExportPreset({
    this.longEdge = 2048,
    this.quality = 85,
    this.format = ExportFormat.jpeg,
    this.sharpen = false,
    this.maxBytes,
    this.template = RenameTemplate.keepNames,
    this.shoot = '',
  });

  /// Target long-edge length in pixels. The source is never upscaled.
  final int longEdge;

  /// JPEG quality, 1–100.
  final int quality;

  /// Output container.
  final ExportFormat format;

  /// Apply a mild sharpen after downscaling (recommended for web proofs).
  final bool sharpen;

  /// Optional target maximum output size in bytes. When set, quality is stepped
  /// down until the JPEG fits (or a quality floor is reached). Null = off.
  final int? maxBytes;

  /// Output filename template (the Phase 3 engine; the source extension it
  /// appends is replaced with [format]'s extension).
  final RenameTemplate template;

  /// Shoot name for the template's `{shoot}` token.
  final String shoot;

  /// Returns a copy with the given fields replaced. [maxBytes] takes a thunk so
  /// passing `() => null` clears the file-size limit (vs leaving it untouched).
  ExportPreset copyWith({
    int? longEdge,
    int? quality,
    ExportFormat? format,
    bool? sharpen,
    int? Function()? maxBytes,
    RenameTemplate? template,
    String? shoot,
  }) => ExportPreset(
    longEdge: longEdge ?? this.longEdge,
    quality: quality ?? this.quality,
    format: format ?? this.format,
    sharpen: sharpen ?? this.sharpen,
    maxBytes: maxBytes != null ? maxBytes() : this.maxBytes,
    template: template ?? this.template,
    shoot: shoot ?? this.shoot,
  );
}
