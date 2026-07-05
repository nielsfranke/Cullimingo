import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';

/// A combinable filter over the cull grid (`BUILD_PLAN.md` §5): rating
/// threshold, flag state, colour label, "has keyword" and "needs caption".
/// `null`/0/false means "don't care".
///
/// The "selected only" quick-filter ([selectedOnly]) can't be answered by
/// [matches] alone — it needs the live grid selection — so the provider
/// intersects with it; this object only carries the toggle state.
class PhotoFilter {
  /// Creates a filter. Defaults match everything.
  const PhotoFilter({
    this.minRating = 0,
    this.flag,
    this.color,
    this.hasKeyword = false,
    this.needsCaption = false,
    this.selectedOnly = false,
    this.burstsOnly = false,
    this.hideJpegPairs = false,
    this.collapseBrackets = false,
  });

  /// Rebuilds a filter from a saved-preset [json] (see [toJson]). Missing keys
  /// and unknown enum names fall back to "don't care", so a preset written by a
  /// newer build still loads (minus the constraint it didn't understand).
  factory PhotoFilter.fromJson(Map<String, dynamic> json) => PhotoFilter(
    minRating: (json['minRating'] as num?)?.toInt() ?? 0,
    flag: _enumByName(PickFlag.values, json['flag']),
    color: _enumByName(ColorLabel.values, json['color']),
    hasKeyword: json['hasKeyword'] as bool? ?? false,
    needsCaption: json['needsCaption'] as bool? ?? false,
    burstsOnly: json['burstsOnly'] as bool? ?? false,
    hideJpegPairs: json['hideJpegPairs'] as bool? ?? false,
    collapseBrackets: json['collapseBrackets'] as bool? ?? false,
  );

  /// Minimum star rating (0 = any).
  final int minRating;

  /// Required pick/reject flag (null = any).
  final PickFlag? flag;

  /// Required colour label (null = any).
  final ColorLabel? color;

  /// When true, only photos that carry at least one keyword pass.
  final bool hasKeyword;

  /// When true, only photos with a blank IPTC caption pass — the caption-pass
  /// view: which picks still need writing up (`BUILD_PLAN.md` Phase 4b).
  final bool needsCaption;

  /// When true, only photos in the current grid selection pass. Applied by the
  /// provider, not [matches] (the selection lives outside this value object).
  final bool selectedOnly;

  /// When true, only photos that belong to a capture-time burst (a group of
  /// ≥ 2) pass. Applied by the provider, not [matches] (grouping lives outside
  /// this value object).
  final bool burstsOnly;

  /// When true, the JPEG side of a RAW+JPEG pair is hidden (the RAW stays).
  /// Applied by the provider, not [matches] (pairing lives outside this value
  /// object).
  final bool hideJpegPairs;

  /// When true, exposure-bracket stacks collapse to their reference (normal)
  /// frame — the non-reference members are hidden so the grid shows one cell
  /// per bracket. Applied by the provider, not [matches] (grouping lives
  /// outside this value object).
  final bool collapseBrackets;

  /// Whether any constraint is set.
  bool get isActive =>
      minRating > 0 ||
      flag != null ||
      color != null ||
      hasKeyword ||
      needsCaption ||
      selectedOnly ||
      burstsOnly ||
      hideJpegPairs ||
      collapseBrackets;

  /// True if [photo] passes every active constraint that this object can judge
  /// on its own. Does **not** consider [selectedOnly] — see the class doc.
  bool matches(Photo photo) {
    if (photo.rating < minRating) return false;
    if (flag != null && photo.flag != flag) return false;
    if (color != null && photo.colorLabel != color) return false;
    if (hasKeyword && photo.keywords.isEmpty) return false;
    if (needsCaption && photo.iptc.caption.trim().isNotEmpty) return false;
    return true;
  }

  /// The persistable constraints, for a saved filter preset. [selectedOnly] is
  /// deliberately excluded — it references the live grid selection, so it can't
  /// be a reusable preset (the presets layer strips it before saving too).
  Map<String, dynamic> toJson() => {
    'minRating': minRating,
    if (flag != null) 'flag': flag!.name,
    if (color != null) 'color': color!.name,
    'hasKeyword': hasKeyword,
    'needsCaption': needsCaption,
    'burstsOnly': burstsOnly,
    'hideJpegPairs': hideJpegPairs,
    'collapseBrackets': collapseBrackets,
  };

  /// Returns a copy with the minimum rating set (0 clears it).
  PhotoFilter withMinRating(int rating) => _copyWith(minRating: rating);

  /// Returns a copy with the flag constraint set (null clears it).
  PhotoFilter withFlag(PickFlag? value) => _copyWith(flag: () => value);

  /// Returns a copy with the colour constraint set (null clears it).
  PhotoFilter withColor(ColorLabel? value) => _copyWith(color: () => value);

  /// Returns a copy with the has-keyword constraint set.
  // ignore: avoid_positional_boolean_parameters — mirrors the other with* setters.
  PhotoFilter withHasKeyword(bool value) => _copyWith(hasKeyword: value);

  /// Returns a copy with the needs-caption constraint set.
  // ignore: avoid_positional_boolean_parameters — mirrors the other with* setters.
  PhotoFilter withNeedsCaption(bool value) => _copyWith(needsCaption: value);

  /// Returns a copy with the selected-only constraint set.
  // ignore: avoid_positional_boolean_parameters — mirrors the other with* setters.
  PhotoFilter withSelectedOnly(bool value) => _copyWith(selectedOnly: value);

  /// Returns a copy with the bursts-only constraint set.
  // ignore: avoid_positional_boolean_parameters — mirrors the other with* setters.
  PhotoFilter withBurstsOnly(bool value) => _copyWith(burstsOnly: value);

  /// Returns a copy with the hide-JPEG-pairs constraint set.
  // ignore: avoid_positional_boolean_parameters — mirrors the other with* setters.
  PhotoFilter withHideJpegPairs(bool value) => _copyWith(hideJpegPairs: value);

  /// Returns a copy with the collapse-brackets constraint set.
  // ignore: avoid_positional_boolean_parameters — mirrors the other with* setters.
  PhotoFilter withCollapseBrackets(bool value) =>
      _copyWith(collapseBrackets: value);

  // Nullable fields use a thunk so passing null clears them (vs "absent").
  PhotoFilter _copyWith({
    int? minRating,
    PickFlag? Function()? flag,
    ColorLabel? Function()? color,
    bool? hasKeyword,
    bool? needsCaption,
    bool? selectedOnly,
    bool? burstsOnly,
    bool? hideJpegPairs,
    bool? collapseBrackets,
  }) => PhotoFilter(
    minRating: minRating ?? this.minRating,
    flag: flag != null ? flag() : this.flag,
    color: color != null ? color() : this.color,
    hasKeyword: hasKeyword ?? this.hasKeyword,
    needsCaption: needsCaption ?? this.needsCaption,
    selectedOnly: selectedOnly ?? this.selectedOnly,
    burstsOnly: burstsOnly ?? this.burstsOnly,
    hideJpegPairs: hideJpegPairs ?? this.hideJpegPairs,
    collapseBrackets: collapseBrackets ?? this.collapseBrackets,
  );
}

/// Looks up the enum value named [name] in [values], or null when [name] is
/// absent / not a string / unrecognised — used to decode a persisted filter
/// tolerantly (see [PhotoFilter.fromJson]).
T? _enumByName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
