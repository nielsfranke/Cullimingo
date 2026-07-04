import 'package:cullimingo/features/cull/presentation/widgets/grid_zoom_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('resizes live during the drag and brackets it with start/end', (
    tester,
  ) async {
    final changes = <double>[];
    var starts = 0;
    var ends = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: GridZoomSlider(
                value: 200,
                onChanged: changes.add,
                onZoomStart: () => starts++,
                onZoomEnd: () => ends++,
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Slider)),
    );
    await tester.pump();

    // The drag opened with exactly one start signal (freeze decode + capture
    // anchor), and nothing has ended yet.
    expect(starts, 1);
    expect(ends, 0);

    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();

    // The width changed *live* during the drag (grid resizes every frame)…
    expect(changes, isNotEmpty);

    await gesture.up();
    await tester.pump();

    // …and the drag closed with exactly one end signal (re-decode + re-anchor).
    expect(ends, 1);
  });
}
