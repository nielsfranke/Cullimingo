import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/features/metadata/domain/xmp_data.dart';

// Legacy IPTC IIM *reader* — the inverse of `iptc_iim.dart`'s writer. Photo
// Mechanic, cameras and older wire systems (FotoStation, AP/Reuters tooling)
// caption via the classic APP13 / `8BIM` / `0x0404` IIM block, often *without*
// a modern XMP packet. Without this, those captions/keywords are invisible on
// import (`BUILD_PLAN.md` §4 round-trip; audit Fix 1). Parsing is byte-exact —
// IIM values are binary, so we never decode the whole prefix to a String first.

// Bound on how many bytes from the file header we scan for the IIM block; the
// APP13 segment sits near the start and a single JPEG marker caps at 64 KB, so
// 256 KB is a generous bound that keeps the read cheap (like `embedded_xmp`).
const int _scanBytes = 256 * 1024;

const List<int> _photoshopMarker = [
  0x50, 0x68, 0x6F, 0x74, 0x6F, 0x73, 0x68, 0x6F, 0x70, // "Photoshop"
];
const List<int> _eightBim = [0x38, 0x42, 0x49, 0x4D]; // "8BIM"

// Record-2 dataset numbers (mirror `iptc_iim.dart`).
const int _dsObjectName = 5;
const int _dsEditStatus = 7;
const int _dsUrgency = 10;
const int _dsCategory = 15;
const int _dsSupplementalCategory = 20; // repeatable
const int _dsKeywords = 25;
const int _dsInstructions = 40;
const int _dsDateCreated = 55; // CCYYMMDD
const int _dsTimeCreated = 60; // HHMMSS
const int _dsByline = 80;
const int _dsBylineTitle = 85;
const int _dsCity = 90;
const int _dsSublocation = 92;
const int _dsState = 95;
const int _dsCountryCode = 100;
const int _dsCountry = 101;
const int _dsTransmissionRef = 103;
const int _dsHeadline = 105;
const int _dsCredit = 110;
const int _dsSource = 115;
const int _dsCopyright = 116;
const int _dsCaption = 120;
const int _dsWriter = 122;

// Record-1 dataset 90 = coded character set; ESC % G (0x1B 0x25 0x47) = UTF-8.
const int _dsCodedCharacterSet = 90;

/// Reads the classic IPTC (IIM) block embedded in the image file at [path] and
/// returns it as an [XmpData] (keywords + [IptcCore]), or `null` when the file
/// has no IIM block. Only a bounded prefix is read; still, call off the UI
/// isolate for big batches. Mirrors the shape of `readEmbeddedXmp`.
Future<XmpData?> readEmbeddedIim(String path) async {
  RandomAccessFile? raf;
  try {
    raf = await File(path).open();
    final length = await raf.length();
    final count = length < _scanBytes ? length : _scanBytes;
    final bytes = await raf.read(count);
    return decodeIptcIim(bytes);
  } on Object {
    return null;
  } finally {
    await raf?.close();
  }
}

/// Parses the IPTC IIM datasets out of raw image [bytes] (a JPEG or its header
/// prefix). Returns an [XmpData] carrying the classic editorial fields, or
/// `null` when there is no `0x0404` IPTC resource or it holds nothing. Pure and
/// byte-exact so it can be unit-tested without a file.
XmpData? decodeIptcIim(Uint8List bytes) {
  final datasets = _findIptcResource(bytes);
  if (datasets == null) return null;
  return _datasetsToXmpData(datasets);
}

/// Locates the IIM dataset bytes inside the Photoshop image-resource block
/// (IRB). Walks the IRB list from the `Photoshop 3.0` header so it correctly
/// skips other `8BIM` resources; returns the `0x0404` (IPTC-NAA) resource's
/// data, or `null` if absent/malformed.
Uint8List? _findIptcResource(Uint8List bytes) {
  final header = _indexOf(bytes, _photoshopMarker, 0);
  if (header < 0) return null;
  // The IRB list begins just after the null-terminated "Photoshop x.y\0" tag.
  var pos = _indexOf(bytes, const [0x00], header);
  if (pos < 0) return null;
  pos += 1;

  while (pos + 8 <= bytes.length && _matchesAt(bytes, _eightBim, pos)) {
    pos += 4;
    final id = (bytes[pos] << 8) | bytes[pos + 1];
    pos += 2;
    // Pascal name: 1 length byte + name, whole thing padded to an even length.
    final nameLen = bytes[pos];
    var nameField = 1 + nameLen;
    if (nameField.isOdd) nameField += 1;
    pos += nameField;
    if (pos + 4 > bytes.length) return null;
    final size =
        (bytes[pos] << 24) |
        (bytes[pos + 1] << 16) |
        (bytes[pos + 2] << 8) |
        bytes[pos + 3];
    pos += 4;
    if (size < 0 || pos + size > bytes.length) return null;
    if (id == 0x0404) {
      return Uint8List.sublistView(bytes, pos, pos + size);
    }
    pos += size + (size.isOdd ? 1 : 0); // resource data padded to even length
  }
  return null;
}

/// Walks the IIM datasets in [data] and folds them into an [XmpData]. Returns
/// `null` when nothing usable was present.
XmpData? _datasetsToXmpData(Uint8List data) {
  final values = <int, List<Uint8List>>{};
  var pos = 0;
  while (pos + 5 <= data.length && data[pos] == 0x1C) {
    final record = data[pos + 1];
    final dataset = data[pos + 2];
    var len = (data[pos + 3] << 8) | data[pos + 4];
    pos += 5;
    // Extended (long-form) length: high bit set → next `len & 0x7fff` bytes are
    // the real length. Editorial fields never need it, but tolerate it.
    if (len & 0x8000 != 0) {
      final lenOfLen = len & 0x7fff;
      if (pos + lenOfLen > data.length || lenOfLen > 4) return null;
      var real = 0;
      for (var i = 0; i < lenOfLen; i++) {
        real = (real << 8) | data[pos + i];
      }
      pos += lenOfLen;
      len = real;
    }
    if (pos + len > data.length) break;
    final value = Uint8List.sublistView(data, pos, pos + len);
    pos += len;
    values.putIfAbsent(record << 8 | dataset, () => []).add(value);
  }
  if (values.isEmpty) return null;

  final utf8Charset = _isUtf8(values[1 << 8 | _dsCodedCharacterSet]);
  String decode(int dataset) {
    final list = values[2 << 8 | dataset];
    if (list == null || list.isEmpty) return '';
    return _decodeText(list.first, utf8: utf8Charset);
  }

  final keywords = [
    for (final raw in values[2 << 8 | _dsKeywords] ?? const <Uint8List>[])
      _decodeText(raw, utf8: utf8Charset),
  ].where((k) => k.isNotEmpty).toList();

  // Repeatable dataset → comma-joined string (mirrors our XMP bag handling).
  String decodeAll(int dataset) => [
    for (final raw in values[2 << 8 | dataset] ?? const <Uint8List>[])
      _decodeText(raw, utf8: utf8Charset),
  ].where((v) => v.isNotEmpty).join(', ');

  final iptc = IptcCore(
    caption: decode(_dsCaption),
    headline: decode(_dsHeadline),
    title: decode(_dsObjectName),
    creator: decode(_dsByline),
    authorTitle: decode(_dsBylineTitle),
    credit: decode(_dsCredit),
    source: decode(_dsSource),
    copyright: decode(_dsCopyright),
    instructions: decode(_dsInstructions),
    location: decode(_dsSublocation),
    city: decode(_dsCity),
    state: decode(_dsState),
    country: decode(_dsCountry),
    countryCode: decode(_dsCountryCode),
    jobId: decode(_dsTransmissionRef),
    editStatus: decode(_dsEditStatus),
    urgency: decode(_dsUrgency),
    category: decode(_dsCategory),
    supplementalCategories: decodeAll(_dsSupplementalCategory),
    descriptionWriters: decode(_dsWriter),
  );

  if (iptc.isEmpty && keywords.isEmpty) return null;
  return XmpData(
    keywords: keywords,
    iptc: iptc,
    dateCreated: _dateFrom(decode(_dsDateCreated), decode(_dsTimeCreated)),
  );
}

/// True if the record-1 coded-character-set dataset declares UTF-8 (ESC % G).
bool _isUtf8(List<Uint8List>? charset) {
  if (charset == null || charset.isEmpty) return false;
  final v = charset.first;
  return v.length >= 3 && v[0] == 0x1B && v[1] == 0x25 && v[2] == 0x47;
}

/// Decodes an IIM value. Uses UTF-8 when the block declared it *or* when the
/// bytes are valid UTF-8; otherwise Latin-1, so accented legacy captions
/// survive. Trailing NULs (some writers pad) are trimmed.
String _decodeText(Uint8List bytes, {required bool utf8}) {
  var end = bytes.length;
  while (end > 0 && bytes[end - 1] == 0x00) {
    end--;
  }
  final view = Uint8List.sublistView(bytes, 0, end);
  if (utf8) {
    try {
      return const Utf8Decoder().convert(view);
    } on FormatException {
      return latin1.decode(view);
    }
  }
  // No explicit charset: prefer UTF-8 if it parses, else Latin-1.
  try {
    return const Utf8Decoder().convert(view);
  } on FormatException {
    return latin1.decode(view);
  }
}

/// Reconstructs the capture time from IIM 2:55 (CCYYMMDD) + 2:60 (HHMMSS), or
/// null when the date is missing/unparseable.
DateTime? _dateFrom(String date, String time) {
  if (date.length < 8) return null;
  final year = int.tryParse(date.substring(0, 4));
  final month = int.tryParse(date.substring(4, 6));
  final day = int.tryParse(date.substring(6, 8));
  if (year == null || month == null || day == null) return null;
  var hour = 0;
  var minute = 0;
  var second = 0;
  if (time.length >= 6) {
    hour = int.tryParse(time.substring(0, 2)) ?? 0;
    minute = int.tryParse(time.substring(2, 4)) ?? 0;
    second = int.tryParse(time.substring(4, 6)) ?? 0;
  }
  try {
    return DateTime(year, month, day, hour, minute, second);
  } on Object {
    return null;
  }
}

/// First index of [needle] in [haystack] at or after [start], or -1.
int _indexOf(Uint8List haystack, List<int> needle, int start) {
  if (needle.isEmpty) return -1;
  final last = haystack.length - needle.length;
  for (var i = start < 0 ? 0 : start; i <= last; i++) {
    if (_matchesAt(haystack, needle, i)) return i;
  }
  return -1;
}

/// Whether [needle] appears in [haystack] starting exactly at [at].
bool _matchesAt(Uint8List haystack, List<int> needle, int at) {
  if (at + needle.length > haystack.length) return false;
  for (var i = 0; i < needle.length; i++) {
    if (haystack[at + i] != needle[i]) return false;
  }
  return true;
}
