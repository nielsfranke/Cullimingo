/// How aggressively "Find similar photos" groups images (`BUILD_PLAN.md` §8):
/// the dHash Hamming-distance threshold passed to `clusterByHash`. Higher
/// distance = looser matching (more photos grouped). The 64-bit dHash means the
/// distance ranges 0–64; these presets cover the useful band.
enum SimilaritySensitivity {
  /// Only near-identical frames (tight crops / exposure brackets of one shot).
  strict(label: 'Strict', blurb: 'Near-duplicates only', maxDistance: 5),

  /// The default: clear bursts of the same subject.
  balanced(label: 'Balanced', blurb: 'Same subject / burst', maxDistance: 10),

  /// Loosely similar scenes (more grouped, more false positives).
  loose(label: 'Loose', blurb: 'Similar scenes', maxDistance: 16);

  const SimilaritySensitivity({
    required this.label,
    required this.blurb,
    required this.maxDistance,
  });

  /// Short display name.
  final String label;

  /// One-line description of what this level groups.
  final String blurb;

  /// The dHash Hamming-distance threshold for `clusterByHash`.
  final int maxDistance;

  /// The preset used when the user hasn't chosen one.
  static const SimilaritySensitivity fallback = SimilaritySensitivity.balanced;

  /// Resolves a stored [name] back to a preset, or [fallback] if unknown/null.
  static SimilaritySensitivity fromName(String? name) {
    for (final s in SimilaritySensitivity.values) {
      if (s.name == name) return s;
    }
    return fallback;
  }
}
