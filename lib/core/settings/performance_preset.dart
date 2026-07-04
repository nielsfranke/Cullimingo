import 'package:cullimingo/core/cache/memory_budget.dart';

/// A user-chosen performance level, bundling the two perceptible levers
/// (thumbnail source resolution + in-RAM cache budget) into named presets so
/// the app stays lean — no free-form knobs (`BUILD_PLAN.md` §2/§3).
enum PerformancePreset {
  /// Smaller thumbnails + a tight RAM cache — light and fast on low-RAM
  /// machines (or to keep Cullimingo's footprint down).
  lean(label: 'Lean', blurb: 'Lighter on memory, less sharp thumbnails'),

  /// The default — sharp thumbnails with a RAM cache scaled to the machine.
  balanced(label: 'Balanced', blurb: 'Sharp thumbnails, memory scaled to RAM'),

  /// Sharp thumbnails with the largest RAM cache — snappiest scroll-back on
  /// roomy machines (kept everything resident).
  max(label: 'Max', blurb: 'Keeps the most resident — fastest scroll-back');

  const PerformancePreset({required this.label, required this.blurb});

  /// Short display name.
  final String label;

  /// One-line description for the settings UI.
  final String blurb;

  /// Parses a stored preset name, or null if unknown/absent.
  static PerformancePreset? fromName(String? name) {
    for (final p in values) {
      if (p.name == name) return p;
    }
    return null;
  }
}

/// The resolved numbers a [PerformancePreset] maps to on a given machine.
class PerformanceSettings {
  /// Creates resolved settings.
  const PerformanceSettings({
    required this.preset,
    required this.thumbLongEdge,
    required this.ramBudgetBytes,
  });

  /// The preset these came from.
  final PerformancePreset preset;

  /// Grid thumbnail source resolution (long edge, px).
  final int thumbLongEdge;

  /// In-RAM cache budget per cache (bytes).
  final int ramBudgetBytes;
}

const int _leanThumb = 768;
const int _standardThumb = 1024;
const int _leanRamCap = 96 * 1024 * 1024;
const int _maxRam = 256 * 1024 * 1024;
const int _gb = 1024 * 1024 * 1024;

/// Resolves [preset] to concrete numbers for this machine. [totalBytes] is the
/// physical RAM (injectable for tests; production reads the OS).
///
/// Lean = 768 px + a RAM cache capped at ~96 MB; Balanced = 1024 px + the
/// auto RAM budget ([cacheMemoryBudgetBytes]); Max = 1024 px + the 256 MB cap.
PerformanceSettings resolvePerformance(
  PerformancePreset preset, {
  int? totalBytes,
}) {
  final auto = cacheMemoryBudgetBytes(totalBytes: totalBytes);
  return switch (preset) {
    PerformancePreset.lean => PerformanceSettings(
      preset: preset,
      thumbLongEdge: _leanThumb,
      ramBudgetBytes: auto < _leanRamCap ? auto : _leanRamCap,
    ),
    PerformancePreset.balanced => PerformanceSettings(
      preset: preset,
      thumbLongEdge: _standardThumb,
      ramBudgetBytes: auto,
    ),
    PerformancePreset.max => PerformanceSettings(
      preset: preset,
      thumbLongEdge: _standardThumb,
      ramBudgetBytes: _maxRam,
    ),
  };
}

/// The preset to recommend for a machine with [totalBytes] of RAM: Lean under
/// 8 GB, Balanced 8–16 GB, Max at 16 GB+. Unknown RAM → the conservative Lean.
PerformancePreset recommendedPreset({int? totalBytes}) {
  if (totalBytes == null || totalBytes <= 0) return PerformancePreset.lean;
  if (totalBytes < 8 * _gb) return PerformancePreset.lean;
  if (totalBytes < 16 * _gb) return PerformancePreset.balanced;
  return PerformancePreset.max;
}

/// The presets worth offering on a machine with [totalBytes] of RAM. Max is
/// hidden under ~12 GB — forcing 256 MB resident there risks swap, so it's not
/// a sensible choice (and we don't offer settings the machine can't carry).
List<PerformancePreset> availablePresets({int? totalBytes}) {
  if (totalBytes == null || totalBytes < 12 * _gb) {
    return const [PerformancePreset.lean, PerformancePreset.balanced];
  }
  return PerformancePreset.values;
}
