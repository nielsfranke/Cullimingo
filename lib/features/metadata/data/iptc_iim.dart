import 'dart:convert';
import 'dart:typed_data';

import 'package:cullimingo/features/metadata/domain/xmp_data.dart';

// Legacy IPTC IIM writer: emits a Photoshop APP13 (`8BIM`, resource `0x0404`)
// block alongside the modern XMP, so purely-IIM readers (older wire systems,
// macOS Spotlight's image importer) can read the classic editorial fields.
// Modern tools read either. Only record-2 classic fields exist in IIM; the
// newer XMP-only fields (rights terms, contact, AI provenance…) stay in XMP.

/// Record-2 dataset numbers for the classic editorial fields, in the ascending
/// order IIM expects.
const int _dsObjectName = 5; // Title
const int _dsEditStatus = 7;
const int _dsUrgency = 10;
const int _dsCategory = 15;
const int _dsSupplementalCategory = 20; // repeatable
const int _dsKeywords = 25; // repeatable
const int _dsInstructions = 40;
const int _dsDateCreated = 55; // CCYYMMDD
const int _dsTimeCreated = 60; // HHMMSS
const int _dsByline = 80; // Creator
const int _dsBylineTitle = 85; // Job title
const int _dsCity = 90;
const int _dsSublocation = 92;
const int _dsState = 95;
const int _dsCountryCode = 100;
const int _dsCountry = 101;
const int _dsTransmissionRef = 103; // Job ID
const int _dsHeadline = 105;
const int _dsCredit = 110;
const int _dsSource = 115;
const int _dsCopyright = 116;
const int _dsCaption = 120;
const int _dsWriter = 122;

/// Encodes [data]'s classic IPTC fields as IIM record-2 datasets (UTF-8), or an
/// empty list when there is nothing legacy to write. Prefixed with a record-1
/// coded-character-set marker declaring UTF-8 so readers decode it correctly.
Uint8List buildIptcIim(XmpData data) {
  final iptc = data.iptc;
  final body = BytesBuilder();
  void put(int dataset, String value) {
    if (value.isNotEmpty) _dataset(body, 2, dataset, utf8.encode(value));
  }

  // Ascending dataset order within record 2.
  put(_dsObjectName, iptc.title);
  put(_dsEditStatus, iptc.editStatus);
  put(_dsUrgency, iptc.urgency);
  put(_dsCategory, iptc.category);
  for (final cat in _splitComma(iptc.supplementalCategories)) {
    _dataset(body, 2, _dsSupplementalCategory, utf8.encode(cat));
  }
  for (final keyword in data.keywords) {
    _dataset(body, 2, _dsKeywords, utf8.encode(keyword));
  }
  put(_dsInstructions, iptc.instructions);
  // The editable IPTC Date Created wins over the EXIF capture time.
  final created = iptc.dateCreatedParsed ?? data.dateCreated;
  if (created != null) {
    String two(int n) => n.toString().padLeft(2, '0');
    final y = created.year.toString().padLeft(4, '0');
    put(_dsDateCreated, '$y${two(created.month)}${two(created.day)}');
    put(
      _dsTimeCreated,
      '${two(created.hour)}${two(created.minute)}${two(created.second)}',
    );
  }
  put(_dsByline, iptc.creator);
  put(_dsBylineTitle, iptc.authorTitle);
  put(_dsCity, iptc.city);
  put(_dsSublocation, iptc.location);
  put(_dsState, iptc.state);
  put(_dsCountryCode, iptc.countryCode);
  put(_dsCountry, iptc.country);
  put(_dsTransmissionRef, iptc.jobId);
  put(_dsHeadline, iptc.headline);
  put(_dsCredit, iptc.credit);
  put(_dsSource, iptc.source);
  put(_dsCopyright, iptc.copyright);
  put(_dsCaption, iptc.caption);
  put(_dsWriter, iptc.descriptionWriters);

  final datasets = body.toBytes();
  if (datasets.isEmpty) return Uint8List(0);

  // Record 1, dataset 90 = coded character set → UTF-8 (ESC % G), first.
  final out = BytesBuilder();
  _dataset(out, 1, 90, ascii.encode('\x1B%G'));
  out.add(datasets);
  return out.toBytes();
}

/// Splits a comma-separated field into its trimmed, non-empty values (used for
/// the repeatable Supplemental Category dataset).
List<String> _splitComma(String csv) => [
  for (final v in csv.split(','))
    if (v.trim().isNotEmpty) v.trim(),
];

/// Splices [data]'s IIM block into [jpeg] as an APP13 Photoshop IRB segment
/// right after SOI. Returns [jpeg] unchanged if it isn't a JPEG, there's no
/// legacy content, or the block is too large for one APP13 segment.
Uint8List embedIptcIimInJpeg(Uint8List jpeg, XmpData data) {
  if (jpeg.length < 2 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) return jpeg;
  final iim = buildIptcIim(data);
  if (iim.isEmpty) return jpeg;

  final irb = _photoshopIrb(iim);
  final header = ascii.encode('Photoshop 3.0\x00'); // 14 bytes
  final segmentLength = 2 + header.length + irb.length;
  if (segmentLength > 0xFFFF) return jpeg;

  return (BytesBuilder()
        ..add(const [0xFF, 0xD8]) // SOI
        ..add([
          0xFF,
          0xED, // APP13 marker
          (segmentLength >> 8) & 0xFF,
          segmentLength & 0xFF,
        ])
        ..add(header)
        ..add(irb)
        ..add(jpeg.sublist(2)))
      .toBytes();
}

/// Wraps IIM [datasets] in an `8BIM` image-resource block (id `0x0404`).
Uint8List _photoshopIrb(Uint8List datasets) {
  final len = datasets.length;
  final b = BytesBuilder()
    ..add(ascii.encode('8BIM'))
    ..add(const [0x04, 0x04]) // resource id 0x0404 = IPTC-NAA
    ..add(const [0x00, 0x00]) // empty Pascal name (length 0 + pad)
    ..add([
      (len >> 24) & 0xFF,
      (len >> 16) & 0xFF,
      (len >> 8) & 0xFF,
      len & 0xFF,
    ])
    ..add(datasets);
  if (len.isOdd) b.addByte(0x00); // resource data padded to even length
  return b.toBytes();
}

/// Appends one IIM dataset (`0x1C` marker, record, dataset, 2-byte length,
/// data). Values ≥ 32 KB are skipped — IIM's short form can't express them and
/// no editorial field is that long.
void _dataset(BytesBuilder b, int record, int dataset, List<int> data) {
  if (data.length > 0x7FFF) return;
  b
    ..addByte(0x1C)
    ..addByte(record)
    ..addByte(dataset)
    ..addByte((data.length >> 8) & 0xFF)
    ..addByte(data.length & 0xFF)
    ..add(data);
}
