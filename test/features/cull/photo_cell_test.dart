import 'dart:typed_data';

import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/cull/presentation/widgets/photo_cell.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Photo _photo({
  String caption = '',
  ColorLabel color = ColorLabel.none,
  int userRotation = 0,
  bool hasCrop = false,
}) {
  return Photo(
    id: 1,
    importId: 1,
    path: '/x/DSC_0001.jpg',
    mtime: DateTime(2026),
    orientation: 1,
    userRotation: userRotation,
    hasCrop: hasCrop,
    rating: 0,
    flag: PickFlag.none,
    colorLabel: color,
    keywords: const [],
    iptc: IptcCore(caption: caption),
    hasXmp: false,
    xmpConflict: false,
    previewCached: false,
    isRaw: false,
  );
}

Future<void> _pumpCell(WidgetTester tester, Photo photo) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 200,
        height: 200,
        child: PhotoCell(photo: photo, thumbnail: null, cellWidth: 200),
      ),
    ),
  ),
);

void main() {
  testWidgets('a captioned photo shows the caption badge with a preview '
      'tooltip', (tester) async {
    await _pumpCell(tester, _photo(caption: 'Winner crosses the line'));

    final badge = find.byIcon(Icons.notes_rounded);
    expect(badge, findsOneWidget);
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: badge, matching: find.byType(Tooltip)),
    );
    expect(tooltip.message, 'Winner crosses the line');
  });

  testWidgets('no badge without a caption (blank counts as none)', (
    tester,
  ) async {
    await _pumpCell(tester, _photo(caption: '   '));
    expect(find.byIcon(Icons.notes_rounded), findsNothing);
  });

  testWidgets('badge coexists with a colour dot', (tester) async {
    await _pumpCell(
      tester,
      _photo(caption: 'Podium', color: ColorLabel.green),
    );
    expect(find.byIcon(Icons.notes_rounded), findsOneWidget);
  });

  testWidgets('the reference frame shows a bracket badge with its count', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 200,
            child: PhotoCell(
              photo: _photo(),
              thumbnail: null,
              cellWidth: 200,
              bracketSize: 3,
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.layers_rounded), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('no bracket badge on a non-reference / non-bracket frame', (
    tester,
  ) async {
    await _pumpCell(tester, _photo()); // bracketSize defaults to 0
    expect(find.byIcon(Icons.layers_rounded), findsNothing);
  });

  testWidgets('a cropped photo shows the crop badge', (tester) async {
    await _pumpCell(tester, _photo(hasCrop: true));
    expect(find.byIcon(Icons.crop_rounded), findsOneWidget);
  });

  testWidgets('no crop badge when the photo is uncropped', (tester) async {
    await _pumpCell(tester, _photo());
    expect(find.byIcon(Icons.crop_rounded), findsNothing);
  });

  testWidgets('hover reveals rotate + metadata actions that fire callbacks', (
    tester,
  ) async {
    var turns = 0;
    var editMeta = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 200,
            child: PhotoCell(
              photo: _photo(),
              thumbnail: null,
              cellWidth: 200,
              onRotateLeft: () => turns--,
              onRotateRight: () => turns++,
              onEditMetadata: () => editMeta++,
            ),
          ),
        ),
      ),
    );

    // No action bar until the pointer hovers the cell.
    expect(find.byIcon(Icons.rotate_right_rounded), findsNothing);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(PhotoCell)));
    await tester.pump();

    expect(find.byIcon(Icons.rotate_left_rounded), findsOneWidget);
    expect(find.byIcon(Icons.rotate_right_rounded), findsOneWidget);
    expect(find.byIcon(Icons.edit_note_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.rotate_right_rounded));
    await tester.tap(find.byIcon(Icons.edit_note_rounded));
    expect(turns, 1);
    expect(editMeta, 1);
  });

  testWidgets('the preview is wrapped in a RotatedBox by userRotation', (
    tester,
  ) async {
    final jpeg = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 8, height: 6)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 200,
            child: PhotoCell(
              photo: _photo(userRotation: 3),
              thumbnail: jpeg,
              cellWidth: 200,
            ),
          ),
        ),
      ),
    );

    final rotated = tester.widget<RotatedBox>(
      find.ancestor(
        of: find.byType(Image),
        matching: find.byType(RotatedBox),
      ),
    );
    expect(rotated.quarterTurns, 3);
  });
}
