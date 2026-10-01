// Manual end-to-end verification of GitHub #3 (RAW+JPEG pairs keep separate
// marks) and #4 ("apply marks to whole bracket" in the loupe) on Linux.
// Launches the REAL app window, drives it with real key events, and checks
// the sidecars it writes to disk. Not part of CI.
//
// Needs a RAW to pair with: set CULL_E2E_RAW to any RAW file (it's copied, so
// it may be one LibRaw can't decode — the grid shows a placeholder).
import 'dart:io';

import 'package:cullimingo/app/app.dart';
import 'package:cullimingo/core/cache/vips.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/widgets/photo_cell.dart';
import 'package:cullimingo/features/metadata/data/xmp_sidecar.dart';
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
  await Process.run('import', [
    '-window',
    'root',
    p.join(shotsDir!, '$name.png'),
  ]);
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

  testWidgets('RAW+JPEG keep separate sidecars; loupe marks the bracket', (
    tester,
  ) async {
    if (shotsDir != null) Directory(shotsDir!).createSync(recursive: true);
    Vips.warmUpProcess(); // as main() does, before pool workers spawn

    final shoot = await Directory(
      p.join(Platform.environment['HOME']!, '.cache'),
    ).createTemp('cullimingo_e2e_pair');
    String jpeg(String name, int shade) {
      final image = img.Image(width: 640, height: 420);
      img.fill(image, color: img.ColorRgb8(shade, 90, 200 - shade));
      final path = p.join(shoot.path, name);
      File(path).writeAsBytesSync(img.encodeJpg(image));
      return path;
    }

    final rawSource = Platform.environment['CULL_E2E_RAW']!;
    final rawPath = p.join(shoot.path, 'A7C0001${p.extension(rawSource)}');
    File(rawSource).copySync(rawPath);
    final jpgPath = jpeg('A7C0001.JPG', 60);
    final bPath = jpeg('A7C0002.JPG', 120);
    final cPath = jpeg('A7C0003.JPG', 180);

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
    await pumpUntil(tester, () => find.byType(PhotoCell).evaluate().isNotEmpty);
    await tester.pump(const Duration(seconds: 2));

    final rows = await db.photosForImport(importId);
    int idOf(String path) => rows.firstWhere((r) => r.path == path).id;
    Future<int> ratingOf(String path) async => (await db.photosForImport(
      importId,
    )).firstWhere((r) => r.path == path).rating;
    final controller = container.read(cullControllerProvider.notifier);

    // Grid focus, then rate the RAW 2 and its JPEG 5 with real keys.
    await tester.tap(find.byType(PhotoCell).first);
    await tester.pump();
    controller.setSelection({idOf(rawPath)});
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    controller.setSelection({idOf(jpgPath)});
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await pumpUntil(
      tester,
      () => File(p.join(shoot.path, 'A7C0001.JPG.xmp')).existsSync(),
    );
    await tester.pump(const Duration(seconds: 1));
    await shot(tester, '1-pair-rated');

    final rawXmp = await readSidecar(rawPath);
    final jpgXmp = await readSidecar(jpgPath);
    final names = shoot.listSync().map((e) => p.basename(e.path)).toList()
      ..sort();
    // ignore: avoid_print — evidence for the report.
    print('SIDECARS: $names raw=${rawXmp?.rating} jpg=${jpgXmp?.rating}');
    expect(File(p.join(shoot.path, 'A7C0001.xmp')).existsSync(), isTrue);
    expect(rawXmp!.rating, 2);
    expect(jpgXmp!.rating, 5);

    // Re-sync from disk the way reopening the folder does: each keeps its own.
    await container
        .read(metadataRepositoryProvider)
        .applySidecarsForImport(importId);
    await tester.pump(const Duration(milliseconds: 500));
    expect(await ratingOf(rawPath), 2);
    expect(await ratingOf(jpgPath), 5);

    // #4: stack B+C, turn on "apply marks to whole bracket", rate B in the
    // loupe → C follows.
    controller.setSelection({idOf(bPath), idOf(cPath)});
    expect(await controller.stackSelection(), 2);
    container.read(propagateMarksToStackProvider.notifier).set(true);
    controller.setSelection({idOf(bPath)});
    await tester.pump(const Duration(milliseconds: 500));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // open loupe
    await tester.pump(const Duration(milliseconds: 500));
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump(const Duration(milliseconds: 300));
    await shot(tester, '2-loupe-rated');
    await tester.pump(const Duration(seconds: 1)); // DB + sidecar writes
    // ignore: avoid_print — evidence for the report.
    print('BRACKET: b=${await ratingOf(bPath)} c=${await ratingOf(cPath)}');
    expect(await ratingOf(bPath), 3);
    expect(await ratingOf(cPath), 3);
    expect((await readSidecar(cPath))!.rating, 3);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
    shoot.deleteSync(recursive: true);
  });
}
