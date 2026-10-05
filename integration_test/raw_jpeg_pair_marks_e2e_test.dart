// Manual end-to-end verification of GitHub #12 (RAW+JPEG pairs culled as one
// photo). Launches the REAL app window, drives it with real key events, and
// checks the DB rows, sidecars and file names it leaves on disk. Not part of
// CI.
//
// Run: flutter test integration_test/raw_jpeg_pair_marks_e2e_test.dart -d macos
// (or -d linux). It flips persisted settings — back up the app's
// settings.json first and restore it afterwards.
//
// The "RAF" files are JPEG bytes under a RAW extension: the grid shows a
// placeholder for them, which is fine — only pairing by name matters here.
import 'dart:io';

import 'package:cullimingo/app/app.dart';
import 'package:cullimingo/core/cache/vips.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/widgets/photo_cell.dart';
import 'package:cullimingo/features/filter/presentation/filter_providers.dart';
import 'package:cullimingo/features/metadata/data/xmp_sidecar.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

final String? shotsDir = Platform.environment['CULL_E2E_SHOTS'];

Future<void> shot(WidgetTester tester, String name) async {
  if (shotsDir == null) return;
  await tester.pump(const Duration(milliseconds: 300));
  final path = p.join(shotsDir!, '$name.png');
  if (Platform.isMacOS) {
    await Process.run('screencapture', ['-x', path]);
  } else {
    await Process.run('import', ['-window', 'root', path]);
  }
}

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (done()) return;
  }
  fail('timed out');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RAF+JPG pairs pick, advance, filter and rename as one', (
    tester,
  ) async {
    if (shotsDir != null) Directory(shotsDir!).createSync(recursive: true);
    Vips.warmUpProcess(); // as main() does, before pool workers spawn

    final shoot = await Directory(
      p.join(Platform.environment['HOME']!, '.cache'),
    ).createTemp('cullimingo_e2e_pair12');
    String file(String name, int minute) {
      final image = img.Image(width: 640, height: 420);
      img.fill(image, color: img.ColorRgb8(40 * minute + 60, 90, 120));
      final path = p.join(shoot.path, name);
      File(path)
        ..writeAsBytesSync(img.encodeJpg(image))
        ..setLastModifiedSync(DateTime(2026, 10, 5, 12, minute));
      return path;
    }

    final aRaw = file('DSCF8912.RAF', 0);
    final aJpg = file('DSCF8912.JPG', 0);
    final bRaw = file('DSCF8913.RAF', 1);
    final bJpg = file('DSCF8913.JPG', 1);
    file('DSCF8914.JPG', 2);

    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const CullimingoApp(),
      ),
    );
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(CullimingoApp)),
    );
    container.read(propagateMarksToPairProvider.notifier).set(true);
    container.read(autoAdvanceAfterMarkProvider.notifier).set(true);

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
    await pumpUntil(
      tester,
      () => find.byType(PhotoCell).evaluate().length == 5,
    );
    await tester.pump(const Duration(seconds: 2));

    final rows = await db.photosForImport(importId);
    int idOf(String path) => rows.firstWhere((r) => r.path == path).id;
    Future<PickFlag> flagOf(String path) async => (await db.photosForImport(
      importId,
    )).firstWhere((r) => r.path == path).flag;
    final grid = container.read(filteredPhotosProvider).map((r) => r.path);
    // ignore: avoid_print — evidence for the report.
    print('GRID: ${grid.map(p.basename).toList()}');
    expect(grid.first, aJpg, reason: 'each JPG sorts right before its RAF');

    // P on the first shot's JPG: both files picked, focus skips the RAF.
    await tester.tap(find.byType(PhotoCell).first);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump(const Duration(milliseconds: 500));
    expect(await flagOf(aJpg), PickFlag.pick);
    expect(await flagOf(aRaw), PickFlag.pick);
    expect(container.read(cullControllerProvider).focusedId, idOf(bJpg));

    // X on the second shot: both rejected, focus on to the lone JPG.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pump(const Duration(milliseconds: 500));
    expect(await flagOf(bJpg), PickFlag.reject);
    expect(await flagOf(bRaw), PickFlag.reject);
    await pumpUntil(
      tester,
      () => File(p.join(shoot.path, 'DSCF8913.JPG.xmp')).existsSync(),
    );
    await tester.pump(const Duration(seconds: 1));
    final aRawXmp = await readSidecar(aRaw);
    final aJpgXmp = await readSidecar(aJpg);
    // ignore: avoid_print — evidence for the report.
    print('SIDECAR FLAGS: raf=${aRawXmp?.flag} jpg=${aJpgXmp?.flag}');
    expect(aRawXmp!.flag, PickFlag.pick);
    expect(aJpgXmp!.flag, PickFlag.pick);
    await shot(tester, '1-pairs-marked');

    // The new chips: only DSCF8914.JPG is unflagged; nothing is rated.
    await tester.tap(find.text('Unflagged (1)'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PhotoCell), findsNWidgets(1));
    await shot(tester, '2-unflagged-chip');
    await tester.tap(find.text('Unflagged (1)'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Unrated (5)'), findsOneWidget);

    // Rename with JPEGs hidden: R on the second RAF takes its JPG along.
    container
        .read(photoFilterControllerProvider.notifier)
        .toggleHideJpegPairs();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PhotoCell), findsNWidgets(3));
    container.read(cullControllerProvider.notifier).setSelection({
      idOf(bRaw),
    });
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await pumpUntil(tester, () => find.text('Rename 2').evaluate().isNotEmpty);
    await shot(tester, '3-rename-dialog');
    await tester.tap(find.text('Rename 2'));
    await pumpUntil(
      tester,
      () => find.textContaining('Renamed 2 photo').evaluate().isNotEmpty,
    );
    final names = shoot.listSync().map((e) => p.basename(e.path)).toList()
      ..sort();
    // ignore: avoid_print — evidence for the report.
    print('AFTER RENAME: $names');
    expect(names.where((n) => n.startsWith('DSCF8913')), isEmpty);
    final renamed = names
        .where((n) => !n.startsWith('DSCF'))
        .map(p.basenameWithoutExtension)
        .map((n) => n.replaceAll('.JPG', '')) // the JPG's own .JPG.xmp
        .toSet();
    expect(renamed, hasLength(1), reason: 'RAF, JPG and sidecars share a stem');
    await shot(tester, '4-renamed');

    container.read(propagateMarksToPairProvider.notifier).set(false);
    container.read(autoAdvanceAfterMarkProvider.notifier).set(false);
    shoot.deleteSync(recursive: true);
  });
}
