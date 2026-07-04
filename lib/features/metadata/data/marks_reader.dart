import 'package:cullimingo/core/files/supported_files.dart';
import 'package:cullimingo/features/metadata/data/embedded_xmp.dart';
import 'package:cullimingo/features/metadata/data/iptc_iim_reader.dart';
import 'package:cullimingo/features/metadata/data/xmp_sidecar.dart';
import 'package:cullimingo/features/metadata/domain/xmp_data.dart';

/// Reads a photo's external marks the way Capture One / Lightroom store them,
/// in priority order:
///   1. a `.xmp` sidecar (the RAW convention, our own write target);
///   2. the modern XMP packet embedded in the image (how C1/LR write exported
///      JPEG/HEIC/TIFF);
///   3. the legacy IPTC IIM (APP13 `8BIM`/`0x0404`) block — what Photo
///      Mechanic, cameras and older wire systems write, often without XMP.
///
/// XMP is authoritative: when both XMP and IIM are present (common in Photo
/// Mechanic exports, which write both), the IIM block is ignored entirely.
/// Returns `null` when none is present. Call off the UI isolate — the embedded
/// paths read file bytes.
Future<XmpData?> readMarks(String photoPath) async {
  final sidecar = await readSidecar(photoPath);
  if (sidecar != null) return sidecar;
  if (!carriesEmbeddedXmp(photoPath)) return null;
  final embeddedXmp = await readEmbeddedXmp(photoPath);
  if (embeddedXmp != null) return embeddedXmp;
  return readEmbeddedIim(photoPath);
}

/// A photo's external marks together with its sidecar mtime — read in one pass
/// so the import metadata pass can batch both into a single DB write.
typedef MarksRead = (XmpData? xmp, DateTime? sidecarMtime);

/// Reads marks + sidecar mtime for every path in [paths] — a background-isolate
/// entry point (run via `Isolate.run`) so the file I/O and XMP parsing never
/// touch the UI isolate (`BUILD_PLAN.md` §2). Reads run with bounded
/// concurrency so a big import's I/O overlaps instead of going file-by-file.
Future<List<MarksRead>> readMarksForPaths(List<String> paths) async {
  final results = List<MarksRead>.filled(paths.length, (null, null));
  const concurrency = 16;
  for (var start = 0; start < paths.length; start += concurrency) {
    final end = (start + concurrency).clamp(0, paths.length);
    await Future.wait([
      for (var i = start; i < end; i++)
        Future(() async {
          final xmp = await readMarks(paths[i]);
          if (xmp == null) return;
          results[i] = (xmp, await readSidecarMtime(paths[i]));
        }),
    ]);
  }
  return results;
}

/// One photo to scan during a disk sync: its sidecar `path` and the sidecar
/// mtime we last recorded (`knownMtime`, whole seconds), so the isolate can
/// skip re-parsing sidecars that haven't moved since our own write.
typedef SidecarSyncQuery = (String path, DateTime? knownMtime);

/// Per-photo result of a disk sync scan: the sidecar's current mtime and, when
/// it changed since the query's `knownMtime`, the freshly parsed marks.
/// `xmp` is null when the sidecar is missing, unchanged, or unparseable — the
/// caller treats all three as "nothing to adopt".
typedef SidecarSyncState = (DateTime? fileMtime, XmpData? xmp);

/// Reads current sidecar mtime + (when changed) parsed marks for every query in
/// [queries] — a background-isolate entry point (run via `compute`) so the file
/// I/O and XMP parsing never touch the UI isolate (`BUILD_PLAN.md` §2). Bounded
/// concurrency mirrors [readMarksForPaths].
Future<List<SidecarSyncState>> readSidecarSyncStates(
  List<SidecarSyncQuery> queries,
) async {
  final results = List<SidecarSyncState>.filled(queries.length, (null, null));
  const concurrency = 16;
  for (var start = 0; start < queries.length; start += concurrency) {
    final end = (start + concurrency).clamp(0, queries.length);
    await Future.wait([
      for (var i = start; i < end; i++)
        Future(() async {
          final (path, knownMtime) = queries[i];
          final fileMtime = await readSidecarMtime(path);
          if (fileMtime == null) return; // no sidecar on disk
          // Unchanged since our own last write → nothing to parse or adopt.
          if (knownMtime != null && fileMtime == knownMtime) {
            results[i] = (fileMtime, null);
            return;
          }
          results[i] = (fileMtime, await readSidecar(path));
        }),
    ]);
  }
  return results;
}
