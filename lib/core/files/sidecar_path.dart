import 'package:path/path.dart' as p;

/// Sidecar path for [photoPath]: same folder, basename + `.xmp` — the
/// Lightroom/Bridge convention for proprietary RAW (`DSC0001.ARW` →
/// `DSC0001.xmp`).
///
/// Lives in core (not the metadata feature) because copy/move/rename/delete
/// flows across features pair the sidecar with its photo — only the XMP
/// *content* handling belongs to metadata.
String sidecarPath(String photoPath) => p.setExtension(photoPath, '.xmp');
