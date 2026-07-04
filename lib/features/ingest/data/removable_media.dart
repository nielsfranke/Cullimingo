import 'dart:convert';
import 'dart:io';

/// A hot-pluggable partition (SD card, USB stick, external drive) that could be
/// an ingest source. Discovered from `lsblk` on Linux (`BUILD_PLAN.md` §5).
class RemovablePartition {
  /// Creates a removable-partition record.
  const RemovablePartition({
    required this.devicePath,
    required this.fsType,
    required this.mountPoint,
  });

  /// Block-device node, e.g. `/dev/sda1`.
  final String devicePath;

  /// Filesystem type reported by `lsblk`, e.g. `exfat`, `vfat`.
  final String fsType;

  /// Current mount point, or null/empty when the partition isn't mounted.
  final String? mountPoint;

  /// Whether the partition is already mounted somewhere.
  bool get isMounted => mountPoint != null && mountPoint!.isNotEmpty;
}

/// Filesystem types we refuse to auto-mount: swap and container/member volumes
/// that aren't a browsable filesystem. Anything else hot-pluggable is fair game
/// (camera cards are `vfat`/`exfat`; a USB SSD source might be `ext4`/`ntfs`).
const Set<String> _nonDataFsTypes = {
  '',
  'swap',
  'crypto_LUKS',
  'LVM2_member',
  'linux_raid_member',
  'squashfs',
};

/// Parses `lsblk -J -o PATH,TYPE,FSTYPE,MOUNTPOINT,HOTPLUG` JSON into the
/// hot-pluggable partitions carrying a mountable filesystem. Whole disks, the
/// internal (non-hotplug) system drive, swap and container volumes are skipped.
/// Pure, so the filtering is unit-testable without a real device.
List<RemovablePartition> parseRemovablePartitions(String lsblkJson) {
  final result = <RemovablePartition>[];
  void walk(List<dynamic> nodes) {
    for (final node in nodes.cast<Map<String, dynamic>>()) {
      final children = node['children'];
      if (children is List) walk(children);

      if (node['type'] != 'part') continue;
      if (node['hotplug'] != true) continue;
      final fsType = (node['fstype'] as String?) ?? '';
      if (_nonDataFsTypes.contains(fsType)) continue;
      final path = node['path'] as String?;
      if (path == null) continue;

      result.add(
        RemovablePartition(
          devicePath: path,
          fsType: fsType,
          mountPoint: node['mountpoint'] as String?,
        ),
      );
    }
  }

  final decoded = jsonDecode(lsblkJson);
  if (decoded is Map && decoded['blockdevices'] is List) {
    walk(decoded['blockdevices'] as List);
  }
  return result;
}

/// The device paths in [parts] that should be mounted now: unmounted partitions
/// we haven't seen before. Skipping already-known devices means a card the user
/// manually unmounted (while leaving it plugged in) is not re-mounted against
/// their wishes — only a freshly-inserted device triggers an auto-mount. Pure.
List<String> partitionsToMount(
  Set<String> knownDevices,
  List<RemovablePartition> parts,
) => [
  for (final part in parts)
    if (!part.isMounted && !knownDevices.contains(part.devicePath))
      part.devicePath,
];

/// Extracts the mount point from `udisksctl mount` output, handling both a
/// fresh mount (`Mounted /dev/sda1 at /run/media/...`) and an already-mounted
/// device (`... is already mounted at `/run/media/...'`). Null if neither
/// matches. Pure.
String? parseUdisksMountPoint(String output) {
  final mounted = RegExp(
    r'Mounted \S+ at (.+?)\.?\s*$',
    multiLine: true,
  ).firstMatch(output);
  if (mounted != null) return mounted.group(1);
  final already = RegExp(
    "already mounted at [`'\"](.+?)[`'\"]",
  ).firstMatch(output);
  return already?.group(1);
}

/// Runs a process and returns its result. Injectable so tests don't shell out.
typedef RunProcess =
    Future<ProcessResult> Function(String executable, List<String> arguments);

Future<ProcessResult> _defaultRun(String exe, List<String> args) =>
    Process.run(exe, args);

/// Lists hot-pluggable partitions via `lsblk`. Linux only; returns `[]` on
/// other platforms or when `lsblk` is missing/unparseable. Never throws.
Future<List<RemovablePartition>> listRemovablePartitions({
  RunProcess runProcess = _defaultRun,
}) async {
  try {
    final res = await runProcess('lsblk', [
      '-J',
      '-o',
      'PATH,TYPE,FSTYPE,MOUNTPOINT,HOTPLUG',
    ]);
    if (res.exitCode != 0) return const [];
    return parseRemovablePartitions(res.stdout as String);
  } on Object {
    return const [];
  }
}

/// Mounts [devicePath] via `udisksctl` (user-space, no sudo, no polkit prompt),
/// returning the resulting mount point, or null on failure. A device that was
/// already mounted counts as success. Best effort — never throws.
Future<String?> mountRemovable(
  String devicePath, {
  RunProcess runProcess = _defaultRun,
}) async {
  try {
    final res = await runProcess('udisksctl', [
      'mount',
      '--no-user-interaction',
      '-b',
      devicePath,
    ]);
    final output = '${res.stdout}\n${res.stderr}';
    return parseUdisksMountPoint(output);
  } on Object {
    return null;
  }
}

/// Auto-mounts freshly-inserted removable cards so they appear in the app the
/// way they do on macOS, even when the Linux desktop didn't auto-mount them.
///
/// Mounts every unmounted, not-yet-seen removable partition, then returns the
/// device paths currently present — pass this back on the next call as
/// [knownDevices] so a device is auto-mounted only once (see
/// [partitionsToMount]). Never throws. Gate the call on `Platform.isLinux`.
Future<Set<String>> autoMountNewRemovables(
  Set<String> knownDevices, {
  Future<List<RemovablePartition>> Function() list = listRemovablePartitions,
  Future<String?> Function(String) mount = mountRemovable,
}) async {
  final parts = await list();
  for (final devicePath in partitionsToMount(knownDevices, parts)) {
    await mount(devicePath);
  }
  return parts.map((p) => p.devicePath).toSet();
}
