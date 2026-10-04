import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:cullimingo/core/files/posix_fs.dart';
import 'package:cullimingo/core/settings/app_settings.dart';
import 'package:path/path.dart' as p;

/// One file a run is about to copy: its `relPath` under each destination
/// root, and its `sizeBytes` (negative: unknown, read from `source`).
typedef PlannedCopy = ({String source, String relPath, int sizeBytes});

/// What [checkDestinationsSync] found.
class DestinationCheck {
  /// Creates a check result.
  const DestinationCheck({this.problems = const [], this.mounts = const {}});

  /// One human-readable line per failed check; empty when good to go.
  final List<String> problems;

  /// The folder each checked root lands in (the root itself, or its nearest
  /// existing ancestor when the run will create it) → that folder's current
  /// mount point. Pass to the run as its volume guards, so a drive that
  /// disappears mid-run isn't written "into" either.
  final Map<String, String> mounts;

  /// Whether every check passed.
  bool get ok => problems.isEmpty;
}

const String _notResponding =
    "The destination isn't responding (drive disconnected or network share "
    'hung?).';

/// Headroom kept free on a destination volume beyond what a run needs.
const int _minHeadroomBytes = 64 * 1024 * 1024;

/// Checks a run's destination [roots] before anything is copied.
///
/// - **A destination is a volume, not a path.** [rememberedMounts] maps a
///   root to the mount point its volume had when it was chosen. If the root
///   now resolves to a different one, its drive isn't there: an unplugged
///   drive leaves an empty mount-point folder (fstab/sshfs/rclone mounts on
///   Linux) or nothing at all, and copying "into" it wrote to the system
///   disk while the summary said "Copied & verified".
/// - **A missing root is never created** when [mustExist] is set: a root
///   that vanished is a drive that's gone, not a folder to make.
/// - **Enough free space**, per filesystem (two roots on one drive add up),
///   counting only files not already present at the destination.
///
/// - **Even with nothing remembered** (a destination picked before this
///   check existed), a root under a removable-media folder (`/Volumes` on
///   macOS, `/media` and `/run/media` on Linux) must sit on a volume mounted
///   *inside* that folder, and on Linux an `/etc/fstab` mount point holding
///   the root must be mounted ([unmountedDriveFor]).
///
/// Blocking I/O — use [checkDestinations], which runs this off the UI
/// isolate with a timeout. [probe], [resolveAnchor], [removableBases],
/// [fstab] and [mountInfo] are injectable for tests; by default they come
/// from the running system.
DestinationCheck checkDestinationsSync({
  required List<String> roots,
  required List<PlannedCopy> files,
  Map<String, String> rememberedMounts = const {},
  bool mustExist = true,
  VolumeInfo? Function(String path) probe = volumeInfo,
  String? Function(String root)? resolveAnchor,
  List<String>? removableBases,
  String? fstab,
  String? mountInfo,
}) {
  final anchorOf = resolveAnchor ?? _resolvedAnchor;
  final bases = removableBases ?? _platformRemovableBases();
  final fstabText = fstab ?? (Platform.isLinux ? _readFstab() : '');
  final mounted = linuxMountPoints(
    mountInfo ?? (Platform.isLinux ? readLinuxMountInfo() : ''),
  );
  final problems = <String>[];
  final mounts = <String, String>{};
  final needed = <String, int>{};
  final free = <String, int>{};
  int? sizeOf(PlannedCopy f) {
    if (f.sizeBytes >= 0) return f.sizeBytes;
    try {
      return File(f.source).lengthSync();
    } on FileSystemException {
      return null; // reported per file by the copy itself
    }
  }

  for (final root in roots) {
    final volume = probe(root);
    final remembered = rememberedMounts[root];
    if (volume != null &&
        remembered != null &&
        volume.mountPoint != remembered) {
      problems.add(
        "${p.basename(root)}: its drive isn't connected (expected at "
        '$remembered). Connect it — or choose the folder again if it moved.',
      );
      continue;
    }
    final expected = unmountedDriveFor(
      root,
      anchor: anchorOf(root),
      anchorMount: volume?.mountPoint,
      removableBases: bases,
      fstab: fstabText,
      mounted: mounted,
    );
    if (expected != null) {
      problems.add(
        "${p.basename(root)}: its drive isn't connected (expected at "
        '$expected). Connect it and try again.',
      );
      continue;
    }
    if (mustExist && !Directory(root).existsSync()) {
      problems.add(
        '${p.basename(root)}: folder not found ($root). Is its drive '
        'connected?',
      );
      continue;
    }
    if (volume == null) continue; // platform without volume info
    final anchor = nearestExistingDirectory(root);
    if (anchor != null) mounts[anchor] = volume.mountPoint;

    var need = 0;
    for (final f in files) {
      final dest = p.join(root, f.relPath);
      if (FileSystemEntity.typeSync(dest, followLinks: false) !=
          FileSystemEntityType.notFound) {
        continue; // already there: skipped or compared, never rewritten
      }
      need += sizeOf(f) ?? 0;
    }
    needed[volume.mountPoint] = (needed[volume.mountPoint] ?? 0) + need;
    free[volume.mountPoint] = volume.freeBytes;
  }

  for (final MapEntry(key: mount, value: need) in needed.entries) {
    if (need == 0) continue;
    final headroom = need ~/ 100 > _minHeadroomBytes
        ? need ~/ 100
        : _minHeadroomBytes;
    final available = free[mount]!;
    if (need + headroom > available) {
      problems.add(
        'Not enough space on $mount: needs ${formatBytes(need)}, '
        '${formatBytes(available)} free.',
      );
    }
  }
  return DestinationCheck(problems: problems, mounts: mounts);
}

/// Where [root]'s drive should be mounted when it plainly isn't, else null.
/// Needs no remembered volume, so it also guards destinations picked before
/// volumes were remembered. Pure: the caller supplies the system's state.
///
/// - **fstab** (Linux): a mount point in [fstab] that is [root] or one of its
///   ancestors but isn't among [mounted] — an fstab NAS share or USB drive
///   that's down leaves its mount point as a plain folder on the system disk.
///   `/mnt/...` destinations are judged by this rule only: `/mnt` is just as
///   often an ordinary folder. Skipped when [mounted] is empty (no mount
///   table to compare with — never guess).
/// - **Removable-media folders**: when [anchor] (the nearest existing folder
///   of [root], symlinks resolved) lies in one of [removableBases]
///   (`/Volumes`, `/media`, `/run/media`), its volume, [anchorMount], must be
///   mounted *inside* that base. A drive that's gone leaves the path
///   resolving to the folder above it — the system disk, or `/run`'s tmpfs —
///   which would otherwise be written into. A symlink out of the base (macOS'
///   `/Volumes/Macintosh HD` → `/`) resolves elsewhere and isn't judged.
String? unmountedDriveFor(
  String root, {
  required String? anchor,
  required String? anchorMount,
  required List<String> removableBases,
  required String fstab,
  required Set<String> mounted,
}) {
  if (mounted.isNotEmpty) {
    String? missing;
    for (final mountPoint in fstabMountPoints(fstab)) {
      final holdsRoot = root == mountPoint || p.isWithin(mountPoint, root);
      if (!holdsRoot || mounted.contains(mountPoint)) continue;
      if (missing == null || mountPoint.length > missing.length) {
        missing = mountPoint;
      }
    }
    if (missing != null) return missing;
  }

  if (anchor == null || anchorMount == null) return null;
  for (final base in removableBases) {
    if (anchor != base && !p.isWithin(base, anchor)) continue;
    if (p.isWithin(base, anchorMount)) return null; // its drive is there
    // Name the drive's folder: /Volumes/<name>, /media/<user>/<label>.
    final rel = p.isWithin(base, root)
        ? p.split(p.relative(root, from: base))
        : <String>[];
    final depth = base == '/Volumes' ? 1 : 2;
    return rel.isEmpty ? base : p.joinAll([base, ...rel.take(depth)]);
  }
  return null;
}

/// The mount points `/etc/fstab` text declares, other than `/` and swap.
List<String> fstabMountPoints(String fstab) => [
  for (final raw in fstab.split('\n'))
    if (raw.trim() case final line
        when line.isNotEmpty && !line.startsWith('#'))
      if (line.split(RegExp(r'\s+')) case final fields when fields.length >= 2)
        if (unescapeMountField(fields[1]) case final mountPoint
            when mountPoint.startsWith('/') &&
                mountPoint != '/' &&
                (fields.length < 3 || fields[2] != 'swap'))
          p.normalize(mountPoint),
];

List<String> _platformRemovableBases() {
  if (Platform.isMacOS) return const ['/Volumes'];
  if (Platform.isLinux) return const ['/media', '/run/media'];
  return const [];
}

String? _resolvedAnchor(String root) {
  final anchor = nearestExistingDirectory(root);
  if (anchor == null) return null;
  try {
    return Directory(anchor).resolveSymbolicLinksSync();
  } on FileSystemException {
    return null;
  }
}

String _readFstab() {
  try {
    return File('/etc/fstab').readAsStringSync();
  } on FileSystemException {
    return '';
  }
}

/// [checkDestinationsSync] off the UI isolate. A volume that doesn't answer
/// within [timeout] (a hung network share) is a problem too, not a freeze.
Future<DestinationCheck> checkDestinations({
  required List<String> roots,
  required List<PlannedCopy> files,
  Map<String, String> rememberedMounts = const {},
  bool mustExist = true,
  Duration timeout = const Duration(seconds: 20),
}) =>
    Isolate.run(
      () => checkDestinationsSync(
        roots: roots,
        files: files,
        rememberedMounts: rememberedMounts,
        mustExist: mustExist,
      ),
    ).timeout(
      timeout,
      onTimeout: () => const DestinationCheck(
        problems: [_notResponding],
      ),
    );

/// Records which volume destination [path] lives on, so later runs can tell
/// when its drive is gone. Call when the user picks a destination — picking
/// it again is also how a folder that really moved is re-learnt. Best effort.
Future<void> rememberDestinationVolume(String path) async {
  try {
    final volume = await Isolate.run(
      () => volumeInfo(path),
    ).timeout(const Duration(seconds: 10));
    if (volume == null) return;
    await updateSettings(
      (s) => s.setDestinationVolume(path, volume.mountPoint),
    );
  } on Object {
    // No memory just means no check for this folder.
  }
}

/// [bytes] as a short human size (`512 B`, `3.4 MB`, `120 GB`).
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var size = bytes / 1024;
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(size >= 10 ? 0 : 1)} ${units[unit]}';
}
