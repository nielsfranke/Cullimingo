import 'package:path/path.dart' as p;

/// Inputs a [RenameTemplate] needs to build one destination path.
class RenameInput {
  /// Creates a rename input.
  const RenameInput({
    required this.capturedAt,
    required this.originalName,
    required this.sequence,
    this.camera,
    this.shoot = '',
  });

  /// Capture time driving the date/time tokens. The orchestrator resolves this
  /// from EXIF `DateTimeOriginal`, falling back to the file's mtime.
  final DateTime capturedAt;

  /// The source file's basename **with** extension (e.g. `DSC0001.ARW`).
  final String originalName;

  /// 1-based position in the ingest batch, for the `{seq}` token. The
  /// template's [RenameTemplate.counterStart] shifts this before it is
  /// rendered, so the caller always passes the plain batch position (1, 2, …).
  final int sequence;

  /// Camera make/model for `{camera}`, when known.
  final String? camera;

  /// User-supplied shoot name for `{shoot}`, when given.
  final String shoot;
}

/// Builds destination-relative paths from a token pattern (`BUILD_PLAN.md` §5
/// Phase 3). The same engine drives the live preview and the actual copy, so
/// "preview matches output exactly" holds by construction. It also backs the
/// Capture-One-style naming builder (`features/naming/`), so tokens can carry
/// per-element options.
///
/// Tokens (case-sensitive):
/// - Plain: `{YYYY} {MM} {DD} {HH} {mm} {ss} {HHmmss} {YYYY-MM-DD} {camera}
///   {seq} {origname} {shoot}`.
/// - Counter with an explicit width: `{seq:3}` renders `007` regardless of
///   [sequenceWidth] (the width dropdown on the counter chip writes this).
/// - Date with a named format: `{date:<key>}` for one of [dateKeys] (the format
///   dropdown on the date chip writes this) — e.g. `{date:monthDayYear}` →
///   `Jul 02 2026`.
///
/// Literal `/` in the pattern create sub-folders; `/` inside a token's *value*
/// is sanitised away so only the pattern shapes the folder tree. The source
/// extension is preserved and appended automatically.
class RenameTemplate {
  /// Creates a template from [pattern], padding a bare `{seq}` to
  /// [sequenceWidth] and starting the counter at [counterStart].
  const RenameTemplate(
    this.pattern, {
    this.sequenceWidth = 4,
    this.counterStart = 1,
  });

  /// The token pattern, e.g. `{YYYY}/{YYYY-MM-DD}_{shoot}/{origname}`.
  final String pattern;

  /// Zero-pad width for a bare `{seq}` token (an explicit `{seq:N}` overrides).
  final int sequenceWidth;

  /// The value the counter renders for the first file of a batch. Defaults to 1
  /// (so `{seq}` matches the batch position); a preset can begin at 100, etc.
  final int counterStart;

  /// No organising — keep original filenames, flat into the destination (just
  /// copy A → B). Within-batch name clashes still get a `_2` suffix.
  static const RenameTemplate keepNames = RenameTemplate('{origname}');

  /// A folder-into-date preset (`BUILD_PLAN.md` §5).
  static const RenameTemplate datedShoot = RenameTemplate(
    '{YYYY}/{YYYY-MM-DD}_{shoot}/{origname}',
  );

  /// Keep the original name, just sort into year/month folders.
  static const RenameTemplate byMonth = RenameTemplate(
    '{YYYY}/{MM}/{origname}',
  );

  /// Rename to a sortable timestamp + sequence (no original name).
  static const RenameTemplate timestamped = RenameTemplate(
    '{YYYY}/{YYYY-MM-DD}_{shoot}/{YYYY-MM-DD}_{HHmmss}_{seq}',
  );

  static final RegExp _token = RegExp(r'\{([^}]+)\}');

  /// All *plain* (option-less) tokens this engine understands. The counter
  /// (`seq`, `seq:N`) and date (`date:key`) tokens are validated separately.
  static const Set<String> tokens = {
    'YYYY',
    'MM',
    'DD',
    'HH',
    'mm',
    'ss',
    'HHmmss',
    'YYYY-MM-DD',
    'camera',
    'seq',
    'origname',
    'shoot',
  };

  /// The named formats accepted by the `{date:<key>}` token, each mapped to a
  /// concrete rendering in [_formatDate]. The date chip's dropdown offers them.
  static const Set<String> dateKeys = {
    'iso',
    'compact',
    'dmyDots',
    'dmyDotsShort',
    'year',
    'yearMonth',
    'monthNumber',
    'monthName',
    'monthNameFull',
    'monthDayYear',
    'dayMonthYear',
    'weekday',
    'weekdayFull',
    'time',
    'timeHM',
  };

  // English month/weekday names for the `{date:…}` name formats. The rest of the
  // app's strings are English, so these match (no localisation layer yet).
  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const List<String> _monthsFull = [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const List<String> _weekdays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  static const List<String> _weekdaysFull = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', //
    'Friday', 'Saturday', 'Sunday',
  ];

  /// Returns the unknown tokens used in [pattern] (empty when all are valid).
  Iterable<String> unknownTokens() => _token
      .allMatches(pattern)
      .map((m) => m[1]!)
      .where((t) => !_isKnownToken(t))
      .toSet();

  /// Builds the destination-relative path (with the source extension) for
  /// [input]. Always uses `/` separators; the caller joins it under the
  /// destination root.
  String pathFor(RenameInput input) {
    final d = input.capturedAt;

    final substituted = pattern.replaceAllMapped(_token, (m) {
      final key = m[1]!;
      final value = _resolve(key, input, d);
      // Leave unknown tokens literal so a typo is visible in the preview.
      if (value == null) return m[0]!;
      return _sanitiseValue(value);
    });

    // Clean each path segment from any literal illegal chars, drop empties.
    final segments = substituted
        .split('/')
        .map(_sanitiseSegment)
        .where((s) => s.isNotEmpty)
        .toList();

    final ext = p.extension(input.originalName);
    return segments.join('/') + ext;
  }

  /// Resolves one token [key] to its string value, or null when [key] is not a
  /// token this engine understands (so the caller can leave it literal).
  String? _resolve(String key, RenameInput input, DateTime d) {
    final colon = key.indexOf(':');
    if (colon > 0) {
      final base = key.substring(0, colon);
      final arg = key.substring(colon + 1);
      switch (base) {
        case 'seq':
          final width = int.tryParse(arg);
          if (width == null || width < 1) return null;
          return _counterValue(input).toString().padLeft(width, '0');
        case 'date':
          return _formatDate(d, arg);
      }
      return null;
    }

    switch (key) {
      case 'YYYY':
        return _pad4(d.year);
      case 'MM':
        return _pad2(d.month);
      case 'DD':
        return _pad2(d.day);
      case 'HH':
        return _pad2(d.hour);
      case 'mm':
        return _pad2(d.minute);
      case 'ss':
        return _pad2(d.second);
      case 'HHmmss':
        return '${_pad2(d.hour)}${_pad2(d.minute)}${_pad2(d.second)}';
      case 'YYYY-MM-DD':
        return '${_pad4(d.year)}-${_pad2(d.month)}-${_pad2(d.day)}';
      case 'camera':
        return input.camera ?? '';
      case 'seq':
        return _counterValue(input).toString().padLeft(sequenceWidth, '0');
      case 'origname':
        return p.basenameWithoutExtension(input.originalName);
      case 'shoot':
        return input.shoot;
    }
    return null;
  }

  /// The counter number for [input], shifted by [counterStart].
  int _counterValue(RenameInput input) => input.sequence - 1 + counterStart;

  static String? _formatDate(DateTime d, String key) {
    switch (key) {
      case 'iso':
        return '${_pad4(d.year)}-${_pad2(d.month)}-${_pad2(d.day)}';
      case 'compact':
        return '${_pad4(d.year)}${_pad2(d.month)}${_pad2(d.day)}';
      case 'dmyDots': // European standard, day first: 02.07.2026
        return '${_pad2(d.day)}.${_pad2(d.month)}.${_pad4(d.year)}';
      case 'dmyDotsShort': // 02.07.26
        return '${_pad2(d.day)}.${_pad2(d.month)}.${_pad2(d.year % 100)}';
      case 'year':
        return _pad4(d.year);
      case 'yearMonth':
        return '${_pad4(d.year)}-${_pad2(d.month)}';
      case 'monthNumber':
        return _pad2(d.month);
      case 'monthName':
        return _months[d.month - 1];
      case 'monthNameFull':
        return _monthsFull[d.month - 1];
      case 'monthDayYear':
        return '${_months[d.month - 1]} ${_pad2(d.day)} ${_pad4(d.year)}';
      case 'dayMonthYear':
        return '${_pad2(d.day)} ${_months[d.month - 1]} ${_pad4(d.year)}';
      case 'weekday':
        return _weekdays[d.weekday - 1];
      case 'weekdayFull':
        return _weekdaysFull[d.weekday - 1];
      case 'time':
        return '${_pad2(d.hour)}${_pad2(d.minute)}${_pad2(d.second)}';
      case 'timeHM':
        return '${_pad2(d.hour)}-${_pad2(d.minute)}';
    }
    return null;
  }

  static bool _isKnownToken(String key) {
    final colon = key.indexOf(':');
    if (colon > 0) {
      final base = key.substring(0, colon);
      final arg = key.substring(colon + 1);
      if (base == 'seq') {
        final width = int.tryParse(arg);
        return width != null && width >= 1;
      }
      if (base == 'date') return dateKeys.contains(arg);
      return false;
    }
    return tokens.contains(key);
  }

  static String _pad2(int v) => v.toString().padLeft(2, '0');
  static String _pad4(int v) => v.toString().padLeft(4, '0');

  // Illegal in a path segment on the platforms we target (plus `/` so a token
  // value can't inject sub-folders) and control chars.
  static final RegExp _illegal = RegExp(r'[<>:"/\\|?*\x00-\x1f]');

  static String _sanitiseValue(String value) =>
      value.replaceAll(_illegal, '_').trim();

  // Segment-level cleanup: strip illegal chars from literals, collapse runs of
  // whitespace, and trim trailing dots/spaces (Windows-hostile, harmless else).
  static String _sanitiseSegment(String segment) => segment
      .replaceAll(_illegal, '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
}
