import 'package:cullimingo/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CullimingoApp opens on the empty cull page', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CullimingoApp()));
    // Let the photos stream emit its initial empty list (was AsyncLoading).
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(
      find.text('Open a folder of RAWs or JPEGs to start culling'),
      findsOneWidget,
    );
  });
}
