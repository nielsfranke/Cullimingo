// Visual-check tool. Not part of the CI suite (no `_test` suffix); run on
// demand. Renders a sample grid of real PhotoCells with the real theme and
// writes a PNG via the golden mechanism, so the Aftershoot cell can be
// eyeballed without Xcode.
//
//   flutter test test/screenshot.dart --update-goldens
//
// Loads a macOS system font so text renders as real glyphs. Skips gracefully
// where that font is absent (e.g. CI).
import 'dart:io';

import 'package:cullimingo/app/theme/app_theme.dart';
import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/widgets/photo_cell.dart';
import 'package:cullimingo/features/filter/presentation/filter_bar.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _regular = '/System/Library/Fonts/Supplemental/Arial.ttf';
const _bold = '/System/Library/Fonts/Supplemental/Arial Bold.ttf';
const _materialIcons =
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/'
    'MaterialIcons-Regular.otf';

Future<void> _loadFontFamily(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final bytes = Uint8List.fromList(File(path).readAsBytesSync());
    loader.addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

Future<void> _loadFonts() async {
  await _loadFontFamily('CullSans', const [_regular, _bold]);
  if (File(_materialIcons).existsSync()) {
    await _loadFontFamily('MaterialIcons', const [_materialIcons]);
  }
}

Uint8List _swatch(int r, int g, int b) {
  final image = img.Image(width: 200, height: 200);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  return img.encodeJpg(image);
}

Photo _photo({
  required int id,
  required String name,
  int rating = 0,
  PickFlag flag = PickFlag.none,
  ColorLabel color = ColorLabel.none,
  bool isRaw = false,
}) {
  return Photo(
    id: id,
    importId: 1,
    path: '/cards/shootA/$name',
    mtime: DateTime(2026, 6, 2),
    orientation: 1,
    userRotation: 0,
    hasCrop: false,
    rating: rating,
    flag: flag,
    colorLabel: color,
    keywords: const [],
    iptc: const IptcCore(),
    hasXmp: false,
    xmpConflict: false,
    previewCached: false,
    isRaw: isRaw,
  );
}

void main() {
  testWidgets('render sample cull grid screenshot', (tester) async {
    if (!File(_regular).existsSync()) {
      markTestSkipped('System font not available on this platform.');
      return;
    }
    await _loadFonts();

    await tester.binding.setSurfaceSize(const Size(900, 560));
    tester.view.devicePixelRatio = 1;
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      tester.view.resetDevicePixelRatio();
    });

    final cells = <Widget>[
      PhotoCell(
        photo: _photo(
          id: 1,
          name: 'DSC_0001.JPG',
          rating: 5,
          flag: PickFlag.pick,
        ),
        thumbnail: _swatch(120, 140, 175),
        cellWidth: 200,
        focused: true,
      ),
      PhotoCell(
        photo: _photo(
          id: 2,
          name: 'DSC_0002.JPG',
          rating: 3,
          color: ColorLabel.green,
        ),
        thumbnail: _swatch(190, 150, 120),
        cellWidth: 200,
        selected: true,
      ),
      PhotoCell(
        photo: _photo(id: 3, name: 'DSC_0003.JPG', color: ColorLabel.red),
        thumbnail: _swatch(110, 160, 150),
        cellWidth: 200,
      ),
      PhotoCell(
        photo: _photo(id: 4, name: 'DSC_0004.ARW', isRaw: true),
        thumbnail: null,
        cellWidth: 200,
      ),
    ];

    final theme = buildDarkTheme();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'CullSans'),
        ),
        home: Scaffold(
          backgroundColor: AppColors.bgBase,
          body: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: GridView.count(
              crossAxisCount: 4,
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 200 / 196,
              children: cells,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('screenshots/cull_grid.png'),
    );
  });

  testWidgets('render filter bar screenshot', (tester) async {
    if (!File(_regular).existsSync()) {
      markTestSkipped('System font not available on this platform.');
      return;
    }
    await _loadFonts();

    await tester.binding.setSurfaceSize(const Size(900, 60));
    tester.view.devicePixelRatio = 1;
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      tester.view.resetDevicePixelRatio();
    });

    final photos = [
      for (var i = 0; i < 6; i++) _photo(id: i, name: 'p$i.jpg', rating: 5),
      for (var i = 6; i < 14; i++)
        _photo(id: i, name: 'p$i.jpg', flag: PickFlag.pick),
      for (var i = 14; i < 17; i++)
        _photo(id: i, name: 'p$i.jpg', flag: PickFlag.reject),
    ];

    final theme = buildDarkTheme();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          photosProvider.overrideWith((ref) => Stream.value(photos)),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'CullSans'),
          ),
          home: const Scaffold(
            backgroundColor: AppColors.bgBase,
            body: Column(children: [FilterBar()]),
          ),
        ),
      ),
    );
    await tester.pump(); // let the photos stream emit so counts populate

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('screenshots/filter_bar.png'),
    );
  });
}
