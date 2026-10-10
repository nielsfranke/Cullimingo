// Manual end-to-end verification of GitHub #14 and #15 on Linux. Launches
// the REAL app window and drives it with real key events. The shoot must live
// where `gio trash` refuses (a tmpfs, like an SMB share via gvfs: no trash), so
// the "Trash not available" fallback kicks in. Not part of CI.
//
// Docker run (Xvfb): see the verify skill; SHOOT_ROOT points at the tmpfs,
// SHOTS_DIR at a mounted folder for the screenshots.
import 'dart:io';

import 'package:cullimingo/app/app.dart';
import 'package:cullimingo/core/cache/vips.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/cull/presentation/cull_job_runner.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/widgets/photo_cell.dart';
import 'package:cullimingo/features/handoff/data/transfer_service.dart';
import 'package:cullimingo/features/handoff/presentation/transfer_dialog.dart';
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

Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('timed out waiting for $finder');
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

  testWidgets('#14 trash fallback + #15 Ctrl labels on Linux', (tester) async {
    Directory(shotsDir).createSync(recursive: true);
    Vips.warmUpProcess();

    final shoot = Directory(
      p.join(Platform.environment['SHOOT_ROOT'] ?? '/shoots', 'shoot'),
    )..createSync(recursive: true);
    String photo(int i) => p.join(shoot.path, 'DSC_000$i.JPG');
    String rejected(String name) => p.join(shoot.path, '_Rejected', name);
    for (var i = 1; i <= 5; i++) {
      final image = img.Image(width: 640, height: 420);
      img.fill(image, color: img.ColorRgb8(50 * i, 90, 230 - 40 * i));
      File(photo(i)).writeAsBytesSync(img.encodeJpg(image));
    }

    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const CullimingoApp(),
      ),
    );
    await settle(tester, 1000);
    // Fresh settings in the container: dismiss the first-run welcome.
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
          label: p.basename(shoot.path),
        );
    await repo.populateImport(importId, shoot.path);
    await pumpUntil(tester, find.byType(PhotoCell));
    expect(find.byType(PhotoCell), findsNWidgets(5));
    await settle(tester, 2000);
    await shot(tester, '1-grid');

    // #15: the ⋮ menu shows Linux modifier labels, not ⌘.
    await tester.tap(find.byTooltip('More'));
    await settle(tester, 500);
    await shot(tester, '2-menu-ctrl-labels');
    expect(find.text('Refresh folder (Ctrl+R)'), findsOneWidget);
    expect(
      find.text('Delete rejected photos… (Ctrl+Backspace)'),
      findsOneWidget,
    );
    expect(find.textContaining('⌘'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, 500);

    // #14: reject 1 + 2 (X writes their sidecars), delete → trash refuses.
    await tester.tap(find.byType(PhotoCell).at(0));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await settle(tester, 300);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await settle(tester); // sidecar writes are debounced
    expect(File(p.setExtension(photo(1), '.xmp')).existsSync(), isTrue);

    await ctrlKey(tester, LogicalKeyboardKey.backspace);
    await pumpUntil(tester, find.text('Move to Trash'));
    await tester.tap(find.text('Move to Trash'));
    await pumpUntil(tester, find.text('Trash not available'));
    await shot(tester, '3-trash-not-available');
    await tester.tap(find.text('Move to _Rejected'));
    await pumpUntil(tester, find.textContaining('Moved 2 photos to _Rejected'));
    await shot(tester, '4-moved-to-rejected');
    expect(find.byType(PhotoCell), findsNWidgets(3));
    expect(File(photo(1)).existsSync(), isFalse);
    expect(File(rejected('DSC_0001.JPG')).existsSync(), isTrue);
    expect(File(rejected('DSC_0001.xmp')).existsSync(), isTrue);
    expect(File(rejected('DSC_0002.JPG')).existsSync(), isTrue);

    // A refresh must not bring the _Rejected photos back.
    await tester.tap(find.byType(PhotoCell).at(0));
    await ctrlKey(tester, LogicalKeyboardKey.keyR);
    await settle(tester, 3000);
    expect(find.byType(PhotoCell), findsNWidgets(3));

    // Permanent delete: backing out of the second confirmation keeps it.
    await tester.tap(find.byType(PhotoCell).at(0)); // DSC_0003
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await settle(tester, 300);
    await ctrlKey(tester, LogicalKeyboardKey.backspace);
    await pumpUntil(tester, find.text('Move to Trash'));
    await tester.tap(find.text('Move to Trash'));
    await pumpUntil(tester, find.text('Delete permanently…'));
    await tester.tap(find.text('Delete permanently…'));
    await pumpUntil(tester, find.text('Delete 1 photo permanently?'));
    await shot(tester, '5-second-confirmation');
    await tester.tap(find.text('Cancel'));
    await settle(tester, 1000);
    expect(File(photo(3)).existsSync(), isTrue, reason: 'cancel must keep');
    expect(find.byType(PhotoCell), findsNWidgets(3));

    // …and confirming deletes it for good.
    await ctrlKey(tester, LogicalKeyboardKey.backspace);
    await pumpUntil(tester, find.text('Move to Trash'));
    await tester.tap(find.text('Move to Trash'));
    await pumpUntil(tester, find.text('Delete permanently…'));
    await tester.tap(find.text('Delete permanently…'));
    await pumpUntil(tester, find.text('Delete permanently'));
    await tester.tap(find.text('Delete permanently'));
    await pumpUntil(tester, find.textContaining('Deleted 1 photo permanently'));
    await shot(tester, '6-deleted-permanently');
    expect(File(photo(3)).existsSync(), isFalse);
    expect(find.byType(PhotoCell), findsNWidgets(2));

    // #14 ghost rows: a moved photo leaves the grid.
    final elsewhere = Directory(p.join(shoot.parent.path, 'elsewhere'))
      ..createSync();
    await container
        .read(cullJobRunnerProvider)
        .runTransferJob(
          TransferRequest(
            sources: [photo(4)],
            destinationRoot: elsewhere.path,
            mode: TransferMode.move,
            includeSidecars: true,
            openWhenDone: false,
          ),
        );
    await pumpUntil(tester, find.textContaining('Moved 1 photo'));
    await settle(tester, 1000);
    await shot(tester, '7-after-move');
    expect(File(photo(4)).existsSync(), isFalse);
    expect(File(p.join(elsewhere.path, 'DSC_0004.JPG')).existsSync(), isTrue);
    expect(find.byType(PhotoCell), findsNWidgets(1));

    final left = [
      for (final e in shoot.listSync(recursive: true))
        p.relative(e.path, from: shoot.path),
    ]..sort();
    // ignore: avoid_print — the evidence for the report.
    print('SHOOT-AFTER: $left');
  });
}
