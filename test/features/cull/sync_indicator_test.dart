import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/widgets/cull_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ProviderContainer> pumpBar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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
            ),
          ),
        ),
      ),
    );
    return container;
  }

  testWidgets('shows "Syncing N…" only while sidecar writes are pending', (
    tester,
  ) async {
    final container = await pumpBar(tester);

    // Idle: nothing shown.
    expect(find.textContaining('Syncing'), findsNothing);

    // Writes in flight → the count appears.
    container.read(sidecarSyncProvider.notifier).add(7);
    await tester.pump();
    expect(find.text('Syncing 7…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Drained → it hides again.
    container.read(sidecarSyncProvider.notifier).add(-7);
    await tester.pump();
    expect(find.textContaining('Syncing'), findsNothing);
  });
}
