// Manual end-to-end verification of GitHub #31 on Linux: a folder and its
// subfolders open as tabs side by side, through opening, Ctrl+R, the
// sub-folders toggle and a restart. Launches the REAL app window; folders open
// through the "+" recent menu, i.e. the page's own _importFolder, and the
// restart goes through the page's own _restoreLastFolders. Not part of CI.
//
// Docker run (Xvfb): see the verify skill; SHOOT_ROOT points at a scratch dir,
// SHOTS_DIR at a mounted folder for the screenshots. Writes the app's real
// settings.json (fresh in the container).
import 'dart:convert';
import 'dart:io';

import 'package:cullimingo/app/app.dart';
import 'package:cullimingo/core/cache/vips.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/widgets/photo_cell.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

/// Waits until the grid shows exactly [n] cells and stays there for a second
/// (an empty tab that flashes the previous tab's photos must not pass).
Future<void> expectCells(
  WidgetTester tester,
  int n, {
  required String reason,
}) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(PhotoCell).evaluate().length == n) {
      await settle(tester, 1000);
      if (find.byType(PhotoCell).evaluate().length == n) return;
    }
  }
  fail(
    '$reason: expected $n cells, saw '
    '${find.byType(PhotoCell).evaluate().length}',
  );
}

Future<void> ctrlKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('#31 parent + subfolder tabs', (tester) async {
    Directory(shotsDir).createSync(recursive: true);
    Vips.warmUpProcess();

    // 2026/ with 2 photos, day1/ with 3, day2/ with 2 → parent shows 7.
    final root = Directory(
      p.join(Platform.environment['SHOOT_ROOT'] ?? '/shoots', '2026'),
    )..createSync(recursive: true);
    final day1 = Directory(p.join(root.path, '2026-09-23_day1'))..createSync();
    final day2 = Directory(p.join(root.path, '2026-11-16_day2'))..createSync();
    var n = 0;
    void photos(Directory dir, int count) {
      for (var i = 0; i < count; i++) {
        n++;
        final image = img.Image(width: 480, height: 320);
        img.fill(image, color: img.ColorRgb8(30 * n % 255, 120, 200));
        File(
          p.join(dir.path, 'IMG_${n.toString().padLeft(4, '0')}.JPG'),
        ).writeAsBytesSync(img.encodeJpg(image));
      }
    }

    photos(root, 2);
    photos(day1, 3);
    photos(day2, 2);

    // Like Marc: reopen-last-folders on, cheat sheet already seen.
    final support = await getApplicationSupportDirectory();
    support.createSync(recursive: true);
    File(p.join(support.path, 'settings.json')).writeAsStringSync(
      jsonEncode({
        'reopenLastFolders': true,
        'hasSeenShortcutsHint': true,
        'checkForUpdates': false,
      }),
    );

    final dbFile = File(p.join(root.parent.path, 'e2e.sqlite'));
    if (dbFile.existsSync()) dbFile.deleteSync();
    // One DB across the "restart", like the real app's file on disk.
    final db = AppDatabase(NativeDatabase(dbFile));

    Future<void> launch() async {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            recentFoldersSeedProvider.overrideWithValue([
              day2.path,
              day1.path,
              root.path,
            ]),
          ],
          child: const CullimingoApp(),
        ),
      );
      await settle(tester, 1000);
      if (find.text('Got it').evaluate().isNotEmpty) {
        await tester.tap(find.text('Got it'));
        await settle(tester, 500);
      }
    }

    Future<void> openRecent(Directory dir) async {
      await tester.tap(find.byTooltip('Open folder / recent'));
      await settle(tester, 500);
      await tester.tap(find.text(p.basename(dir.path)).last);
      await settle(tester, 300);
    }

    Future<void> selectTab(Directory dir) async {
      await tester.tap(find.text(p.basename(dir.path)).first);
      await settle(tester, 300);
    }

    await launch();

    // The tab bar (and its "+" menu) only exists once a tab is open, so the
    // parent opens the way the other e2e drives do; both subfolders then open
    // through the page's own path (the "+" recent menu → _importFolder).
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CullimingoApp)),
    );
    final repo = container.read(libraryRepositoryProvider);
    final (rootId, _) = await repo.findOrCreateImport(root.path);
    container
        .read(workspaceProvider.notifier)
        .openImport(importId: rootId, sourcePath: root.path, label: '2026');
    await repo.populateImport(rootId, root.path);
    await expectCells(tester, 7, reason: 'parent opened');
    await openRecent(day1);
    await expectCells(tester, 3, reason: 'day1 opened next to its parent');
    await shot(tester, '1-day1-opened');
    await openRecent(day2);
    await expectCells(tester, 2, reason: 'day2 opened next to its parent');

    await selectTab(root);
    await expectCells(tester, 7, reason: 'parent after opening subfolders');
    await shot(tester, '2-parent-still-full');

    // Ctrl+R in the parent must not empty the subfolder tabs.
    await tester.tap(find.byType(PhotoCell).first);
    await ctrlKey(tester, LogicalKeyboardKey.keyR);
    await settle(tester, 2500);
    await expectCells(tester, 7, reason: 'parent after Ctrl+R');
    await selectTab(day1);
    await expectCells(tester, 3, reason: 'day1 after Ctrl+R in parent');

    // Rate in day1; the parent shows the same rating (one row per file).
    await tester.tap(find.byType(PhotoCell).first);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await settle(tester, 800);
    final rated = (await db.photosForImport(
      rootId,
    )).where((ph) => ph.rating == 5);
    expect(rated, hasLength(1), reason: 'rating shared with the parent tab');

    // Sub-folders off hides them in the parent but deletes nothing.
    await selectTab(root);
    await expectCells(tester, 7, reason: 'parent before toggle');
    await tester.tap(find.byTooltip('Open folder: including sub-folders'));
    await expectCells(tester, 2, reason: 'parent, sub-folders off');
    await shot(tester, '3-subfolders-off');
    await selectTab(day1);
    await expectCells(tester, 3, reason: 'day1 while sub-folders off');
    await tester.tap(find.byTooltip('Open folder: top level only'));
    await selectTab(root);
    await expectCells(tester, 7, reason: 'parent, sub-folders back on');

    // Leave day2 active, then "restart": a fresh widget tree + providers on
    // the same DB and settings.json; the page restores the tabs itself.
    await selectTab(day2);
    await expectCells(tester, 2, reason: 'day2 before restart');
    await settle(tester); // settings write is async
    await tester.pumpWidget(const SizedBox());
    await settle(tester, 500);
    await launch();
    await expectCells(tester, 2, reason: 'day2 restored active');
    await shot(tester, '4-restored');
    expect(find.text(p.basename(root.path)), findsWidgets);
    expect(find.text(p.basename(day1.path)), findsWidgets);
    await settle(tester, 3000); // background rescans of all restored tabs
    await expectCells(tester, 2, reason: 'day2 after the restore rescans');
    await selectTab(day1);
    await expectCells(tester, 3, reason: 'day1 after restart');
    await selectTab(root);
    await expectCells(tester, 7, reason: 'parent after restart');
    await shot(tester, '5-parent-after-restart');

    await tester.pumpWidget(const SizedBox());
    await db.close();
  });
}
