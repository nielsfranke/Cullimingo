import 'dart:io';

import 'package:path/path.dart' as p;

/// A mounted volume that could be an ingest source (`BUILD_PLAN.md` Phase 3).
class Volume {
  /// Creates a volume record.
  const Volume({required this.path, required this.name, required this.hasDcim});

  /// Absolute mount path (e.g. `/Volumes/UNTITLED`).
  final String path;

  /// Display name (the mount's basename).
  final String name;

  /// Whether the volume has a top-level `DCIM` folder — a strong hint it's a
  /// camera card, used to auto-select the source.
  final bool hasDcim;
}

/// Lists mounted volumes that could be an ingest source: on macOS the entries
/// under `/Volumes`, on Linux the per-user mount roots (`/media/$USER`,
/// `/run/media/$USER`) and `/mnt`. Pass [searchRoots] in tests.
///
/// Top-level listing only (cheap) and fully synchronous, so callers that
/// poll this every few seconds (`cull_page.workspace.dart`) must run it via
/// `Isolate.run` rather than awaiting it directly — a failing card reader can
/// make even this "cheap" listing block for a long time, and a synchronous
/// call can't be raced against a timeout on the same isolate.
/// Returns volumes sorted with likely camera cards (those with `DCIM`) first.
Future<List<Volume>> listVolumes({List<String>? searchRoots}) async {
  final roots = searchRoots ?? _platformRoots();
  final volumes = <Volume>[];

  for (final root in roots) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync()) {
      final stat = entity.statSync();
      if (stat.type != FileSystemEntityType.directory) continue;
      // Never offer the macOS system/boot volume as a source — ingesting from
      // (and scanning) the whole startup disk makes no sense and can OOM.
      if (_isSystemVolume(entity.path)) continue;
      volumes.add(
        Volume(
          path: entity.path,
          name: p.basename(entity.path),
          hasDcim: _hasDcim(entity.path),
        ),
      );
    }
  }

  volumes.sort((a, b) {
    if (a.hasDcim != b.hasDcim) return a.hasDcim ? -1 : 1; // cards first
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return volumes;
}

/// The camera cards (volumes with `DCIM`) in [current] whose path isn't in
/// [seenPaths] — i.e. newly inserted since the last poll. Pure, for testing the
/// auto-detect diff without timing.
List<Volume> newCards(Set<String> seenPaths, List<Volume> current) => [
  for (final v in current)
    if (v.hasDcim && !seenPaths.contains(v.path)) v,
];

List<String> _platformRoots() {
  if (Platform.isMacOS) return const ['/Volumes'];
  if (Platform.isLinux) {
    final user = Platform.environment['USER'] ?? '';
    return [
      if (user.isNotEmpty) '/media/$user',
      if (user.isNotEmpty) '/run/media/$user',
      '/media',
      '/mnt',
    ];
  }
  return const [];
}

// The macOS startup volume carries the OS here; a card/external drive never
// does. Used to keep "Macintosh HD" out of the source list.
bool _isSystemVolume(String volumePath) => File(
  p.join(
    volumePath,
    'System',
    'Library',
    'CoreServices',
    'SystemVersion.plist',
  ),
).existsSync();

bool _hasDcim(String volumePath) {
  final dir = Directory(volumePath);
  try {
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is Directory &&
          p.basename(entity.path).toUpperCase() == 'DCIM') {
        return true;
      }
    }
  } on Object {
    // Unreadable mount (permissions / ejected mid-scan) — just not a card.
  }
  return false;
}
