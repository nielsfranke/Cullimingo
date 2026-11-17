// Manual end-to-end check of GitHub #25: H / J / E toggle the loupe's
// histogram, clipping warning and focus peaking in the REAL app window.
import 'dart:io';

import 'package:cullimingo/app/app.dart';
import 'package:cullimingo/core/cache/vips.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/widgets/loupe_view.dart';
import 'package:cullimingo/features/cull/presentation/widgets/photo_cell.dart';
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('#25 overlay keys in the loupe', (tester) async {
    Directory(shotsDir).createSync(recursive: true);
    Vips.warmUpProcess();
    final shoot = Directory(
      p.join(Platform.environment['SHOOT_ROOT'] ?? '/shoots', 'shoot'),
    )..createSync(recursive: true);
    for (var i = 1; i <= 2; i++) {
      // Checkerboard with pure white + pure black squares: sharp edges for
      // peaking, blown/crushed areas for clipping.
      final image = img.Image(width: 1200, height: 800);
      for (var y = 0; y < 800; y++) {
        for (var x = 0; x < 1200; x++) {
          final on = ((x ~/ 100) + (y ~/ 100)).isEven;
          final v = x < 600 ? (on ? 255 : 0) : (on ? 180 : 90);
          image.setPixelRgb(x, y, v, v, (v + 40 * i).clamp(0, 255));
        }
      }
      File(
        p.join(shoot.path, 'DSC_000$i.JPG'),
      ).writeAsBytesSync(img.encodeJpg(image, quality: 95));
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
        .openImport(importId: importId, sourcePath: shoot.path, label: 'shoot');
    await repo.populateImport(importId, shoot.path);
    for (var i = 0; i < 200 && find.byType(PhotoCell).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await settle(tester, 2000);

    await tester.tap(find.byType(PhotoCell).first);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); // open loupe
    await settle(tester, 3000);
    expect(find.byType(LoupeView), findsOneWidget);
    await shot(tester, '1-loupe-plain');

    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await settle(tester, 4000);
    expect(container.read(loupeFocusPeakingVisibleProvider), isTrue);
    await shot(tester, '2-peaking-E');

    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await settle(tester, 4000);
    expect(container.read(loupeFocusPeakingVisibleProvider), isFalse);
    expect(container.read(loupeHistogramVisibleProvider), isTrue);
    expect(container.read(loupeClippingVisibleProvider), isTrue);
    expect(find.byType(LoupeView), findsOneWidget);
    await shot(tester, '3-histogram-H-clipping-J');

    // Sticky across photos.
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await settle(tester, 4000);
    expect(container.read(loupeClippingVisibleProvider), isTrue);
    await shot(tester, '4-next-photo-still-on');
  });
}
