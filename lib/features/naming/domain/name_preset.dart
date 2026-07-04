import 'package:cullimingo/features/ingest/domain/rename_template.dart';

/// A named, savable filename + folder naming scheme — the "Voreinstellung" in
/// the Capture-One-style naming builder (`features/naming/`). It splits the
/// engine pattern into a [folderPattern] (the sub-folder tree) and a
/// [filePattern] (the output basename) so the builder can present two rows, but
/// the two collapse back into one [RenameTemplate] pattern for the engine.
class NamePreset {
  /// Creates a preset.
  const NamePreset({
    required this.name,
    required this.folderPattern,
    required this.filePattern,
    this.counterStart = 1,
    this.builtIn = false,
  });

  /// Rebuilds a preset from its persisted map (see [toJson]).
  factory NamePreset.fromJson(Map<String, dynamic> json) => NamePreset(
    name: json['name'] as String? ?? '',
    folderPattern: json['folder'] as String? ?? '',
    filePattern: json['file'] as String? ?? '{origname}',
    counterStart: (json['counterStart'] as num?)?.toInt() ?? 1,
  );

  /// Display name shown in the preset dropdown.
  final String name;

  /// The sub-folder tree pattern, e.g. `{YYYY}/{YYYY-MM-DD}_{shoot}`. Empty
  /// means "no sub-folders — write straight into the destination".
  final String folderPattern;

  /// The output basename pattern (no extension), e.g. `{origname}` or
  /// `{shoot}_{seq:3}`.
  final String filePattern;

  /// The value the counter renders for the first file of a batch.
  final int counterStart;

  /// Built-in presets ship with the app and can't be deleted or overwritten.
  final bool builtIn;

  /// The single engine pattern: [folderPattern] (when set) joined to
  /// [filePattern] with `/`, which the engine turns into sub-folders.
  String get combinedPattern =>
      folderPattern.isEmpty ? filePattern : '$folderPattern/$filePattern';

  /// The [RenameTemplate] this preset drives.
  RenameTemplate toTemplate() =>
      RenameTemplate(combinedPattern, counterStart: counterStart);

  /// Returns a copy with the given fields replaced.
  NamePreset copyWith({
    String? name,
    String? folderPattern,
    String? filePattern,
    int? counterStart,
    bool? builtIn,
  }) => NamePreset(
    name: name ?? this.name,
    folderPattern: folderPattern ?? this.folderPattern,
    filePattern: filePattern ?? this.filePattern,
    counterStart: counterStart ?? this.counterStart,
    builtIn: builtIn ?? this.builtIn,
  );

  /// Persisted form (built-ins aren't stored — they're always re-seeded).
  Map<String, dynamic> toJson() => {
    'name': name,
    'folder': folderPattern,
    'file': filePattern,
    'counterStart': counterStart,
  };

  /// True when the two patterns match (ignoring [name]/[builtIn]) — used to spot
  /// which preset the current editor state corresponds to.
  bool sameSchemeAs(NamePreset other) =>
      folderPattern == other.folderPattern &&
      filePattern == other.filePattern &&
      counterStart == other.counterStart;

  /// The built-in presets, mirroring the [RenameTemplate] constants so
  /// switchers from Photo Mechanic / Capture One find familiar starting points.
  static const List<NamePreset> builtIns = [
    NamePreset(
      name: 'Keep filenames',
      folderPattern: '',
      filePattern: '{origname}',
      builtIn: true,
    ),
    NamePreset(
      name: 'Year / date_shoot / name',
      folderPattern: '{date:year}/{date:iso}_{shoot}',
      filePattern: '{origname}',
      builtIn: true,
    ),
    NamePreset(
      name: 'Year / month / name',
      folderPattern: '{date:year}/{date:monthNumber}',
      filePattern: '{origname}',
      builtIn: true,
    ),
    NamePreset(
      name: 'Timestamped',
      folderPattern: '{date:year}/{date:iso}_{shoot}',
      filePattern: '{date:iso}_{date:time}_{seq:4}',
      builtIn: true,
    ),
  ];
}
