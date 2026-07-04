import 'package:path/path.dart' as p;

/// The template variables Cullimingo understands, with a short description for
/// the editor's insert menu. We use readable `{token}` names rather than Photo
/// Mechanic's cryptic `%`/`{}` codes — the whole point of "better than PM".
const Map<String, String> kTemplateVariableHelp = {
  'year': "Capture year, e.g. 2026 (today's if the photo has no date)",
  'month': 'Capture month, 01–12',
  'day': 'Capture day, 01–31',
  'date': 'Capture date, YYYY-MM-DD',
  'time': 'Capture time, HH:MM:SS',
  'filename': 'File name with extension, e.g. DSC_0001.ARW',
  'name': 'File name without extension, e.g. DSC_0001',
  'ext': 'File extension without the dot, e.g. ARW',
  'camera': 'Camera model (blank if unknown)',
  'lens': 'Lens model (blank if unknown)',
  'seq': 'Running number across the applied photos, starting at 1',
};

/// Builds the `{token}` → value map for one photo. Date tokens fall back to the
/// current date when the photo has no capture time, so `{year}` in a copyright
/// notice always resolves. Unknown/blank fields are simply omitted (then
/// [expandVariables] leaves their token untouched).
Map<String, String> templateVariables({
  required String path,
  DateTime? capturedAt,
  String? camera,
  String? lens,
  int? sequence,
}) {
  final dt = capturedAt ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return {
    'year': '${dt.year}',
    'month': two(dt.month),
    'day': two(dt.day),
    'date': '${dt.year}-${two(dt.month)}-${two(dt.day)}',
    'time': '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}',
    'filename': p.basename(path),
    'name': p.basenameWithoutExtension(path),
    'ext': p.extension(path).replaceFirst('.', ''),
    if (camera != null && camera.isNotEmpty) 'camera': camera,
    if (lens != null && lens.isNotEmpty) 'lens': lens,
    if (sequence != null) 'seq': '$sequence',
  };
}

/// Replaces every `{token}` in [input] with its value from [vars]. An unknown
/// token is left exactly as written (non-destructive), so a literal `{foo}`
/// survives and a typo is visible rather than silently blanked.
String expandVariables(String input, Map<String, String> vars) =>
    input.replaceAllMapped(RegExp(r'\{(\w+)\}'), (match) {
      final token = match.group(1)!;
      return vars[token] ?? match.group(0)!;
    });

/// Photo Mechanic variable names (long and 4-char short form, lowercase — PM
/// matches its variables case-insensitively) → the Cullimingo token(s) with
/// the same meaning, brace-wrapped and ready to splice in. PM's `{datesort}`
/// (YYYYMMDD) has no single token here, so it maps to a composite. PM names
/// with no exact equivalent (`{hour24}`, `{iptccity}`, …) are deliberately
/// absent: they survive translation literally, so the user sees them in the
/// editor instead of getting silently wrong values. Note PM's `{lens}` is the
/// focal length — its lens *name* variable is `{lenstype}`, which is what our
/// `{lens}` means. Same-named same-meaning variables (`{filename}`, `{time}`)
/// need no entry.
const Map<String, String> kPhotoMechanicVariables = {
  'file': '{filename}',
  'filenamebase': '{name}',
  'fbas': '{name}',
  'year4': '{year}',
  'yr4': '{year}',
  'month0': '{month}',
  'mn0': '{month}',
  'day0': '{day}',
  'datesort': '{year}{month}{day}',
  'dats': '{year}{month}{day}',
  'model': '{camera}',
  'modl': '{camera}',
  'lenstype': '{lens}',
  'lt': '{lens}',
  'sequence': '{seq}',
  'seqn': '{seq}',
  'auto': '{seq}',
};

/// Rewrites Photo Mechanic `{variables}` in [input] into their Cullimingo
/// `{token}` equivalents via [kPhotoMechanicVariables], so a template saved by
/// PM keeps working when applied here. Anything unrecognised — including our
/// own tokens, which share no name with a PM alias — passes through unchanged,
/// making the rewrite a safe no-op on Cullimingo-written files.
String translatePmVariables(String input) => input.replaceAllMapped(
  RegExp(r'\{(\w+)\}'),
  (match) =>
      kPhotoMechanicVariables[match.group(1)!.toLowerCase()] ?? match.group(0)!,
);
