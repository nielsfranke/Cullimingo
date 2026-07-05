import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/features/export/domain/export_preset.dart';
import 'package:cullimingo/features/ingest/domain/rename_template.dart';
import 'package:cullimingo/features/metadata/domain/xmp_data.dart';
import 'package:path/path.dart' as p;

/// One photo to export, resolved enough to name its output.
class ExportSource {
  /// Creates an export source.
  const ExportSource({
    required this.path,
    required this.capturedAt,
    required this.originalName,
    this.camera,
    this.meta,
    this.userRotation = 0,
  });

  /// Absolute source path (RAW or bitmap).
  final String path;

  /// Capture time driving the template's date/time tokens (EXIF, else mtime).
  final DateTime capturedAt;

  /// The source file's basename **with** extension.
  final String originalName;

  /// Camera make/model for the `{camera}` token, when known.
  final String? camera;

  /// The marks + IPTC to embed in the exported JPEG (as XMP + legacy IIM), or
  /// null to write no metadata.
  final XmpData? meta;

  /// The user's extra clockwise quarter-turns (0–3), baked into the export
  /// pixels so proofs match the app.
  final int userRotation;
}

/// A planned export: read [source], render and write to [relPath] under the
/// destination root. [isRaw] picks the embedded-preview path vs a plain decode.
class ExportItem {
  /// Creates a plan item.
  const ExportItem({
    required this.source,
    required this.relPath,
    required this.isRaw,
    this.meta,
    this.userRotation = 0,
  });

  /// Absolute source path.
  final String source;

  /// Destination-relative output path (always with the preset's extension).
  final String relPath;

  /// Whether the source is a RAW file (embedded JPEG preview is extracted).
  final bool isRaw;

  /// Marks + IPTC to embed in the output JPEG (from the source), or null.
  final XmpData? meta;

  /// The user's extra clockwise quarter-turns (0–3), baked into the export.
  final int userRotation;
}

/// Builds the export plan for [sources] under [preset] (`BUILD_PLAN.md` §6).
/// Pure: orders by capture time then path (stable, matching the grid), assigns
/// the `{seq}` token, forces the output extension to the preset's format, and
/// de-duplicates output paths with `_2`, `_3`, … so two sources never collide.
///
/// [perSourceDir] scopes that de-duplication to each source's own directory —
/// for the "same folder as originals" export, where two identically-named
/// files in *different* folders land in different destinations and so never
/// actually collide. Left false (the default) they share one destination root,
/// so any name clash is de-duped globally.
List<ExportItem> buildExportPlan(
  List<ExportSource> sources,
  ExportPreset preset, {
  bool perSourceDir = false,
}) {
  final ordered = [...sources]
    ..sort((a, b) {
      final byTime = a.capturedAt.compareTo(b.capturedAt);
      return byTime != 0 ? byTime : a.path.compareTo(b.path);
    });

  // One taken-name bucket per destination folder. A shared root is a single
  // bucket (key ''); next-to-originals buckets by the source's directory.
  final takenByBucket = <String, Set<String>>{};
  final items = <ExportItem>[];
  var sequence = 1;
  for (final source in ordered) {
    final templated = preset.template.pathFor(
      RenameInput(
        capturedAt: source.capturedAt,
        originalName: source.originalName,
        sequence: sequence,
        camera: source.camera,
        shoot: preset.shoot,
      ),
    );
    final bucket = perSourceDir ? p.dirname(source.path) : '';
    final taken = takenByBucket.putIfAbsent(bucket, () => <String>{});
    final relPath = _dedupe(
      p.setExtension(templated, '.${preset.format.extension}'),
      taken,
    );
    items.add(
      ExportItem(
        source: source.path,
        relPath: relPath,
        isRaw: isRawPath(source.path),
        meta: source.meta,
        userRotation: source.userRotation,
      ),
    );
    sequence++;
  }
  return items;
}

/// Returns [relPath] (or `name_2.ext`, `name_3.ext`, …) such that its
/// lower-cased form isn't already in [taken], and records it.
String _dedupe(String relPath, Set<String> taken) {
  if (taken.add(relPath.toLowerCase())) return relPath;
  final dir = p.dirname(relPath);
  final stem = p.basenameWithoutExtension(relPath);
  final ext = p.extension(relPath);
  for (var n = 2; ; n++) {
    final candidate = p.join(dir == '.' ? '' : dir, '${stem}_$n$ext');
    if (taken.add(candidate.toLowerCase())) return candidate;
  }
}
