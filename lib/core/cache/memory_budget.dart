import 'dart:io';

/// Hard ceiling for a single in-RAM cache (~256 MB). On a roomy machine this is
/// the Photo-Mechanic-style "keep everything resident" budget the app targets.
const int _budgetCap = 256 * 1024 * 1024;

/// Floor for a single in-RAM cache (~64 MB), so even a 4 GB machine keeps a
/// usable scroll-back window without risking swap.
const int _budgetFloor = 64 * 1024 * 1024;

/// Fraction of physical RAM allotted to *one* in-RAM cache. We run two of these
/// (encoded preview bytes + Flutter's decoded image cache), so the caches
/// together take ~2× this — i.e. ~RAM/32 — which keeps a low-end box well clear
/// of swap while still filling a big machine.
const int _ramDivisor = 64;

/// In-RAM cache budget in bytes, scaled to the machine: `physicalRam / 64`,
/// clamped to [64 MB, 256 MB]. Pass [totalBytes] in tests; in production it's
/// read once from the OS via [totalPhysicalMemoryBytes].
///
/// 4 GB → 64 MB · 8 GB → 128 MB · ≥16 GB → 256 MB. Unknown RAM → the floor.
int cacheMemoryBudgetBytes({int? totalBytes}) {
  final total = totalBytes ?? totalPhysicalMemoryBytes();
  if (total == null || total <= 0) return _budgetFloor;
  return (total ~/ _ramDivisor).clamp(_budgetFloor, _budgetCap);
}

/// Total physical RAM in bytes, or `null` if it can't be determined (then
/// callers fall back to the conservative floor). Read once at startup.
int? totalPhysicalMemoryBytes() {
  try {
    if (Platform.isMacOS) {
      final r = Process.runSync('sysctl', ['-n', 'hw.memsize']);
      return int.tryParse((r.stdout as String).trim());
    }
    if (Platform.isLinux) {
      final line = File('/proc/meminfo').readAsLinesSync().firstWhere(
        (l) => l.startsWith('MemTotal:'),
        orElse: () => '',
      );
      final kb = int.tryParse(line.replaceAll(RegExp('[^0-9]'), ''));
      return kb == null ? null : kb * 1024;
    }
  } on Object {
    return null;
  }
  return null; // Windows/unknown: callers use the floor until §later support.
}
