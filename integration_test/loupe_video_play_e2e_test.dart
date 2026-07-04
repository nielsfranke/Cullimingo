// Manual end-to-end verification of the loupe's "open in system player"
// affordance for videos on Linux. Launches the REAL app window on the
// desktop, drives it with real key/mouse events, and lets the tapped button
// really shell out to xdg-open. Not part of CI.
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
    '199fe1eb-6a07-4478-b87d-d766db433691/scratchpad/shots';

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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the loupe play button opens a video in the system player', (
    tester,
  ) async {
    Directory(shotsDir).createSync(recursive: true);
    Vips.warmUpProcess(); // as main() does, before pool workers spawn

    // A scratch shoot: 2 real JPEGs (neither carries EXIF capture time, so the
    // grid's default sort falls back to filename) plus a fake video. Under
    // HOME, not /tmp, matching the other e2e probe's note on filesystem quirks.
    final shoot = await Directory(
      p.join(Platform.environment['HOME']!, '.cache'),
    ).createTemp('cullimingo_video_e2e');
    for (var i = 1; i <= 2; i++) {
      final image = img.Image(width: 640, height: 420);
      img.fill(image, color: img.ColorRgb8(60 * i, 90, 200 - 40 * i));
      File(
        p.join(shoot.path, 'AAA_photo$i.jpg'),
      ).writeAsBytesSync(img.encodeJpg(image));
    }
    final clipPath = p.join(shoot.path, 'ZZZ_clip.mp4');
    // Content is irrelevant — isVideoPath keys off the extension, and a
    // failed EXIF read on garbage bytes is swallowed (readPhotoExif returns
    // empty on any error), so it just sorts last for lacking a capture time.
    File(clipPath).writeAsBytesSync(List.filled(256, 0));

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
    expect(find.byType(PhotoCell), findsNWidgets(3));
    await tester.pump(const Duration(seconds: 2)); // let thumbnails land
    await shot('1-grid-with-video-cell');

    // Tap the first (photo) cell to focus it, then Enter opens the loupe on
    // it directly (Enter on a *video* would instead hand off to
    // openExternally without opening the loupe — this is why we start on a
    // photo and blit over with `]` below, rather than focusing the video).
    await tester.tap(find.byType(PhotoCell).first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    await shot('1b-after-enter');
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.byTooltip('Open in system player'), findsNothing);

    // `]` twice blits to the video (sorted last by filename).
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.byTooltip('Open in system player'), findsOneWidget);
    await shot('2-loupe-play-button-on-video');

    // The real thing: tap it, and confirm a real process actually launched
    // referencing the clip (xdg-open handing off to the desktop's default
    // video handler) — not just that the button exists.
    expect(
      Process.runSync('pgrep', ['-f', clipPath]).stdout.toString().trim(),
      isEmpty,
      reason: 'nothing should reference the clip before the tap',
    );
    await tester.tap(find.byTooltip('Open in system player'));
    await tester.pump();

    var pgrepOutput = '';
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      pgrepOutput = Process.runSync('pgrep', [
        '-af',
        clipPath,
      ]).stdout.toString().trim();
      if (pgrepOutput.isNotEmpty) break;
    }
    // ignore: avoid_print — this is the evidence for the report.
    print('SPAWNED-FOR-CLIP:\n$pgrepOutput');
    await shot('3-after-tap-system-player-launched');

    expect(
      pgrepOutput,
      isNotEmpty,
      reason:
          'tapping the play button should hand the clip off to a real '
          'external process via xdg-open',
    );

    // Clean up whatever got launched so no window/player is left behind.
    Process.runSync('pkill', ['-f', clipPath]);
    shoot.deleteSync(recursive: true);
  });
}
