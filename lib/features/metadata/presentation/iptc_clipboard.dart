import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:flutter/foundation.dart';

/// A session-scoped clipboard of IPTC field values, à la Photo Mechanic's
/// Copy/Paste in the metadata dialog: snapshot every field off one photo and
/// stamp them onto another. In-memory only (not persisted across launches, like
/// PM's own metadata clipboard). Held as a [ValueNotifier] so the Paste button
/// can enable itself the moment something is copied.
final ValueNotifier<Map<IptcField, String>?> iptcClipboard =
    ValueNotifier<Map<IptcField, String>?>(null);
