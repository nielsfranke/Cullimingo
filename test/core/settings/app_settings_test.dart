import 'dart:convert';
import 'dart:io';

import 'package:cullimingo/core/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// Test-only transitive deps (via path_provider) for mocking the platform.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// Test-only transitive dep (via path_provider) for the mock mixin.
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cm_settings');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });
  tearDown(() => tempDir.deleteSync(recursive: true));

  test(
    "concurrent writers from separate loads keep each other's keys",
    () async {
      // Mirrors the Settings-dialog apply: several independent
      // AppSettings.load().then(setX) at once. None must clobber the others.
      final a = await AppSettings.load();
      final b = await AppSettings.load();
      final c = await AppSettings.load();
      await Future.wait([
        a.setShowTooltips(false),
        b.setReopenLastFolders(true),
        c.setContactSheetBaseUrl('https://x'),
      ]);

      final reloaded = await AppSettings.load();
      expect(reloaded.showTooltips, isFalse);
      expect(reloaded.reopenLastFolders, isTrue);
      expect(reloaded.contactSheetBaseUrl, 'https://x');
    },
  );

  test(
    'lastContactSheet round-trips and the legacy token can be blanked',
    () async {
      File(
        p.join(tempDir.path, 'settings.json'),
      ).writeAsStringSync(jsonEncode({'csToken': 'cs_pat_old'}));

      final settings = await AppSettings.load();
      expect(settings.contactSheetToken, 'cs_pat_old');
      await settings.setLastContactSheet({'size': 3072, 'quality': 70});
      await (await AppSettings.load()).clearLegacyContactSheetToken();

      final reloaded = await AppSettings.load();
      expect(reloaded.lastContactSheet, {'size': 3072, 'quality': 70});
      expect(reloaded.contactSheetToken, isNull);
    },
  );

  test(
    'a setter only flushes its own key, preserving unrelated stored keys',
    () async {
      await (await AppSettings.load()).setLastFolders(['/a', '/b']);
      // A different instance changing one key must not drop lastFolders.
      await (await AppSettings.load()).setReopenLastFolders(true);

      final reloaded = await AppSettings.load();
      expect(reloaded.lastFolders, ['/a', '/b']);
      expect(reloaded.reopenLastFolders, isTrue);
    },
  );

  test('a corrupt settings file still yields a store that can save', () async {
    final file = File(p.join(tempDir.path, 'settings.json'))
      ..writeAsStringSync('{broken json');

    // Data is lost, but the handle isn't — the save must land on disk.
    final settings = await AppSettings.load();
    await settings.setShowTooltips(false);

    expect(
      jsonDecode(file.readAsStringSync()),
      containsPair('showTooltips', false),
    );
  });

  test('saves are atomic: a reader never sees a half-written file', () async {
    // The live failure (2026-07-03): save truncated the file in place, a
    // concurrent load() read broken JSON mid-write, silently became
    // file-less, and its own save vanished. Hammer interleaved load+save
    // cycles; with write-to-temp + rename every load sees complete JSON, so
    // every save must survive.
    await (await AppSettings.load()).setLastDestination('/seed');
    for (var i = 0; i < 25; i++) {
      final writeA = AppSettings.load().then(
        (s) => s.setGridCellWidth(100.0 + i),
      );
      final writeB = AppSettings.load().then((s) => s.setShowTooltips(i.isOdd));
      await Future.wait([writeA, writeB]);

      final check = await AppSettings.load();
      expect(check.lastDestination, '/seed', reason: 'iteration $i');
      expect(check.gridCellWidth, 100.0 + i, reason: 'iteration $i');
      expect(check.showTooltips, i.isOdd, reason: 'iteration $i');
    }
  });

  test('lastFolders + active tab round-trip', () async {
    await (await AppSettings.load()).setLastFoldersWithActive([
      '/a',
      '/b',
      '/c',
    ], 2);
    final reloaded = await AppSettings.load();
    expect(reloaded.lastFolders, ['/a', '/b', '/c']);
    expect(reloaded.lastActiveTab, 2);
  });

  test('template snapshots + apply-on-ingest round-trip', () async {
    final s = await AppSettings.load();
    await s.setMetadataTemplates({
      'active': 'Wire',
      'templates': [
        {
          'name': 'Wire',
          'template': {
            'fields': {'credit': 'AP'},
          },
        },
      ],
    });
    await s.setApplyTemplateOnIngest(true);

    final reloaded = await AppSettings.load();
    expect(reloaded.metadataTemplates!['active'], 'Wire');
    expect(reloaded.applyTemplateOnIngest, isTrue);
  });

  test('legacy single-template key stays readable for migration', () async {
    File(p.join(tempDir.path, 'settings.json')).writeAsStringSync(
      jsonEncode({
        'metadataTemplate': {
          'fields': {'credit': 'AP'},
        },
      }),
    );

    final s = await AppSettings.load();
    expect(s.metadataTemplate!['fields'], {'credit': 'AP'});
  });

  test('name presets round-trip; default is empty', () async {
    final s = await AppSettings.load();
    expect(s.namePresets, isEmpty);

    await s.setNamePresets([
      {
        'name': 'Wire',
        'folder': '{YYYY}',
        'file': '{shoot}_{seq:4}',
        'counterStart': 1,
      },
    ]);

    final reloaded = await AppSettings.load();
    expect(reloaded.namePresets, hasLength(1));
    expect(reloaded.namePresets.first['name'], 'Wire');
    expect(reloaded.namePresets.first['file'], '{shoot}_{seq:4}');
  });

  test('last export/import settings round-trip; default null', () async {
    final s = await AppSettings.load();
    expect(s.lastExport, isNull);
    expect(s.lastImport, isNull);

    await s.setLastExport({'quality': 90, 'format': 'webp'});
    await s.setLastImport({'verify': false});

    final reloaded = await AppSettings.load();
    expect(reloaded.lastExport!['quality'], 90);
    expect(reloaded.lastExport!['format'], 'webp');
    expect(reloaded.lastImport!['verify'], false);
  });

  test(
    'loupe analysis toggles round-trip; default off (sticky overlays)',
    () async {
      final s = await AppSettings.load();
      expect(s.loupeHistogram, isFalse);
      expect(s.loupeClipping, isFalse);
      expect(s.loupeFocusPeaking, isFalse);

      await s.setLoupeHistogram(true);
      await s.setLoupeFocusPeaking(true);

      final reloaded = await AppSettings.load();
      expect(reloaded.loupeHistogram, isTrue);
      expect(reloaded.loupeClipping, isFalse);
      expect(reloaded.loupeFocusPeaking, isTrue);
    },
  );

  test('auto-open Import on card insert round-trips; default on', () async {
    final s = await AppSettings.load();
    expect(s.autoOpenImportOnCardInsert, isTrue);

    await s.setAutoOpenImportOnCardInsert(false);

    final reloaded = await AppSettings.load();
    expect(reloaded.autoOpenImportOnCardInsert, isFalse);
  });

  test('template defaults: null snapshots + legacy, ingest off', () async {
    final s = await AppSettings.load();
    expect(s.metadataTemplates, isNull);
    expect(s.metadataTemplate, isNull);
    expect(s.applyTemplateOnIngest, isFalse);
  });
}
