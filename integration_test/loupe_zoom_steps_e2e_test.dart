// Manual end-to-end check of GitHub #24: A / S / D / W step the loupe zoom
// (Fit / 50% / 100% / 200% of true 1:1) in the REAL app window.
import 'dart:io';

import 'package:cullimingo/app/app.dart';
import 'package:cullimingo/core/cache/vips.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/features/cull/domain/loupe_zoom.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/widgets/loupe_view.dart';
import 'package:cullimingo/features/cull/presentation/widgets/photo_cell.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show InteractiveViewer;
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

  testWidgets('#24 stepped zoom keys in the loupe', (tester) async {
    Directory(shotsDir).createSync(recursive: true);
    Vips.warmUpProcess();
    final shoot = Directory(
      p.join(Platform.environment['SHOOT_ROOT'] ?? '/shoots', 'shoot'),
    )..createSync(recursive: true);
    // A 5472-px frame (the reporter's size) with a fine pattern + a label.
    for (var i = 1; i <= 2; i++) {
      final image = img.Image(width: 5472, height: 3648);
      img.fill(image, color: img.ColorRgb8(30, 30, 40));
      for (var y = 0; y < 3648; y += 8) {
        img.drawLine(
          image,
          x1: 0,
          y1: y,
          x2: 5471,
          y2: y,
          color: img.ColorRgb8(200, 120 + 40 * i, 60),
        );
      }
      img.drawString(image, 'FRAME $i', font: img.arial48, x: 2600, y: 1800);
      File(
        p.join(shoot.path, 'DSC_000$i.JPG'),
      ).writeAsBytesSync(img.encodeJpg(image, quality: 90));
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
    await settle(tester, 3000);

    await tester.tap(find.byType(PhotoCell).first);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester, 4000);
    expect(find.byType(LoupeView), findsOneWidget);
    double scale() => tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!
        .value
        .getMaxScaleOnAxis();
    final area = tester.getRect(find.byType(InteractiveViewer));
    final fitW = area.width / area.height > 1.5
        ? area.height * 1.5
        : area.width;
    final hundred = 5472 / fitW;
    LoupeZoomMode mode() => container.read(loupeZoomLevelProvider).mode;

    for (final (key, factor, name) in [
      (LogicalKeyboardKey.keyS, 0.5, '50'),
      (LogicalKeyboardKey.keyW, 2.0, '200'),
      (LogicalKeyboardKey.keyD, 1.0, '100'),
    ]) {
      await tester.sendKeyEvent(key);
      await settle(tester, 6000);
      // ignore: avoid_print — the evidence for the report.
      print(
        'STEP $name: scale ${scale()} want ${hundred * factor} '
        'mode ${mode()}',
      );
      expect(scale(), closeTo(hundred * factor, 0.02));
      await shot(tester, 'step-$name');
    }

    // The step carries over to the next frame of the burst.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await settle(tester, 6000);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await settle(tester, 6000);
    // ignore: avoid_print — the evidence for the report.
    print('NEXT: scale ${scale()} mode ${mode()}');
    expect(scale(), closeTo(hundred * 2, 0.02));
    expect(mode(), LoupeZoomMode.twoHundred);
    await shot(tester, 'next-frame-200');

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await settle(tester, 3000);
    expect(scale(), 1);
    await shot(tester, 'fit');
  });
}
