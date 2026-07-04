// Manual end-to-end verification of delete-rejects-to-trash on Linux.
// Launches the REAL app window on the desktop, drives it with real key
// events, and lets it hit the real `gio` trash. Not part of CI.
import 'dart:io';

import 'package:cullimingo/app/app.dart';
import 'package:cullimingo/core/cache/vips.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/widgets/photo_cell.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

const shotsDir =
    '/tmp/claude-1000/-home-niels-Cullimingo/'
    '5f7a3d76-5b96-4c07-8261-8c05979cc01e/scratchpad/shots';

Future<void> shot(String name) async {
  await Process.run('spectacle', ['-abno', p.join(shotsDir, '$name.png')]);
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

Future<void> ctrlKey(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reject → Ctrl+Backspace moves files to the OS trash', (
    tester,
  ) async {
    Directory(shotsDir).createSync(recursive: true);
    Vips.warmUpProcess(); // as main() does, before pool workers spawn

    // A scratch shoot: 4 real JPEGs. On the HOME filesystem, not /tmp —
    // gio refuses to trash from system-internal mounts like tmpfs
    // ("Trashing on system internal mounts is not supported").
    final shoot = await Directory(
      p.join(Platform.environment['HOME']!, '.cache'),
    ).createTemp('cullimingo_e2e');
    final paths = <String>[];
    for (var i = 1; i <= 4; i++) {
      final image = img.Image(width: 640, height: 420);
      img.fill(image, color: img.ColorRgb8(60 * i, 90, 200 - 40 * i));
      final path = p.join(shoot.path, 'DSC_000$i.JPG');
      File(path).writeAsBytesSync(img.encodeJpg(image));
      paths.add(path);
    }

    // Real app + real providers; only the DB points at a scratch store.
    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const CullimingoApp(),
      ),
    );
    await tester.pump();

    // Open the scratch folder — same calls the folder picker flow makes.
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
    expect(find.byType(PhotoCell), findsNWidgets(4));
    await tester.pump(const Duration(seconds: 2)); // let thumbnails land
    await shot('1-grid-open');

    // Click the first photo, reject it and its neighbour with X.
    await tester.tap(find.byType(PhotoCell).first);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pump(const Duration(milliseconds: 300));
    await shot('2-two-rejected');

    // Probe: undo/redo the second reject at the same surface.
    await ctrlKey(tester, LogicalKeyboardKey.keyZ);
    await pumpUntil(tester, find.textContaining('Undid flag'));
    await ctrlKey(tester, LogicalKeyboardKey.keyZ, shift: true);
    await pumpUntil(tester, find.textContaining('Redid flag'));

    // Probe: Ctrl+Backspace, then Cancel — nothing may be deleted.
    await ctrlKey(tester, LogicalKeyboardKey.backspace);
    await pumpUntil(tester, find.text('Move to Trash'));
    await shot('3-confirm-dialog');
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(File(paths[0]).existsSync(), isTrue, reason: 'cancel must keep');
    expect(find.byType(PhotoCell), findsNWidgets(4));

    // The real thing: confirm, files land in the OS trash.
    await ctrlKey(tester, LogicalKeyboardKey.backspace);
    await pumpUntil(tester, find.text('Move to Trash'));
    await tester.tap(find.text('Move to Trash'));
    await pumpUntil(tester, find.textContaining('Moved 2 photos to the Trash'));
    await tester.pump(const Duration(milliseconds: 300));
    await shot('4-after-delete');

    expect(find.byType(PhotoCell), findsNWidgets(2));
    expect(File(paths[0]).existsSync(), isFalse);
    expect(File(paths[1]).existsSync(), isFalse);
    expect(File(paths[2]).existsSync(), isTrue);

    // The files must be IN the trash (recoverable), not hard-deleted. No
    // gvfs daemon on this box, so read the freedesktop trash dir directly
    // (match by the Path= recorded in each .trashinfo, not by basename, so
    // pre-existing user trash items can't collide).
    final home = Platform.environment['HOME']!;
    final infoDir = Directory(p.join(home, '.local/share/Trash/info'));
    final ours = <({String trashedName, String originalPath})>[];
    for (final info in infoDir.listSync().whereType<File>()) {
      final content = info.readAsStringSync();
      final match = RegExp(
        r'^Path=(.*)$',
        multiLine: true,
      ).firstMatch(content);
      final original = Uri.decodeFull(match?.group(1) ?? '');
      if (p.isWithin(shoot.path, original)) {
        ours.add((
          trashedName: p.basenameWithoutExtension(info.path),
          originalPath: original,
        ));
      }
    }
    // ignore: avoid_print — this is the evidence for the report.
    print('TRASHED-ITEMS: $ours');
    expect(
      ours.where((e) => e.originalPath.endsWith('DSC_0001.JPG')),
      isNotEmpty,
      reason: 'DSC_0001.JPG must be in the trash',
    );
    expect(
      ours.where((e) => e.originalPath.endsWith('DSC_0002.JPG')),
      isNotEmpty,
      reason: 'DSC_0002.JPG must be in the trash',
    );
    expect(
      ours.where((e) => e.originalPath.endsWith('DSC_0001.xmp')),
      isNotEmpty,
      reason: 'the sidecar must travel with its photo',
    );

    // Probe: run it again with no rejects left.
    await ctrlKey(tester, LogicalKeyboardKey.backspace);
    await pumpUntil(tester, find.text('No rejected photos in this folder'));
    await shot('5-no-rejects-notice');

    // Restore by hand (proves recoverability), then clean up fully.
    for (final item in ours) {
      File(
        p.join(home, '.local/share/Trash/files', item.trashedName),
      ).renameSync(item.originalPath);
      File(
        p.join(
          home,
          '.local/share/Trash/info',
          '${item.trashedName}.trashinfo',
        ),
      ).deleteSync();
    }
    expect(File(paths[0]).existsSync(), isTrue, reason: 'restore works');
    shoot.deleteSync(recursive: true);
  });
}
