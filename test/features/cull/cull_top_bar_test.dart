import 'package:cullimingo/features/cull/presentation/widgets/cull_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    VoidCallback? onEditKeywords,
    VoidCallback? onEditMetadata,
    VoidCallback? onApplyTemplate,
    VoidCallback? onGeocode,
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CullTopBar(
              count: 2,
              onOpenFolder: () async {},
              onIngest: () async {},
              includeSubfolders: false,
              onIncludeSubfolders: (_) {},
              onSettings: () async {},
              onShortcuts: () {},
              inspectorOpen: false,
              onEditKeywords: onEditKeywords,
              onEditMetadata: onEditMetadata,
              onApplyTemplate: onApplyTemplate,
              onGeocode: onGeocode,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openMoreMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
  }

  testWidgets('More menu lists keyword, metadata and template entries with '
      'their shortcut hints', (tester) async {
    await pumpBar(
      tester,
      onEditKeywords: () {},
      onEditMetadata: () {},
      onApplyTemplate: () {},
    );
    await openMoreMenu(tester);

    expect(find.text('Edit keywords (K)'), findsOneWidget);
    expect(find.text('Edit metadata (M)'), findsOneWidget);
    expect(find.text('Apply metadata template (T)'), findsOneWidget);
  });

  testWidgets('selecting Edit metadata / Apply template fires the callbacks', (
    tester,
  ) async {
    var metadata = 0;
    var template = 0;
    await pumpBar(
      tester,
      onEditMetadata: () => metadata++,
      onApplyTemplate: () => template++,
    );

    await openMoreMenu(tester);
    await tester.tap(find.text('Edit metadata (M)'));
    await tester.pumpAndSettle();
    expect(metadata, 1);

    await openMoreMenu(tester);
    await tester.tap(find.text('Apply metadata template (T)'));
    await tester.pumpAndSettle();
    expect(template, 1);
  });

  testWidgets('menu entries hide when their callback is absent', (
    tester,
  ) async {
    await pumpBar(tester, onEditKeywords: () {});
    await openMoreMenu(tester);

    expect(find.text('Edit keywords (K)'), findsOneWidget);
    expect(find.text('Edit metadata (M)'), findsNothing);
    expect(find.text('Apply metadata template (T)'), findsNothing);
    expect(find.text('Fill location from GPS'), findsNothing);
  });

  testWidgets('selecting Fill location from GPS fires the callback', (
    tester,
  ) async {
    var geocoded = 0;
    await pumpBar(tester, onGeocode: () => geocoded++);

    await openMoreMenu(tester);
    await tester.tap(find.text('Fill location from GPS'));
    await tester.pumpAndSettle();
    expect(geocoded, 1);
  });
}
