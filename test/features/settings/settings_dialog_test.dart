import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cullimingo/core/cache/memory_budget.dart';
import 'package:cullimingo/core/secrets/secret_store.dart';
import 'package:cullimingo/core/settings/app_settings.dart';
import 'package:cullimingo/core/settings/performance_preset.dart';
import 'package:cullimingo/core/version/app_version.g.dart';
import 'package:cullimingo/features/settings/presentation/settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// Test-only transitive deps (via path_provider) for mocking the platform.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// Test-only transitive dep (via path_provider) for the mock mixin.
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Feeds a fixed app-support dir so the dialog's AppSettings reads resolve
/// promptly (an empty store on first run), instead of a pending platform call
/// that could clobber the user's selection mid-test.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.supportDir);
  final String supportDir;
  @override
  Future<String?> getApplicationSupportPath() async => supportDir;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cm_settings_dialog');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    // These tests tap Apply, which saves settings inside the test's FakeAsync
    // zone — detach the queue so a previous test's zone can't wedge it.
    AppSettings.resetWriteQueueForTests();
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  // The dialog is taller than the default 600px test viewport, so its action
  // buttons would land off-screen. Give every test a tall surface.
  Future<void> tallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  // Pumps a host with an "open" button that shows the dialog and stashes its
  // result. Returns a getter for the captured value once the dialog pops.
  Future<PerformancePreset? Function()> pumpDialog(
    WidgetTester tester, {
    Future<void> Function()? onClearCache,
  }) async {
    await tallSurface(tester);
    PerformancePreset? result;
    await tester.pumpWidget(
      ProviderScope(
        // The dialog reads the ContactSheet token through the secret store
        // before opening; the real store's platform channel never answers
        // under FakeAsync, so give it an in-memory one.
        overrides: [
          secretStoreProvider.overrideWithValue(InMemorySecretStore()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showSettingsDialog(
                    context,
                    onClearCache: onClearCache ?? () async {},
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  // Selects a group in the dialog's left nav-rail (sections now live under
  // General / Metadata / Delivery / About tabs rather than one long scroll).
  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  /// Drives the tester until Apply's background saves have fully flushed,
  /// returning the settings file's content.
  ///
  /// Flushed means: the write queue's tail is complete *and* every save
  /// chain's final key is on disk — _persist ends with hotCodes, and the
  /// tooltips provider writes showTooltips. The save futures live in the
  /// tester's fake-async zone but do real file I/O, so this alternates
  /// [WidgetTester.pump] (drives their continuations) with
  /// [WidgetTester.runAsync] (lets the I/O events actually deliver).
  Future<Map<String, dynamic>> drainApplyPersist(WidgetTester tester) async {
    const required = {'hotCodes', 'showTooltips'};
    final file = File(p.join(tempDir.path, 'settings.json'));
    for (var i = 0; i < 400; i++) {
      var queueIdle = false;
      unawaited(
        AppSettings.pendingWrites.whenComplete(() => queueIdle = true),
      );
      // Runs the whenComplete microtask when the queue tail is already done.
      await tester.pump();
      if (queueIdle) {
        // Tolerate a missing / mid-write file: keep polling.
        try {
          final map =
              jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
          if (required.every(map.containsKey)) return map;
        } on Object {
          // Not written yet.
        }
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await tester.pump();
    }
    throw StateError('settings persist never completed');
  }

  testWidgets('shows the settings sections across tabs', (tester) async {
    await pumpDialog(tester);

    expect(find.text('Settings'), findsOneWidget);
    // General is the default tab.
    expect(find.text('PERFORMANCE'), findsOneWidget);
    expect(find.text('INTERFACE'), findsOneWidget);
    expect(find.text('Show button tooltips'), findsOneWidget);
    expect(find.text('STARTUP'), findsOneWidget);
    expect(find.text('Reopen last folders on startup'), findsOneWidget);
    expect(find.text('CACHE'), findsOneWidget);
    expect(find.text('Clear thumbnail cache'), findsOneWidget);

    await openTab(tester, 'Delivery');
    expect(find.text('CONTACTSHEET'), findsOneWidget);

    await openTab(tester, 'About');
    expect(find.text('ABOUT'), findsOneWidget);
    expect(find.text('View logs'), findsOneWidget);
    expect(find.text('About & licenses'), findsOneWidget);
  });

  testWidgets('View logs opens the log viewer', (tester) async {
    await pumpDialog(tester);
    await openTab(tester, 'About');

    await tester.ensureVisible(find.text('View logs'));
    await tester.tap(find.text('View logs'));
    await tester.pumpAndSettle();

    expect(find.text('Cullimingo Logs'), findsOneWidget);
  });

  testWidgets('About & licenses shows the about dialog', (tester) async {
    await pumpDialog(tester);
    await openTab(tester, 'About');

    await tester.ensureVisible(find.text('About & licenses'));
    await tester.tap(find.text('About & licenses'));
    await tester.pumpAndSettle();

    // The about dialog shows the app name + version (and a View-licenses link).
    expect(find.byType(AboutDialog), findsOneWidget);
    expect(find.text(kAppVersion), findsOneWidget);
  });

  testWidgets('Cancel returns null', (tester) async {
    final result = await pumpDialog(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result(), isNull);
  });

  testWidgets('Apply returns the newly chosen preset', (tester) async {
    final ram = totalPhysicalMemoryBytes();
    final available = availablePresets(totalBytes: ram);
    final recommended = recommendedPreset(totalBytes: ram);
    final target = available.firstWhere((p) => p != recommended);

    final result = await pumpDialog(tester);

    final targetRow = find.ancestor(
      of: find.text(target.label),
      matching: find.byType(InkWell),
    );
    await tester.ensureVisible(targetRow);
    await tester.tap(targetRow);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(result(), target);
  });

  testWidgets('Clear thumbnail cache runs the callback', (tester) async {
    var cleared = false;
    await pumpDialog(tester, onClearCache: () async => cleared = true);

    await tester.ensureVisible(find.text('Clear thumbnail cache'));
    await tester.tap(find.text('Clear thumbnail cache'));
    await tester.pumpAndSettle();

    expect(cleared, isTrue);
    expect(find.text('Thumbnail cache cleared'), findsOneWidget);
  });

  group('template snapshots', () {
    /// Seeds `settings.json` in the fake app-support dir before the dialog
    /// loads.
    void seedSettings(Map<String, dynamic> data) => File(
      p.join(tempDir.path, 'settings.json'),
    ).writeAsStringSync(jsonEncode(data));

    /// Two snapshots, "Wire" active.
    void seedTwoSnapshots() => seedSettings({
      'metadataTemplates': {
        'active': 'Wire',
        'templates': [
          {
            'name': 'Wire',
            'template': {
              'fields': {'credit': 'Reuters'},
            },
          },
          {
            'name': 'Agency',
            'template': {
              'fields': {'credit': 'dpa'},
            },
          },
        ],
      },
    });

    /// Waits until Apply's background persist has flushed, then returns the
    /// persisted snapshots key. (The seed may already carry metadataTemplates,
    /// so this only reads it after the persist demonstrably ran.)
    Future<Map<String, dynamic>> persistedSnapshots(
      WidgetTester tester,
    ) async {
      final map = await drainApplyPersist(tester);
      return (map['metadataTemplates'] as Map).cast<String, dynamic>();
    }

    testWidgets('dropdown switches the active snapshot; Apply persists it', (
      tester,
    ) async {
      seedTwoSnapshots();
      await pumpDialog(tester);
      await openTab(tester, 'Metadata');

      expect(find.text('Edit "Wire" (1 fields)…'), findsOneWidget);

      await tester.ensureVisible(find.text('Wire'));
      await tester.tap(find.text('Wire'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agency').last);
      await tester.pumpAndSettle();

      expect(find.text('Edit "Agency" (1 fields)…'), findsOneWidget);

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      final persisted = await persistedSnapshots(tester);
      expect(persisted['active'], 'Agency');
      expect((persisted['templates'] as List).length, 2);
    });

    testWidgets('a legacy single template shows up as the Default snapshot', (
      tester,
    ) async {
      seedSettings({
        'metadataTemplate': {
          'fields': {'credit': 'AP'},
        },
      });
      await pumpDialog(tester);
      await openTab(tester, 'Metadata');

      expect(find.text('Default'), findsOneWidget);
      expect(find.text('Edit "Default" (1 fields)…'), findsOneWidget);
    });

    testWidgets('New template prompts for a name and opens the editor', (
      tester,
    ) async {
      await pumpDialog(tester);
      await openTab(tester, 'Metadata');

      expect(find.text('No saved templates'), findsOneWidget);
      expect(find.text('Set up template…'), findsOneWidget);

      await tester.ensureVisible(find.byTooltip('New template'));
      await tester.tap(find.byTooltip('New template'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Bundesliga');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // The template editor opens for the new snapshot; Save adds it.
      expect(find.text('Metadata template'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Bundesliga'), findsOneWidget);
      expect(find.text('Edit "Bundesliga" (0 fields)…'), findsOneWidget);
    });

    testWidgets('cancelling the editor adds no snapshot', (tester) async {
      await pumpDialog(tester);
      await openTab(tester, 'Metadata');

      await tester.ensureVisible(find.byTooltip('New template'));
      await tester.tap(find.byTooltip('New template'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Bundesliga');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      expect(find.text('No saved templates'), findsOneWidget);
      expect(find.text('Bundesliga'), findsNothing);
    });

    testWidgets('Rename keeps the snapshot but changes its name', (
      tester,
    ) async {
      seedTwoSnapshots();
      await pumpDialog(tester);
      await openTab(tester, 'Metadata');

      await tester.ensureVisible(find.byTooltip('Rename template'));
      await tester.tap(find.byTooltip('Rename template'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'AP');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('Edit "AP" (1 fields)…'), findsOneWidget);
      expect(find.text('Wire'), findsNothing);
    });

    testWidgets('Delete removes the active snapshot, next one takes over', (
      tester,
    ) async {
      seedTwoSnapshots();
      await pumpDialog(tester);
      await openTab(tester, 'Metadata');

      await tester.ensureVisible(find.byTooltip('Delete template'));
      await tester.tap(find.byTooltip('Delete template'));
      await tester.pumpAndSettle();

      expect(find.text('Edit "Agency" (1 fields)…'), findsOneWidget);
      expect(find.text('Wire'), findsNothing);

      await tester.tap(find.byTooltip('Delete template'));
      await tester.pumpAndSettle();

      expect(find.text('No saved templates'), findsOneWidget);
      expect(find.text('Set up template…'), findsOneWidget);
    });
  });
}
