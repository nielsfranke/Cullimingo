import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/filter/domain/photo_filter.dart';
import 'package:cullimingo/features/filter/presentation/filter_providers.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Photo _photo({
  int id = 1,
  int rating = 0,
  PickFlag flag = PickFlag.none,
  ColorLabel color = ColorLabel.none,
  List<String> keywords = const [],
  String caption = '',
  String? path,
  bool isRaw = false,
  DateTime? capturedAt,
  String? camera,
  double? exposureBias,
  double? exposureTime,
}) {
  return Photo(
    id: id,
    importId: 1,
    path: path ?? '/x/$id.jpg',
    mtime: DateTime(2026),
    capturedAt: capturedAt,
    camera: camera,
    orientation: 1,
    userRotation: 0,
    hasCrop: false,
    rating: rating,
    flag: flag,
    colorLabel: color,
    keywords: keywords,
    iptc: IptcCore(caption: caption),
    hasXmp: false,
    xmpConflict: false,
    previewCached: false,
    isRaw: isRaw,
    exposureBias: exposureBias,
    exposureTime: exposureTime,
  );
}

void main() {
  group('PhotoFilter.matches', () {
    test('an empty filter matches everything', () {
      const filter = PhotoFilter();
      expect(filter.isActive, isFalse);
      expect(filter.matches(_photo()), isTrue);
      expect(filter.matches(_photo(rating: 5, flag: PickFlag.reject)), isTrue);
    });

    test('rating threshold is inclusive', () {
      const filter = PhotoFilter(minRating: 3);
      expect(filter.matches(_photo(rating: 2)), isFalse);
      expect(filter.matches(_photo(rating: 3)), isTrue);
    });

    test('flag and colour must match exactly', () {
      const filter = PhotoFilter(flag: PickFlag.pick, color: ColorLabel.green);
      expect(filter.matches(_photo(flag: PickFlag.pick)), isFalse);
      expect(
        filter.matches(_photo(flag: PickFlag.pick, color: ColorLabel.green)),
        isTrue,
      );
    });

    test('has-keyword requires at least one keyword', () {
      const filter = PhotoFilter(hasKeyword: true);
      expect(filter.isActive, isTrue);
      expect(filter.matches(_photo()), isFalse);
      expect(filter.matches(_photo(keywords: ['cat'])), isTrue);
    });

    test('needs-caption passes only photos with a blank caption', () {
      const filter = PhotoFilter(needsCaption: true);
      expect(filter.isActive, isTrue);
      expect(filter.matches(_photo()), isTrue);
      expect(filter.matches(_photo(caption: '   ')), isTrue); // blank counts
      expect(filter.matches(_photo(caption: 'Finish line')), isFalse);
      expect(filter.withNeedsCaption(false).isActive, isFalse);
    });

    test(
      'selected-only is active but ignored by matches (provider applies it)',
      () {
        const filter = PhotoFilter(selectedOnly: true);
        expect(filter.isActive, isTrue);
        expect(filter.matches(_photo()), isTrue);
      },
    );

    test('withColor(null) clears the colour constraint', () {
      const filter = PhotoFilter(color: ColorLabel.red);
      expect(filter.withColor(null).color, isNull);
      expect(filter.withColor(null).isActive, isFalse);
    });

    test('collapse-brackets is active and survives a json round-trip', () {
      const filter = PhotoFilter(collapseBrackets: true);
      expect(filter.isActive, isTrue);
      expect(filter.matches(_photo()), isTrue); // provider applies it, not this
      expect(
        PhotoFilter.fromJson(filter.toJson()).collapseBrackets,
        isTrue,
      );
      expect(filter.withCollapseBrackets(false).isActive, isFalse);
    });
  });

  group('filteredPhotosProvider', () {
    final photos = [
      _photo(rating: 5, flag: PickFlag.pick),
      _photo(id: 2, rating: 2),
      _photo(id: 3, flag: PickFlag.reject, color: ColorLabel.red),
    ];

    test('reflects the active filter and its toggles', () async {
      final container = ProviderContainer(
        overrides: [photosProvider.overrideWith((ref) => Stream.value(photos))],
      );
      addTearDown(container.dispose);
      // Riverpod 3 pauses unobserved providers; a listener keeps the stream
      // active so its first value resolves.
      container.listen(photosProvider, (_, _) {});
      await container.read(photosProvider.future);

      expect(container.read(filteredPhotosProvider), hasLength(3));

      final filter = container.read(photoFilterControllerProvider.notifier)
        ..toggleFlag(PickFlag.pick);
      expect(container.read(filteredPhotosProvider).single.id, 1);

      filter.toggleFlag(PickFlag.pick); // toggles back off
      expect(container.read(filteredPhotosProvider), hasLength(3));

      filter.toggleMinRating(3);
      expect(container.read(filteredPhotosProvider).map((p) => p.id), [1]);
    });

    test('selected-only intersects with the live grid selection', () async {
      final container = ProviderContainer(
        overrides: [photosProvider.overrideWith((ref) => Stream.value(photos))],
      );
      addTearDown(container.dispose);
      container.listen(photosProvider, (_, _) {});
      await container.read(photosProvider.future);

      container.read(cullControllerProvider.notifier).setSelection({2, 3});
      container
          .read(photoFilterControllerProvider.notifier)
          .toggleSelectedOnly();

      expect(container.read(filteredPhotosProvider).map((p) => p.id), [2, 3]);

      // Deselecting updates the filtered set live.
      container.read(cullControllerProvider.notifier).toggleSelect(2);
      expect(container.read(filteredPhotosProvider).map((p) => p.id), [3]);
    });

    test('keyworded toggle keeps only photos with keywords', () async {
      final tagged = [
        _photo(keywords: ['sky']),
        _photo(id: 2),
      ];
      final container = ProviderContainer(
        overrides: [
          photosProvider.overrideWith((ref) => Stream.value(tagged)),
        ],
      );
      addTearDown(container.dispose);
      container.listen(photosProvider, (_, _) {});
      await container.read(photosProvider.future);

      container.read(photoFilterControllerProvider.notifier).toggleHasKeyword();
      expect(container.read(filteredPhotosProvider).map((p) => p.id), [1]);
    });

    test('needs-caption toggle keeps only photos without a caption', () async {
      final captioned = [
        _photo(caption: 'Winner celebrates'),
        _photo(id: 2),
      ];
      final container = ProviderContainer(
        overrides: [
          photosProvider.overrideWith((ref) => Stream.value(captioned)),
        ],
      );
      addTearDown(container.dispose);
      container.listen(photosProvider, (_, _) {});
      await container.read(photosProvider.future);

      container
          .read(photoFilterControllerProvider.notifier)
          .toggleNeedsCaption();
      expect(container.read(filteredPhotosProvider).map((p) => p.id), [2]);
    });

    test('hide-JPEG drops the JPEG side of a RAW+JPEG pair', () async {
      final paired = [
        _photo(path: '/c/_AIV1.ARW', isRaw: true), // id 1
        _photo(id: 2, path: '/c/_AIV1.JPG'), // pairs with id 1
        _photo(id: 3, path: '/c/_AIV2.JPG'), // unpaired JPEG, stays
      ];
      final container = ProviderContainer(
        overrides: [
          photosProvider.overrideWith((ref) => Stream.value(paired)),
        ],
      );
      addTearDown(container.dispose);
      container.listen(photosProvider, (_, _) {});
      await container.read(photosProvider.future);

      container
          .read(photoFilterControllerProvider.notifier)
          .toggleHideJpegPairs();
      expect(container.read(filteredPhotosProvider).map((p) => p.id), [1, 3]);
    });

    test('collapse-brackets shows only reference frames + non-brackets', () {
      DateTime at(int s) =>
          DateTime(2026, 5, 29, 12, 44).add(Duration(seconds: s));
      final shoot = [
        // One 0/+3/−3 bracket: id 1 is the 0 EV reference.
        _photo(camera: 'Fuji', capturedAt: at(0), exposureBias: 0),
        _photo(id: 2, camera: 'Fuji', capturedAt: at(1), exposureBias: 3),
        _photo(id: 3, camera: 'Fuji', capturedAt: at(2), exposureBias: -3),
        // A lone drone frame — not a bracket, always visible.
        _photo(id: 4, camera: 'DJI', capturedAt: at(600), exposureBias: 0),
      ];
      final container = ProviderContainer(
        overrides: [photosProvider.overrideWith((ref) => Stream.value(shoot))],
      );
      addTearDown(container.dispose);
      container.listen(photosProvider, (_, _) {});

      return container.read(photosProvider.future).then((_) {
        expect(container.read(bracketGroupsProvider).bracketCount, 1);
        container
            .read(photoFilterControllerProvider.notifier)
            .toggleCollapseBrackets();
        // Reference frame (1) + the non-bracket drone frame (4) survive.
        expect(container.read(filteredPhotosProvider).map((p) => p.id), [1, 4]);
        // Turning it back off restores the hidden bracket members.
        container
            .read(photoFilterControllerProvider.notifier)
            .toggleCollapseBrackets();
        expect(
          container.read(filteredPhotosProvider).map((p) => p.id),
          [1, 2, 3, 4],
        );
      });
    });
  });
}
