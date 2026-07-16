/// Shared date/time formatting. The XMP codec, the IPTC editor and the
/// inspector each carried a private copy of these exact formats (with their
/// own pad-two helpers) — one home keeps them from drifting apart.
library;

String _two(int n) => n.toString().padLeft(2, '0');

/// ISO 8601 without sub-seconds or zone (`2026-07-02T09:05:03`). XMP treats a
/// naive local time as "local to where it was taken", which is exactly what
/// EXIF gives us; the IPTC editor stores its date fields the same way.
String isoLocal(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)}'
    'T${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

/// Human-readable `YYYY-MM-DD HH:MM` (with `:SS` when [seconds] is set) for
/// display surfaces like the inspector and editor tooltips.
String displayDateTime(DateTime t, {bool seconds = false}) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)} '
    '${_two(t.hour)}:${_two(t.minute)}${seconds ? ':${_two(t.second)}' : ''}';
