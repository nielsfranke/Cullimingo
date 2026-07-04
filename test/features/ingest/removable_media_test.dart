import 'package:cullimingo/features/ingest/data/removable_media.dart';
import 'package:flutter_test/flutter_test.dart';

// Mirrors real `lsblk -J -o PATH,TYPE,FSTYPE,MOUNTPOINT,HOTPLUG` output: a USB
// SD-card reader (hotplug, unmounted exFAT card) alongside the internal NVMe
// system disk and zram swap, which must never be offered for mounting.
const _lsblkJson = '''
{
  "blockdevices": [
    {"path":"/dev/sda","type":"disk","fstype":null,"mountpoint":null,"hotplug":true,
      "children":[
        {"path":"/dev/sda1","type":"part","fstype":"exfat","mountpoint":null,"hotplug":true}
      ]},
    {"path":"/dev/zram0","type":"disk","fstype":"swap","mountpoint":"[SWAP]","hotplug":false},
    {"path":"/dev/nvme0n1","type":"disk","fstype":null,"mountpoint":null,"hotplug":false,
      "children":[
        {"path":"/dev/nvme0n1p1","type":"part","fstype":"vfat","mountpoint":"/boot/efi","hotplug":false},
        {"path":"/dev/nvme0n1p2","type":"part","fstype":"btrfs","mountpoint":"/","hotplug":false}
      ]}
  ]
}
''';

void main() {
  group('parseRemovablePartitions', () {
    test('keeps only hot-pluggable data partitions', () {
      final parts = parseRemovablePartitions(_lsblkJson);
      expect(parts.map((p) => p.devicePath), ['/dev/sda1']);
      expect(parts.single.fsType, 'exfat');
      expect(parts.single.isMounted, isFalse);
    });

    test('never returns the internal system disk or swap', () {
      final paths = parseRemovablePartitions(
        _lsblkJson,
      ).map((p) => p.devicePath);
      expect(
        paths,
        isNot(contains('/dev/nvme0n1p1')),
      ); // /boot/efi, not hotplug
      expect(paths, isNot(contains('/dev/nvme0n1p2'))); // /, not hotplug
      expect(paths, isNot(contains('/dev/zram0'))); // swap
    });

    test('skips a hot-pluggable partition with no filesystem', () {
      final parts = parseRemovablePartitions('''
        {"blockdevices":[
          {"path":"/dev/sdb1","type":"part","fstype":null,"mountpoint":null,"hotplug":true}
        ]}''');
      expect(parts, isEmpty);
    });

    test('reports an already-mounted removable partition as mounted', () {
      final parts = parseRemovablePartitions('''
        {"blockdevices":[
          {"path":"/dev/sda1","type":"part","fstype":"exfat","mountpoint":"/run/media/x/CARD","hotplug":true}
        ]}''');
      expect(parts.single.isMounted, isTrue);
      expect(parts.single.mountPoint, '/run/media/x/CARD');
    });
  });

  group('partitionsToMount', () {
    const card = RemovablePartition(
      devicePath: '/dev/sda1',
      fsType: 'exfat',
      mountPoint: null,
    );

    test('mounts an unmounted, previously-unseen card', () {
      expect(partitionsToMount(const {}, [card]), ['/dev/sda1']);
    });

    test('does not re-mount a card the user manually unmounted', () {
      // Known device, still unmounted → we leave it alone (no fighting).
      expect(partitionsToMount({'/dev/sda1'}, [card]), isEmpty);
    });

    test('does not touch an already-mounted card', () {
      const mounted = RemovablePartition(
        devicePath: '/dev/sda1',
        fsType: 'exfat',
        mountPoint: '/run/media/x/CARD',
      );
      expect(partitionsToMount(const {}, [mounted]), isEmpty);
    });
  });

  group('parseUdisksMountPoint', () {
    test('parses a fresh mount', () {
      expect(
        parseUdisksMountPoint(
          'Mounted /dev/sda1 at /run/media/niels/9EC1-A73E',
        ),
        '/run/media/niels/9EC1-A73E',
      );
    });

    test('parses a trailing-period mount line', () {
      expect(
        parseUdisksMountPoint('Mounted /dev/sda1 at /run/media/niels/CARD.'),
        '/run/media/niels/CARD',
      );
    });

    test('parses the already-mounted error', () {
      expect(
        parseUdisksMountPoint(
          'Error mounting /dev/sda1: GDBus.Error:...AlreadyMounted: '
          "Device /dev/sda1 is already mounted at `/run/media/niels/9EC1-A73E'.",
        ),
        '/run/media/niels/9EC1-A73E',
      );
    });

    test('returns null when nothing matches', () {
      expect(parseUdisksMountPoint('some other error'), isNull);
    });
  });

  group('autoMountNewRemovables', () {
    test('mounts new cards and remembers them for next time', () async {
      const card = RemovablePartition(
        devicePath: '/dev/sda1',
        fsType: 'exfat',
        mountPoint: null,
      );
      final mounted = <String>[];

      final known = await autoMountNewRemovables(
        const {},
        list: () async => [card],
        mount: (path) async {
          mounted.add(path);
          return '/run/media/x/CARD';
        },
      );

      expect(mounted, ['/dev/sda1']);
      expect(known, {'/dev/sda1'});

      // Second pass with the device now known → no second mount attempt.
      mounted.clear();
      await autoMountNewRemovables(
        known,
        list: () async => [card],
        mount: (path) async {
          mounted.add(path);
          return null;
        },
      );
      expect(mounted, isEmpty);
    });
  });
}
