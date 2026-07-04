// Manual end-to-end check of the startup "update available" notice on Linux.
// Launches the REAL app window and overrides the update provider with a fake
// newer release (the real GitHub check can't fire until the repo is mirrored),
// so we can see the notice + its Download action render for real. Not in CI.
import 'dart:io';

import 'package:cullimingo/app/app.dart';
import 'package:cullimingo/core/cache/vips.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/update/update_checker.dart';
import 'package:cullimingo/core/update/update_providers.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

const shotsDir =
    '/tmp/claude-1000/-home-niels-Cullimingo/'
    'af009576-d235-4f83-be37-9e33dad98588/scratchpad/shots';

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

  testWidgets('startup update check flashes the "update available" notice', (
    tester,
  ) async {
    Directory(shotsDir).createSync(recursive: true);
    Vips.warmUpProcess(); // as main() does, before pool workers spawn

    // Real app + real providers; the DB is a scratch store and the update
    // provider is overridden to a fake newer release — exactly the shape
    // main() will feed it once GitHub Releases exist.
    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          availableUpdateProvider.overrideWith(
            (ref) async => UpdateInfo(
              version: '1.4.0',
              releaseUrl: Uri.parse(
                'https://github.com/nielsfranke/Cullimingo/releases/latest',
              ),
            ),
          ),
        ],
        child: const CullimingoApp(),
      ),
    );

    // The CullPage listener fires when the (overridden) future resolves; the
    // notice bar then appears above the export bar even on the empty grid.
    await pumpUntil(
      tester,
      find.text('Cullimingo 1.4.0 is available.'),
    );
    expect(find.text('Download'), findsOneWidget);
    expect(find.byIcon(Icons.system_update_alt), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400)); // settle for the grab
    await shot('update-notice');
  });
}
