import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/filter/domain/photo_filter.dart';
import 'package:cullimingo/features/filter/presentation/filter_bar.dart';
import 'package:cullimingo/features/filter/presentation/filter_providers.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Photo _photo({
  int id = 1,
  String caption = '',
  String? path,
  bool isRaw = false,
}) {
  return Photo(
    id: id,
    importId: 1,
    path: path ?? '/x/$id.jpg',
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
    isRaw: isRaw,
  );
}

Future<ProviderContainer> _pumpBar(
  WidgetTester tester,
  List<Photo> photos,
) async {
  tester.view.physicalSize = const Size(1600, 400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

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
  return container;
}

void main() {
  testWidgets('Needs-caption entry counts blank captions and toggles the '
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

    // "Needs caption" now lives inside the "Metadata" dropdown.
    await tester.tap(find.text('Metadata'));
    await tester.pumpAndSettle();

    final entry = find.text('Needs caption (2)');
    expect(entry, findsOneWidget);

    await tester.tap(entry);
    await tester.pump();
    expect(
      container.read(photoFilterControllerProvider).needsCaption,
      isTrue,
    );
    expect(container.read(filteredPhotosProvider).map((p) => p.id), [2, 3]);

    // The menu stays open (closeOnActivate: false), so the entry can be tapped
    // again to toggle it back off.
    await tester.tap(entry);
    await tester.pump();
    expect(
      container.read(photoFilterControllerProvider).needsCaption,
      isFalse,
    );
  });

  testWidgets(
    'Grouping dropdown offers the file-type radio on a mixed folder',
    (
      tester,
    ) async {
      final container = await _pumpBar(tester, [
        _photo(path: '/c/1.ARW', isRaw: true),
        _photo(id: 2, path: '/c/2.JPG'),
      ]);

      // The RAW/JPEG radios live inside the "Grouping" dropdown, shown because
      // the folder mixes both types.
      await tester.tap(find.text('Grouping'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('JPEG only (1)'));
      await tester.pump();
      expect(
        container.read(photoFilterControllerProvider).fileType,
        FileTypeFilter.jpeg,
      );
      expect(container.read(filteredPhotosProvider).map((p) => p.id), [2]);
    },
  );

  testWidgets('file-type radio stays reachable while active on an unmixed '
      'folder', (tester) async {
    // A RAW-only folder, but a JPEG filter is somehow still active (e.g. the
    // user filtered to JPEG then deleted every JPEG). The radio must remain so
    // they can clear it — not vanish with the filter stuck on.
    final container = await _pumpBar(tester, [
      _photo(path: '/c/1.ARW', isRaw: true),
    ]);
    container
        .read(photoFilterControllerProvider.notifier)
        .setFileType(FileTypeFilter.jpeg);
    await tester.pump();

    await tester.tap(find.text('Grouping'));
    await tester.pumpAndSettle();
    expect(find.text('All file types'), findsOneWidget);

    await tester.tap(find.text('All file types'));
    await tester.pump();
    expect(
      container.read(photoFilterControllerProvider).fileType,
      FileTypeFilter.all,
    );
  });

  testWidgets('the search box filters the grid live by filename', (
    tester,
  ) async {
    final container = await _pumpBar(tester, [
      _photo(path: '/c/DSC_0042.ARW', isRaw: true),
      _photo(id: 2, path: '/c/DSC_0099.JPG'),
    ]);

    await tester.enterText(find.byType(TextField), 'dsc_004');
    await tester.pump();

    expect(container.read(photoFilterControllerProvider).query, 'dsc_004');
    expect(container.read(filteredPhotosProvider).map((p) => p.id), [1]);

    // Clearing the whole filter via "All" empties the search box too.
    await tester.tap(find.text('All (2)'));
    await tester.pump();
    expect(container.read(photoFilterControllerProvider).query, '');
    expect(find.text('dsc_004'), findsNothing);
  });
}
