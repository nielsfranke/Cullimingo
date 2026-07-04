import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/widgets/grid_zoom_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, List<double> commits) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                child: GridZoomSlider(value: 200, onCommit: commits.add),
              ),
            ),
          ),
        ),
      );

  testWidgets('commits the width only when the drag ends, not mid-drag', (
    tester,
  ) async {
    final commits = <double>[];
    await pump(tester, commits);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Slider)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();

    // The thumb has moved, but nothing has been committed yet — so the grid
    // hasn't reflowed / re-decoded / re-anchored during the drag.
    expect(commits, isEmpty);

    await gesture.up();
    await tester.pump();

    // Exactly one commit, on release, within the allowed range.
    expect(commits, hasLength(1));
    expect(
      commits.single,
      inInclusiveRange(GridCellWidth.min, GridCellWidth.max),
    );
  });
}
