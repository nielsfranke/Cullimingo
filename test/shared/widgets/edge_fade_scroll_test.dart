import 'package:cullimingo/shared/widgets/edge_fade_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({required double width, required int items}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          height: 44,
          child: EdgeFadeScroll(
            builder: (context, controller) => ListView(
              controller: controller,
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < items; i++)
                  const SizedBox(width: 100, child: Text('x')),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('no fade when the content fits the viewport', (tester) async {
    // 2 items * 100 = 200 <= 400 viewport: nothing overflows.
    await tester.pumpWidget(_host(width: 400, items: 2));
    await tester.pump(); // let the post-frame edge check run
    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('fades the trailing edge when content overflows at rest', (
    tester,
  ) async {
    // 10 items * 100 = 1000 > 300 viewport, scrolled to the start: only the
    // trailing (right) edge has hidden content, so a mask appears.
    await tester.pumpWidget(_host(width: 300, items: 10));
    await tester.pump();
    expect(find.byType(ShaderMask), findsOneWidget);
  });

  testWidgets('keeps fading after scrolling into the middle', (tester) async {
    await tester.pumpWidget(_host(width: 300, items: 10));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(-200, 0));
    await tester.pump();
    // Both edges now overflow; the mask stays present.
    expect(find.byType(ShaderMask), findsOneWidget);
  });
}
