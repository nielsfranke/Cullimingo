import 'package:cullimingo/features/cull/domain/cull_shortcuts.dart';
import 'package:cullimingo/features/cull/presentation/widgets/keyboard_shortcuts_dialog.dart';
import 'package:cullimingo/features/cull/presentation/widgets/keyboard_shortcuts_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('action groups cover every rebindable action exactly once', () {
    final listed = [
      for (final g in kShortcutActionGroups) ...g.actions,
    ];
    expect(listed.toSet(), CullAction.values.toSet());
    expect(listed.length, CullAction.values.length); // no dupes
  });

  testWidgets('cheat sheet shows live bindings and a Customize button', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showKeyboardShortcuts(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Keyboard shortcuts'), findsOneWidget);
    expect(find.text('Pick'), findsOneWidget);
    expect(find.text('Customize…'), findsOneWidget);
  });

  testWidgets('editor opens and lists rebindable actions', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showShortcutEditor(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Customize shortcuts'), findsOneWidget);
    expect(find.text('Reset to defaults'), findsOneWidget);
    expect(find.text('Pick'), findsOneWidget);
  });
}
