// Manual end-to-end check that real camera files render in the REAL app:
// a Sony .HIF (GitHub #10) and RAWs on both preview paths — embedded JPEG
// and the LibRaw demosaic fallback (#5, #7). Opt-in like
// test/core/raw/raw_samples_test.dart: the files live in the local sample
// set (CULLIMINGO_SAMPLES), never in the repo. Not part of CI.
//
//   CULLIMINGO_SAMPLES=~/.cache/cullimingo/samples \
//     flutter test integration_test/heif_raw_previews_e2e_test.dart -d linux
//
// CULLIMINGO_SHOTS=<dir> saves screenshots (screencapture on macOS,
// spectacle on KDE, ImageMagick `import` under X11/Xvfb).
import 'dart:io';

import 'package:cullimingo/app/app.dart';
import 'package:cullimingo/core/cache/preview_cache.dart';
import 'package:cullimingo/core/cache/vips.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/raw/libraw_preview_extractor.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/widgets/photo_cell.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

/// Sample-set paths (relative to CULLIMINGO_SAMPLES) → what they exercise.
const samples = {
  'sony/Sony_A7CII_A7C06498.HIF': 'HEIF, embedded thumbnails (#10)',
  'sdr/Nikon_Z5_14bit_lossless.NEF': 'RAW, embedded JPEG',
  'eric/DSC_7416.NEF': 'RAW, demosaic fallback (#7)',
};

Future<void> shot(String name) async {
  final dir = Platform.environment['CULLIMINGO_SHOTS'];
  if (dir == null) return;
  Directory(dir).createSync(recursive: true);
  final out = p.join(dir, '$name.png');
  if (Platform.isMacOS) {
    await Process.run('screencapture', ['-x', out]);
    return;
  }
  final r = await Process.run('spectacle', ['-abno', out]).catchError(
    (_) => Process.run('import', ['-window', 'root', out]),
  );
  if (r.exitCode != 0) await Process.run('import', ['-window', 'root', out]);
}

Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('timed out waiting for $finder');
}

int longEdgeOf(Uint8List jpeg) {
  final d = jpegDimensions(jpeg)!;
  return d.width > d.height ? d.width : d.height;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final root = Platform.environment['CULLIMINGO_SAMPLES'];

  testWidgets(
    'HIF and RAW samples render in the grid and the loupe',
    skip: root == null,
    (tester) async {
      // The app under test shares the real app's settings.json (open
      // folders, window size): put it back exactly as it was afterwards.
      final settings = File(
        p.join((await getApplicationSupportDirectory()).path, 'settings.json'),
      );
      final saved = settings.existsSync() ? settings.readAsBytesSync() : null;
      addTearDown(() {
        if (saved == null) {
          if (settings.existsSync()) settings.deleteSync();
        } else {
          settings.writeAsBytesSync(saved);
        }
      });

      Vips.warmUpProcess(); // as main() does, before pool workers spawn
      // main() sizes the window (default 1280×800, never below 960×640);
      // without it the test window opens narrower than the app allows and
      // the loupe toolbar overflows.
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1280, 800));

      final shoot = await Directory(
        p.join(Platform.environment['HOME']!, '.cache'),
      ).createTemp('cullimingo_e2e_previews');
      addTearDown(() => shoot.delete(recursive: true));
      final paths = <String, String>{};
      for (final rel in samples.keys) {
        final src = File(p.join(root!, rel));
        expect(src.existsSync(), isTrue, reason: 'missing sample $rel');
        paths[rel] = src.copySync(p.join(shoot.path, p.basename(rel))).path;
      }

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
      // Every tier is really decoded: the samples are copied to a fresh
      // folder each run, so their cache keys are new. (Never clear() here —
      // the cache is the real app's.)
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
      expect(find.byType(PhotoCell), findsNWidgets(samples.length));

      // Through the app's own cache + pool: what the cells and loupe show.
      final cache = container.read(previewCacheProvider);
      for (final MapEntry(key: rel, value: path) in paths.entries) {
        for (final tier in [PreviewTier.thumb, PreviewTier.loupe]) {
          final watch = Stopwatch()..start();
          final bytes = await tester.runAsync(() => cache.get(path, tier));
          expect(bytes, isNotNull, reason: '$rel (${samples[rel]}) @ $tier');
          // The run log is the report.
          // ignore: avoid_print
          print(
            '$rel @ ${tier.name}: ${longEdgeOf(bytes!)} px long edge, '
            '${watch.elapsedMilliseconds} ms',
          );
        }
      }
      await tester.pump(const Duration(seconds: 1));
      await shot('1-grid');

      // Each file in the loupe, opened and stepped through with real keys.
      await tester.tap(find.byType(PhotoCell).first);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      for (var i = 0; i < samples.length; i++) {
        if (i > 0) await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(milliseconds: 300));
        await shot('${i + 2}-loupe');
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await shot('9-grid-after-loupe');
    },
  );
}
