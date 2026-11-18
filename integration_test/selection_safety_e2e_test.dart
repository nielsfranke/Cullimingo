// Manual end-to-end check of GitHub #28: Esc clears the grid selection, the
// status bar shows it, and a batch mark skips photos the filter hides.
import 'dart:io';

import 'package:cullimingo/app/app.dart';
import 'package:cullimingo/core/cache/vips.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/widgets/photo_cell.dart';
import 'package:cullimingo/features/filter/presentation/filter_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

final String shotsDir = Platform.environment['SHOTS_DIR'] ?? '/tmp/shots';

Future<void> shot(WidgetTester tester, String name) async {
  await tester.pump();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await tester.pump();
  await Process.run('import', [
    '-window',
    'root',
    p.join(shotsDir, '$name.png'),
  ]);
}

Future<void> settle(WidgetTester tester, [int ms = 1500]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> ctrlKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('#28 selection safety in the grid', (tester) async {
    Directory(shotsDir).createSync(recursive: true);
    Vips.warmUpProcess();
    final shoot = Directory(
      p.join(Platform.environment['SHOOT_ROOT'] ?? '/shoots', 'shoot'),
    )..createSync(recursive: true);
    for (var i = 1; i <= 6; i++) {
      final image = img.Image(width: 600, height: 400);
      img.fill(image, color: img.ColorRgb8(40 * i, 100, 200 - 25 * i));
      File(
        p.join(shoot.path, 'DSC_000$i.JPG'),
      ).writeAsBytesSync(img.encodeJpg(image));
    }
    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const CullimingoApp(),
      ),
    );
    await settle(tester, 1000);
    if (find.text('Got it').evaluate().isNotEmpty) {
      await tester.tap(find.text('Got it'));
      await settle(tester, 500);
    }
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CullimingoApp)),
    );
    final repo = container.read(libraryRepositoryProvider);
    final (importId, _) = await repo.findOrCreateImport(shoot.path);
    container
        .read(workspaceProvider.notifier)
        .openImport(
          importId: importId,
          sourcePath: shoot.path,
          label: 'shoot',
        );
    await repo.populateImport(importId, shoot.path);
    for (var i = 0; i < 200 && find.byType(PhotoCell).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await settle(tester, 2000);

    await tester.tap(find.byType(PhotoCell).first);
    await tester.pump();
    await ctrlKey(tester, LogicalKeyboardKey.keyA); // select all 6
    await settle(tester, 500);
    expect(find.textContaining('6 selected · Esc clears'), findsOneWidget);
    await shot(tester, '1-all-selected');

    container.read(photoFilterControllerProvider.notifier).setQuery('0001');
    await settle(tester, 1000);
    expect(
      find.textContaining('6 selected (5 hidden by filter)'),
      findsOneWidget,
    );
    expect(find.text('Export 1 selected'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await settle(tester, 2000);
    await shot(tester, '2-filtered-rated');
    final rows = await db.watchPhotosForImport(importId).first;
    final ratings = {for (final r in rows) p.basename(r.path): r.rating};
    // ignore: avoid_print — the evidence for the report.
    print('RATINGS: $ratings');
    expect(ratings.values.where((r) => r == 4).length, 1);
    // Only the visible photo's sidecar was written.
    final xmps = shoot.listSync().where((e) => e.path.endsWith('.xmp'));
    // ignore: avoid_print — the evidence for the report.
    print('XMPS: ${[for (final x in xmps) p.basename(x.path)]}');
    expect(xmps.length, 1);

    container.read(photoFilterControllerProvider.notifier).setQuery('');
    await settle(tester, 1000);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, 500);
    expect(container.read(cullControllerProvider).selectedIds, isEmpty);
    expect(find.textContaining('Esc clears'), findsNothing);
    await shot(tester, '3-esc-cleared');
  });
}
