import 'dart:convert';
import 'dart:typed_data';

/// Builds a minimal uncompressed Bayer (RGGB) DNG with **no embedded preview**
/// — the shape of RAW that needs the demosaic fallback — so LibRaw paths can
/// be exercised without checking camera files into the repo.
///
/// [truncate] cuts that many bytes off the end of the pixel data, which makes
/// LibRaw hit end-of-file (and report a data error) during unpack.
Uint8List syntheticDng({int width = 64, int height = 48, int truncate = 0}) {
  final pixels = ByteData(width * height * 2);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      // A diagonal ramp, so the output isn't a flat colour.
      final v = 4096 + ((x + y) * 40000 ~/ (width + height));
      pixels.setUint16((y * width + x) * 2, v, Endian.little);
    }
  }

  final entries = <_Entry>[
    _Entry.long(254, [0]), // NewSubFileType: main image
    _Entry.long(256, [width]),
    _Entry.long(257, [height]),
    _Entry.short(258, [16]), // BitsPerSample
    _Entry.short(259, [1]), // Compression: none
    _Entry.short(262, [32803]), // Photometric: CFA
    _Entry.ascii(271, 'Cullimingo'), // Make
    _Entry.ascii(272, 'Synthetic'), // Model
    _Entry.long(273, [0]), // StripOffsets — patched below
    _Entry.short(274, [1]), // Orientation
    _Entry.short(277, [1]), // SamplesPerPixel
    _Entry.long(278, [height]), // RowsPerStrip
    _Entry.long(279, [pixels.lengthInBytes]), // StripByteCounts
    _Entry.short(284, [1]), // PlanarConfiguration
    _Entry.short(33421, [2, 2]), // CFARepeatPatternDim
    _Entry.bytes(33422, [0, 1, 1, 2]), // CFAPattern: RGGB
    _Entry.bytes(50706, [1, 4, 0, 0]), // DNGVersion
    _Entry.ascii(50708, 'Cullimingo Synthetic'), // UniqueCameraModel
    _Entry.long(50717, [65535]), // WhiteLevel
    // ColorMatrix1: identity (XYZ → camera), good enough for a test image.
    _Entry.srational(50721, [1, 0, 0, 0, 1, 0, 0, 0, 1]),
    _Entry.rational(50728, [1, 1, 1]), // AsShotNeutral
    _Entry.short(50778, [21]), // CalibrationIlluminant1: D65
  ]..sort((a, b) => a.tag.compareTo(b.tag));

  // Layout: header(8) | IFD | out-of-line values | pixels.
  const ifdOffset = 8;
  final ifdSize = 2 + entries.length * 12 + 4;
  var extraOffset = ifdOffset + ifdSize;
  final extra = BytesBuilder();
  final valueOffsets = <int>[];
  for (final e in entries) {
    if (e.data.length > 4) {
      valueOffsets.add(extraOffset + extra.length);
      extra.add(e.data);
      if (extra.length.isOdd) extra.addByte(0); // word-align
    } else {
      valueOffsets.add(-1);
    }
  }
  extraOffset += extra.length;
  final pixelOffset = extraOffset;

  final out = BytesBuilder()
    ..add([0x49, 0x49, 42, 0]) // "II*\0"
    ..add(_u32(ifdOffset))
    ..add(_u16(entries.length));
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final data = e.tag == 273 ? _u32(pixelOffset) : e.data;
    out
      ..add(_u16(e.tag))
      ..add(_u16(e.type))
      ..add(_u32(e.count));
    if (valueOffsets[i] >= 0) {
      out.add(_u32(valueOffsets[i]));
    } else {
      out.add([...data, ...List.filled(4 - data.length, 0)]);
    }
  }
  out
    ..add(_u32(0)) // no next IFD
    ..add(extra.toBytes())
    ..add(
      pixels.buffer.asUint8List(0, pixels.lengthInBytes - truncate),
    );
  return out.toBytes();
}

class _Entry {
  _Entry(this.tag, this.type, this.count, this.data);

  factory _Entry.short(int tag, List<int> v) =>
      _Entry(tag, 3, v.length, [for (final x in v) ..._u16(x)]);
  factory _Entry.long(int tag, List<int> v) =>
      _Entry(tag, 4, v.length, [for (final x in v) ..._u32(x)]);
  factory _Entry.bytes(int tag, List<int> v) => _Entry(tag, 1, v.length, v);
  factory _Entry.ascii(int tag, String s) {
    final b = [...ascii.encode(s), 0];
    return _Entry(tag, 2, b.length, b);
  }
  factory _Entry.rational(int tag, List<int> numerators) => _Entry(
    tag,
    5,
    numerators.length,
    [
      for (final n in numerators) ...[..._u32(n), ..._u32(1)],
    ],
  );
  factory _Entry.srational(int tag, List<int> numerators) => _Entry(
    tag,
    10,
    numerators.length,
    [
      for (final n in numerators) ...[..._u32(n & 0xffffffff), ..._u32(1)],
    ],
  );

  final int tag;
  final int type;
  final int count;
  final List<int> data;
}

List<int> _u16(int v) => [v & 0xff, (v >> 8) & 0xff];
List<int> _u32(int v) => [
  v & 0xff,
  (v >> 8) & 0xff,
  (v >> 16) & 0xff,
  (v >> 24) & 0xff,
];
