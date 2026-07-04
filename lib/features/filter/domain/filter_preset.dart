import 'package:cullimingo/features/filter/domain/photo_filter.dart';

/// A named, reusable grid [PhotoFilter] the user has saved — a sibling of saved
/// selections (`BUILD_PLAN.md` §5), but **global**: a filter carries no
/// import-specific data, so a preset like "Keepers = ★★★★ + Pick" is worth
/// having across every shoot. Persisted in app settings as JSON.
class FilterPreset {
  /// Creates a preset pairing a [name] with the [filter] it applies.
  const FilterPreset({required this.name, required this.filter});

  /// Rebuilds a preset from persisted [json]. A blank name / malformed filter
  /// degrades to an empty-named default that [decodeList] then drops.
  factory FilterPreset.fromJson(Map<String, dynamic> json) => FilterPreset(
    name: (json['name'] as String?)?.trim() ?? '',
    filter: PhotoFilter.fromJson(
      (json['filter'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
  );

  /// The user-visible preset name (unique, case-insensitively).
  final String name;

  /// The filter this preset applies when chosen.
  final PhotoFilter filter;

  /// The persisted form of this preset.
  Map<String, dynamic> toJson() => {'name': name, 'filter': filter.toJson()};

  /// Decodes a persisted list, skipping malformed or unnamed entries.
  static List<FilterPreset> decodeList(List<dynamic>? raw) {
    if (raw == null) return const [];
    final out = <FilterPreset>[];
    for (final entry in raw) {
      if (entry is Map) {
        final preset = FilterPreset.fromJson(entry.cast<String, dynamic>());
        if (preset.name.isNotEmpty) out.add(preset);
      }
    }
    return out;
  }

  /// Encodes [presets] for persistence.
  static List<Map<String, dynamic>> encodeList(List<FilterPreset> presets) => [
    for (final preset in presets) preset.toJson(),
  ];
}
