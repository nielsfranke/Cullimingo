import 'package:cullimingo/core/files/posix_fs.dart';
import 'package:cullimingo/features/ingest/presentation/free_space_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, String? path, Map<String, int> free) =>
      tester.pumpWidget(
        MaterialApp(
          home: FreeSpaceLine(
            path: path,
            probe: (path) async => free[path] == null
                ? null
                : VolumeInfo(mountPoint: r'E:\', freeBytes: free[path]!),
          ),
        ),
      );

  testWidgets('shows the free room on the destination volume', (tester) async {
    await pump(tester, r'E:\Shoots', {r'E:\Shoots': 127 * 1024 * 1024 * 1024});
    await tester.pumpAndSettle();
    expect(find.text(r'127 GB free on E:\'), findsOneWidget);
  });

  testWidgets('re-probes when the path changes; silent when unknown', (
    tester,
  ) async {
    final free = {r'E:\A': 5 * 1024 * 1024 * 1024};
    await pump(tester, r'E:\A', free);
    await tester.pumpAndSettle();
    expect(find.textContaining('5.0 GB free'), findsOneWidget);

    await pump(tester, r'E:\B', free);
    await tester.pumpAndSettle();
    expect(find.textContaining('free on'), findsNothing);

    await pump(tester, null, free);
    await tester.pumpAndSettle();
    expect(find.textContaining('free on'), findsNothing);
  });
}
