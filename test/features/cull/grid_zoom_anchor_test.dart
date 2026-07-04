import 'package:cullimingo/features/cull/domain/grid_zoom_anchor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('zoomAnchor', () {
    test(
      'anchors the item nearest the viewport centre when nothing focused',
      () {
        // 4 columns, 100px rows, viewport 300px scrolled to row 5 (offset 500).
        // Centre is at y=650 → row 6 → index 24.
        final anchor = zoomAnchor(
          offset: 500,
          viewportHeight: 300,
          columns: 4,
          rowHeight: 100,
          count: 100,
          focusedIndex: -1,
        );

        expect(anchor, isNotNull);
        expect(anchor!.index, 24);
        // Row 6 top is 600px; 100px below the 500px scroll offset.
        expect(anchor.screenY, 100);
      },
    );

    test('prefers the focused item when its row is on screen', () {
      // Focused index 8 sits on row 2 (top 200px), inside the 0–300 viewport.
      final anchor = zoomAnchor(
        offset: 0,
        viewportHeight: 300,
        columns: 4,
        rowHeight: 100,
        count: 100,
        focusedIndex: 8,
      );

      expect(anchor!.index, 8);
      expect(anchor.screenY, 200);
    });

    test('ignores the focused item when its row is off screen', () {
      // Focused index 80 (row 20, top 2000px) is far below the viewport, so
      // the centre item wins instead.
      final anchor = zoomAnchor(
        offset: 0,
        viewportHeight: 300,
        columns: 4,
        rowHeight: 100,
        count: 100,
        focusedIndex: 80,
      );

      expect(anchor!.index, isNot(80));
    });

    test('returns null for an empty or unmeasured grid', () {
      expect(
        zoomAnchor(
          offset: 0,
          viewportHeight: 300,
          columns: 4,
          rowHeight: 100,
          count: 0,
          focusedIndex: -1,
        ),
        isNull,
      );
      expect(
        zoomAnchor(
          offset: 0,
          viewportHeight: 300,
          columns: 0,
          rowHeight: 100,
          count: 10,
          focusedIndex: -1,
        ),
        isNull,
      );
    });
  });

  group('zoomReanchorOffset', () {
    test('keeps the anchor row at the same on-screen y after a zoom', () {
      // Anchor was index 24 (4 cols → row 6), sitting 100px below the top.
      const anchor = (index: 24, screenY: 100.0);

      // Zoom out: now 6 columns, 60px rows. Index 24 → row 4 (top 240px).
      // Offset must place row 4's top at y=100 → 240 - 100 = 140.
      final offset = zoomReanchorOffset(
        anchor: anchor,
        columns: 6,
        rowHeight: 60,
        maxScrollExtent: 10000,
      );

      expect(offset, 140);
    });

    test('keeps the focused row in view when the inspector narrows it', () {
      // The inspector panel opening drops the grid from 6 to 4 columns with the
      // row height unchanged. The focused item (index 25) was at the top of the
      // viewport (screenY 0); it must stay visible after the reflow.
      const anchor = (index: 25, screenY: 0.0);

      // 6 cols → index 25 was on row 4. 4 cols → row 6 (top 6*100 = 600px).
      final offset = zoomReanchorOffset(
        anchor: anchor,
        columns: 4,
        rowHeight: 100,
        maxScrollExtent: 10000,
      );

      // Row 6's top pinned to y=0 → offset 600, so the focused cell stays put.
      expect(offset, 600);
    });

    test('clamps to the scroll extent', () {
      const anchor = (index: 0, screenY: -50.0);

      final offset = zoomReanchorOffset(
        anchor: anchor,
        columns: 4,
        rowHeight: 100,
        maxScrollExtent: 30,
      );

      // Raw target would be 0 - (-50) = 50, clamped to the 30px max.
      expect(offset, 30);
    });
  });
}
