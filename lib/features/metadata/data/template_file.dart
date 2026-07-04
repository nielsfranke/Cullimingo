/// Metadata templates as **XMP files** — the interchange format Photo
/// Mechanic's "Load…"/"Save…" buttons and Adobe Bridge's metadata templates
/// use, so templates round-trip with both. An XMP file carries values only:
/// merge modes and the per-field checkboxes have no XMP form (Photo Mechanic
/// has the same limitation — those live in its snapshots, here in ours), so a
/// loaded template marks every non-empty field active with Replace mode.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:cullimingo/features/metadata/data/xmp_codec.dart';
import 'package:cullimingo/features/metadata/domain/iptc_template.dart';
import 'package:cullimingo/features/metadata/domain/template_variables.dart';
import 'package:cullimingo/features/metadata/domain/xmp_data.dart';

/// Parses an XMP template file's [source] into a template. Photo Mechanic
/// `{variables}` in the values are translated to our `{tokens}` where an
/// equivalent exists ([translatePmVariables]), so a PM template expands here
/// instead of stamping dead `{year4}` literals. Throws on malformed XML
/// ([FormatException] family) — callers surface that as "not a readable XMP
/// template".
IptcTemplate templateFromXmpSource(String source) {
  final data = decodeXmp(source);
  return templateFromIptc(
    data.iptc,
    keywords: data.keywords,
  ).mapValues(translatePmVariables);
}

/// Serialises [template] as an XMP packet: its values over an empty IPTC
/// record, plus its keywords. No cull marks ride along — the encoder skips a
/// zero rating / none flag — so the file is a pure metadata template. Variables
/// and `=codes=` in field values are written literally, exactly as Photo
/// Mechanic writes its own `{variables}`.
String templateToXmpSource(IptcTemplate template) => encodeXmp(
  XmpData(
    iptc: iptcFromTemplate(template),
    keywords: template.keywords ?? const [],
  ),
);

/// A problem reading or writing an XMP template file, with a [message] fit to
/// show the user as-is — the file/parse errors underneath are developer-speak.
class TemplateFileException implements Exception {
  /// Creates the exception with its user-presentable [message].
  const TemplateFileException(this.message);

  /// What went wrong, in words a photographer can act on.
  final String message;

  @override
  String toString() => message;
}

/// Reads and parses the XMP template file at [path] off the UI isolate (XMP
/// parsing never runs on the UI isolate). Throws [TemplateFileException] with
/// a user-presentable message on unreadable files, non-XMP content, or an XMP
/// that carries no template fields (loading one would only clear the form).
Future<IptcTemplate> readTemplateXmpFile(String path) => Isolate.run(() async {
  final String source;
  try {
    source = await File(path).readAsString();
  } on FileSystemException {
    throw const TemplateFileException(
      'The file could not be opened. Check that it still exists and is '
      'readable.',
    );
  }
  final IptcTemplate template;
  try {
    template = templateFromXmpSource(source);
  } on FormatException {
    throw const TemplateFileException(
      'This is not an XMP template. Choose a .xmp file saved from a metadata '
      'template — by Photo Mechanic, Adobe Bridge, or Cullimingo.',
    );
  }
  if (template.isEmpty) {
    throw const TemplateFileException(
      'This XMP file contains no template fields — nothing to load.',
    );
  }
  return template;
});

/// Serialises [template] and writes it to [path] off the UI isolate. Throws
/// [TemplateFileException] with a user-presentable message when the file
/// can't be written.
Future<void> writeTemplateXmpFile(String path, IptcTemplate template) {
  final xml = templateToXmpSource(template);
  return Isolate.run(() async {
    try {
      await File(path).writeAsString(xml);
    } on FileSystemException {
      throw const TemplateFileException(
        'The file could not be written. Check that the folder exists and is '
        'writable.',
      );
    }
  });
}
