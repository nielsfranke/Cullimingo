import 'dart:async';

import 'package:cullimingo/app/app.dart';
import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/core/cache/memory_budget.dart';
import 'package:cullimingo/core/cache/vips.dart';
import 'package:cullimingo/core/logging/app_logger.dart';
import 'package:cullimingo/core/logging/provider_diagnostics.dart';
import 'package:cullimingo/core/settings/app_settings.dart';
import 'package:cullimingo/core/settings/performance_preset.dart';
import 'package:cullimingo/core/update/update_checker.dart';
import 'package:cullimingo/core/update/update_providers.dart';
import 'package:cullimingo/core/version/app_version.g.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/filter/domain/filter_preset.dart';
import 'package:cullimingo/features/filter/presentation/filter_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Capture framework + uncaught errors into the in-app log viewer (§8).
  setupLogging();

  // Initialise libvips once on this isolate before any preview-worker isolate
  // spawns — libvips' global type registration isn't safe to run concurrently,
  // and the workers share this process's GC safepoints, so a first-use race
  // would freeze the whole app. See Vips.warmUpProcess.
  Vips.warmUpProcess();

  await windowManager.ensureInitialized();

  // Reopen at the last-used window size (default on first run).
  final settings = await AppSettings.load();

  // Resolve the active performance preset (user's choice, else the one
  // recommended for this machine's RAM) into concrete numbers — applied once at
  // startup (the setting takes effect on next launch).
  final totalRam = totalPhysicalMemoryBytes();
  final preset =
      PerformancePreset.fromName(settings.performancePresetName) ??
      recommendedPreset(totalBytes: totalRam);
  final performance = resolvePerformance(preset, totalBytes: totalRam);

  // Trade RAM for instant scrolling (Photo-Mechanic style): keep many decoded
  // thumbnails resident so scrolling back to them is immediate. Pairs with the
  // in-RAM byte cache in PreviewCache; the budget comes from the preset.
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = performance.ramBudgetBytes
    ..maximumSize = 3000;

  final saved = settings.windowSize;
  final windowOptions = WindowOptions(
    size: saved == null
        ? const Size(1280, 800)
        : Size(saved.width, saved.height),
    minimumSize: const Size(960, 640),
    center: saved == null,
    title: 'Cullimingo',
    backgroundColor: AppColors.bgBase,
    titleBarStyle: TitleBarStyle.normal,
  );

  final pos = settings.windowPosition;
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    // Position BEFORE (re-)applying the size. The size in [windowOptions] is
    // applied to the still-hidden window on whichever display it first lands
    // on, and macOS clamps a window's height to that display's visible frame —
    // so a window saved taller than a *shorter* second monitor came back short
    // on a dual-monitor setup. Move onto the saved screen first, then re-apply
    // the saved size there, where its full height fits.
    if (pos != null) {
      await windowManager.setPosition(Offset(pos.x, pos.y));
      if (saved != null) {
        await windowManager.setSize(Size(saved.width, saved.height));
      }
    }
    await windowManager.show();
    await windowManager.focus();
  });
  windowManager.addListener(_WindowBoundsPersister(settings));

  runApp(
    ProviderScope(
      observers: [appProviderDiagnostics],
      overrides: [
        performanceSettingsProvider.overrideWithValue(performance),
        tooltipsEnabledSeedProvider.overrideWithValue(settings.showTooltips),
        autoAdvanceAfterMarkSeedProvider.overrideWithValue(
          settings.autoAdvanceAfterMark,
        ),
        propagateMarksToStackSeedProvider.overrideWithValue(
          settings.propagateMarksToStack,
        ),
        autoExpandBracketsOnSelectSeedProvider.overrideWithValue(
          settings.autoExpandBracketsOnSelect,
        ),
        cullShortcutsSeedProvider.overrideWithValue(settings.shortcutOverrides),
        shortcutsHintSeenSeedProvider.overrideWithValue(
          settings.hasSeenShortcutsHint,
        ),
        markConfirmationEnabledSeedProvider.overrideWithValue(
          settings.markConfirmationOverlay,
        ),
        filterPresetsSeedProvider.overrideWithValue(
          FilterPreset.decodeList(settings.filterPresets),
        ),
        filmstripVisibleSeedProvider.overrideWithValue(
          settings.filmstripVisible,
        ),
        recentFoldersSeedProvider.overrideWithValue(settings.recentFolders),
        // Retry transient preview misses in production (off in widget tests so
        // the back-off timers never linger — see [previewRetryEnabled]).
        previewRetryEnabledProvider.overrideWithValue(true),
        // Run the real GitHub update check at launch (throttled + opt-out);
        // the default provider is a null no-op so widget tests never hit the
        // network. See [availableUpdateProvider].
        availableUpdateProvider.overrideWith(
          (ref) => checkForUpdatesOnStartup(
            settings: settings,
            currentVersion: kAppVersion,
          ),
        ),
        if (settings.gridCellWidth != null)
          gridCellWidthSeedProvider.overrideWithValue(settings.gridCellWidth!),
      ],
      child: const CullimingoApp(),
    ),
  );
}

/// Saves the window size + position (debounced) whenever the user resizes or
/// moves it, so the next launch reopens the same way.
class _WindowBoundsPersister extends WindowListener {
  _WindowBoundsPersister(this._settings);

  final AppSettings _settings;
  Timer? _debounce;

  @override
  void onWindowResize() => _schedule();

  @override
  void onWindowMove() => _schedule();

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final size = await windowManager.getSize();
      final position = await windowManager.getPosition();
      await _settings.setWindowSize(size.width, size.height);
      await _settings.setWindowPosition(position.dx, position.dy);
    });
  }
}
