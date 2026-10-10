import 'package:cullimingo/features/cull/data/reject_deleter.dart';
import 'package:cullimingo/features/cull/presentation/widgets/delete_rejects_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<TrashFallback? Function()> open(WidgetTester tester) async {
    TrashFallback? result;
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showTrashUnavailableDialog(context, count: 3);
              done = true;
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return () {
      expect(done, isTrue, reason: 'dialog still open');
      return result;
    };
  }

  testWidgets('offers the _Rejected folder first', (tester) async {
    final result = await open(tester);
    expect(find.text('Trash not available'), findsOneWidget);
    await tester.tap(find.text('Move to _Rejected'));
    await tester.pumpAndSettle();
    expect(result(), TrashFallback.rejectedFolder);
  });

  testWidgets('permanent delete needs a second confirmation', (tester) async {
    final result = await open(tester);
    await tester.tap(find.text('Delete permanently…'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 3 photos permanently?'), findsOneWidget);
    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();
    expect(result(), TrashFallback.deletePermanently);
  });

  testWidgets('backing out of the second confirmation deletes nothing', (
    tester,
  ) async {
    final result = await open(tester);
    await tester.tap(find.text('Delete permanently…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result(), isNull);
  });
}
