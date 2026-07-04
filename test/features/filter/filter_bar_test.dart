import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/filter/presentation/filter_bar.dart';
import 'package:cullimingo/features/filter/presentation/filter_providers.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Photo _photo({int id = 1, String caption = ''}) {
  return Photo(
    id: id,
    importId: 1,
    path: '/x/$id.jpg',
    mtime: DateTime(2026),
    orientation: 1,
    userRotation: 0,
    hasCrop: false,
    rating: 0,
    flag: PickFlag.none,
    colorLabel: ColorLabel.none,
    keywords: const [],
    iptc: IptcCore(caption: caption),
    hasXmp: false,
    xmpConflict: false,
    previewCached: false,
    isRaw: false,
  );
}

void main() {
  testWidgets('Needs-caption chip counts blank captions and toggles the '
      'filter', (tester) async {
    tester.view.physicalSize = const Size(1600, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final photos = [
      _photo(caption: 'Winner celebrates'),
      _photo(id: 2),
      _photo(id: 3),
    ];
    final container = ProviderContainer(
      overrides: [photosProvider.overrideWith((ref) => Stream.value(photos))],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: FilterBar())),
      ),
    );
    await tester.pump(); // photos stream emits

    final chip = find.text('Needs caption (2)');
    expect(chip, findsOneWidget);

    await tester.tap(chip);
    await tester.pump();
    expect(
      container.read(photoFilterControllerProvider).needsCaption,
      isTrue,
    );
    expect(container.read(filteredPhotosProvider).map((p) => p.id), [2, 3]);

    await tester.tap(chip); // toggles back off
    await tester.pump();
    expect(
      container.read(photoFilterControllerProvider).needsCaption,
      isFalse,
    );
  });
}
