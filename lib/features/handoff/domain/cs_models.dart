/// A ContactSheet gallery, as returned by the API (`GET/POST /api/galleries`).
/// `GET /api/galleries` returns a **nested tree** — each node carries its
/// [children], so the picker can show the structure (and not drop
/// sub-galleries).
class CsGallery {
  /// Creates a gallery.
  const CsGallery({
    required this.id,
    required this.name,
    required this.shareToken,
    this.parentId,
    this.imageCount = 0,
    this.coverImageUrl,
    this.children = const [],
  });

  /// Parses one gallery JSON object, recursing into nested `children`.
  factory CsGallery.fromJson(Map<String, dynamic> json) => CsGallery(
    id: json['id'] as String,
    name: json['name'] as String,
    shareToken: json['share_token'] as String? ?? '',
    parentId: json['parent_id'] as String?,
    imageCount: (json['image_count'] as num?)?.toInt() ?? 0,
    coverImageUrl: json['cover_image_url'] as String?,
    children: [
      for (final c in (json['children'] as List<dynamic>? ?? const []))
        CsGallery.fromJson(c as Map<String, dynamic>),
    ],
  );

  /// Server gallery id.
  final String id;

  /// Display name.
  final String name;

  /// Public share token (the `/g/{token}` link; used later by the pull side).
  final String shareToken;

  /// Parent gallery id, or null for a top-level gallery.
  final String? parentId;

  /// Number of images directly in this gallery.
  final int imageCount;

  /// Cover-thumbnail URL (may be relative to the server base URL), or null.
  final String? coverImageUrl;

  /// Nested sub-galleries.
  final List<CsGallery> children;
}

/// One uploaded image, as returned by `POST /api/galleries/{id}/images`.
class CsUpload {
  /// Creates an upload result.
  const CsUpload({
    required this.id,
    required this.originalFilename,
    required this.processingStatus,
  });

  /// Parses one upload-response JSON object.
  factory CsUpload.fromJson(Map<String, dynamic> json) => CsUpload(
    id: json['id'] as String,
    originalFilename: json['original_filename'] as String,
    processingStatus: json['processing_status'] as String,
  );

  /// Server image id.
  final String id;

  /// The filename the server stored it under.
  final String originalFilename;

  /// Processing status (e.g. `pending`, `ready`).
  final String processingStatus;
}

/// One image's client-review state, from `GET /g/{share_token}/images` — the
/// pull side (`BUILD_PLAN.md` §7b).
class CsImageMark {
  /// Creates a mark.
  const CsImageMark({
    required this.id,
    required this.filename,
    required this.rating,
    required this.colorFlag,
    required this.likes,
  });

  /// Parses one public image JSON object.
  factory CsImageMark.fromJson(Map<String, dynamic> json) => CsImageMark(
    id: json['id'] as String? ?? '',
    filename: json['original_filename'] as String,
    rating: (json['rating'] as num?)?.toInt() ?? 0,
    colorFlag: json['color_flag'] as String? ?? 'none',
    likes: (json['likes'] as num?)?.toInt() ?? 0,
  );

  /// Server image id (links a collection's `image_ids` to a [filename]).
  final String id;

  /// The image's original filename (matched to local photos by basename).
  final String filename;

  /// Client star rating, 0 = unrated.
  final int rating;

  /// Client colour flag: one of none/red/yellow/green/blue.
  final String colorFlag;

  /// Like count (>0 means the client liked it).
  final int likes;
}

/// A client-made collection (a named set of images), from
/// `GET /api/public/g/{share_token}/collections`. Maps to a Cullimingo saved
/// selection (`BUILD_PLAN.md` §5). [imageIds] are server image ids, resolved to
/// filenames via the gallery's image list.
class CsCollection {
  /// Creates a collection.
  const CsCollection({
    required this.id,
    required this.name,
    required this.imageIds,
  });

  /// Parses one collection JSON object.
  factory CsCollection.fromJson(Map<String, dynamic> json) => CsCollection(
    id: json['id'] as String,
    name: json['name'] as String,
    imageIds: [
      for (final e in (json['image_ids'] as List<dynamic>? ?? const []))
        e as String,
    ],
  );

  /// Server collection id.
  final String id;

  /// Collection name (becomes the saved-selection name).
  final String name;

  /// Member image ids, in the collection's order.
  final List<String> imageIds;
}
