/// Where the loupe docks its thumbnail filmstrip (GitHub #19). Bottom is the
/// default; left/right trade a little width for the full height of a wide
/// screen.
enum FilmstripPosition {
  /// Along the bottom edge, under the loupe toolbar (the default).
  bottom(label: 'Bottom'),

  /// A vertical strip left of the photo.
  left(label: 'Left'),

  /// A vertical strip right of the photo, between it and the inspector.
  right(label: 'Right');

  const FilmstripPosition({required this.label});

  /// Short display name.
  final String label;

  /// Whether the strip runs vertically beside the photo.
  bool get isVertical => this != bottom;

  /// Parses a stored position name, or null if unknown/absent.
  static FilmstripPosition? fromName(String? name) {
    for (final p in values) {
      if (p.name == name) return p;
    }
    return null;
  }
}
