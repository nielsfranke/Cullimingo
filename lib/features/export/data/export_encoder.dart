import 'dart:convert';
import 'dart:typed_data';

import 'package:cullimingo/core/vips/vips_encoder.dart';
import 'package:cullimingo/features/export/domain/export_preset.dart';
import 'package:cullimingo/features/metadata/data/iptc_iim.dart';
import 'package:cullimingo/features/metadata/data/xmp_codec.dart';
import 'package:cullimingo/features/metadata/domain/xmp_data.dart';
import 'package:image/image.dart' as img;

/// The APP1 header that marks an XMP packet in a JPEG (NUL-terminated).
const String _xmpApp1Header = 'http://ns.adobe.com/xap/1.0/\x00';

/// Injects [xmp] (a full XMP packet) into [jpeg] as an APP1 segment right after
/// the SOI marker, so the exported JPEG carries the photo's IPTC (caption,
/// creator, credit, copyright, keywords…). The `image` package can't write XMP,
/// so we splice the segment in by hand — this is what stops delivered JPEGs
/// from going out "naked" (`BUILD_PLAN.md` §6 / IPTC guide §12).
///
/// Returns [jpeg] unchanged if it isn't a JPEG, [xmp] is empty, or the packet
/// is too large for a single APP1 segment (~64 KB — far beyond any caption).
Uint8List embedXmpInJpeg(Uint8List jpeg, String xmp) {
  if (xmp.isEmpty) return jpeg;
  if (jpeg.length < 2 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) return jpeg;

  final header = ascii.encode(_xmpApp1Header);
  final payload = utf8.encode(xmp);
  final segmentLength =
      2 + header.length + payload.length; // incl. length bytes
  if (segmentLength > 0xFFFF) return jpeg;

  return (BytesBuilder()
        ..add(const [0xFF, 0xD8]) // SOI
        ..add([
          0xFF,
          0xE1, // APP1 marker
          (segmentLength >> 8) & 0xFF,
          segmentLength & 0xFF,
        ])
        ..add(header)
        ..add(payload)
        ..add(jpeg.sublist(2))) // the rest of the original JPEG after SOI
      .toBytes();
}

/// A mild 3×3 sharpen kernel (sum = 1), applied after downscaling when the
/// preset asks for it — useful for web/proof JPEGs that soften on resize.
const List<num> _sharpenKernel = [0, -1, 0, -1, 5, -1, 0, -1, 0];

/// Decodes [bytes] (an embedded RAW preview or a bitmap file), bakes EXIF
/// orientation (clearing the orientation tag so viewers don't double-rotate),
/// downscales so the long edge is ≤ [longEdge] (never upscaling), optionally
/// [sharpen]s, and re-encodes as JPEG at [quality] (`BUILD_PLAN.md` §6,
/// embedded-resize path). The decoded EXIF/ICC ride along into the output.
///
/// When [maxBytes] is set, quality is stepped down (to a floor of 20) until the
/// JPEG fits the target size — handy for web/email proofs. Returns `null` if
/// the source can't be decoded.
///
/// Pure and isolate-safe: JPEG encodes via the `image` package (with the
/// proven XMP-APP1 + IIM-APP13 byte splicing); [ExportFormat.webp] /
/// [ExportFormat.avif] hand the processed pixels to the bundled libvips
/// (which embeds the XMP itself; IIM is a JPEG-only construct).
Uint8List? renderExportBytes(
  Uint8List bytes, {
  required int longEdge,
  required int quality,
  ExportFormat format = ExportFormat.jpeg,
  bool sharpen = false,
  int? maxBytes,
  XmpData? meta,
  int userRotation = 0,
}) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object {
    return null;
  }
  if (decoded == null) return null;
  // Bake the file's EXIF orientation, then the user's extra clockwise
  // quarter-turns (copyRotate is CW for positive degrees, matching the grid's
  // RotatedBox), so exported proofs show the same orientation as the app.
  var oriented = img.bakeOrientation(decoded);
  final turns = ((userRotation % 4) + 4) % 4;
  if (turns != 0) {
    oriented = img.copyRotate(oriented, angle: turns * 90);
  }

  final maxEdge = oriented.width >= oriented.height
      ? oriented.width
      : oriented.height;
  var out = maxEdge <= longEdge
      ? oriented
      : (oriented.width >= oriented.height
            ? img.copyResize(oriented, width: longEdge)
            : img.copyResize(oriented, height: longEdge));

  if (sharpen) {
    out = img.convolution(out, filter: _sharpenKernel);
  }

  var q = quality.clamp(1, 100);
  if (format != ExportFormat.jpeg) {
    final vips = VipsEncoder.instance();
    if (vips == null) return null;
    final rgb = out
        .convert(format: img.Format.uint8, numChannels: 3)
        .getBytes(order: img.ChannelOrder.rgb);
    final xmp = meta == null ? null : encodeXmp(meta);
    Uint8List? encode(int quality) => vips.encodeRgb(
      rgb: rgb,
      width: out.width,
      height: out.height,
      quality: quality,
      avif: format == ExportFormat.avif,
      xmp: xmp,
    );
    var encoded = encode(q);
    while (encoded != null &&
        maxBytes != null &&
        encoded.lengthInBytes > maxBytes &&
        q > 20) {
      q -= 10;
      encoded = encode(q);
    }
    return encoded;
  }

  var jpeg = img.encodeJpg(out, quality: q);
  // Shrink to a target size by lowering quality, never below a usable floor.
  // Size against the final bytes *with* the metadata, so the target holds.
  while (maxBytes != null &&
      _withMeta(jpeg, meta).lengthInBytes > maxBytes &&
      q > 20) {
    q -= 10;
    jpeg = img.encodeJpg(out, quality: q);
  }
  return _withMeta(jpeg, meta);
}

/// Backwards-compatible JPEG-only entry point (the original encoder name).
Uint8List? renderExportJpeg(
  Uint8List bytes, {
  required int longEdge,
  required int quality,
  bool sharpen = false,
  int? maxBytes,
  XmpData? meta,
  int userRotation = 0,
}) => renderExportBytes(
  bytes,
  longEdge: longEdge,
  quality: quality,
  sharpen: sharpen,
  maxBytes: maxBytes,
  meta: meta,
  userRotation: userRotation,
);

/// Embeds [meta] into [jpeg] as both a modern XMP (APP1) and a legacy IPTC IIM
/// (APP13) block, so modern *and* purely-IIM readers see the caption/credit.
Uint8List _withMeta(Uint8List jpeg, XmpData? meta) {
  if (meta == null) return jpeg;
  return embedIptcIimInJpeg(embedXmpInJpeg(jpeg, encodeXmp(meta)), meta);
}
