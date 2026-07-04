import 'package:cullimingo/features/filter/domain/filename_match.dart';
import 'package:cullimingo/features/handoff/domain/cs_models.dart';

/// A ContactSheet collection resolved to local photo ids, ready to persist as a
/// Cullimingo saved selection (`BUILD_PLAN.md` §5).
class CollectionSelection {
  /// Creates a resolved collection.
  const CollectionSelection({required this.name, required this.photoIds});

  /// The collection name (used as the saved-selection name).
  final String name;

  /// Matched local photo ids, in the collection's order, de-duplicated.
  final List<int> photoIds;
}

/// Resolves client [collections] to local saved selections. [images] (the
/// gallery's image list) maps each member image id → its filename, which is
/// matched to local [photos] by basename (extension-insensitive via
/// [normalizeName], so a JPEG proof's collection lands on the RAW). Collections
/// with no matched local photo are skipped. Pure — the page persists them.
List<CollectionSelection> resolveCollectionSelections(
  List<CsCollection> collections,
  List<CsImageMark> images,
  List<({int id, String path})> photos,
) {
  final filenameById = {for (final m in images) m.id: m.filename};
  final idsByName = <String, List<int>>{};
  for (final photo in photos) {
    idsByName.putIfAbsent(normalizeName(photo.path), () => []).add(photo.id);
  }

  final result = <CollectionSelection>[];
  for (final collection in collections) {
    final photoIds = <int>[];
    final seen = <int>{};
    for (final imageId in collection.imageIds) {
      final filename = filenameById[imageId];
      if (filename == null) continue;
      for (final id in idsByName[normalizeName(filename)] ?? const <int>[]) {
        if (seen.add(id)) photoIds.add(id);
      }
    }
    if (photoIds.isNotEmpty) {
      result.add(
        CollectionSelection(name: collection.name, photoIds: photoIds),
      );
    }
  }
  return result;
}
