import 'dart:ui' show AppExitResponse;

import 'package:cullimingo/app/theme/app_theme.dart';
import 'package:cullimingo/features/cull/presentation/cull_page.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Root widget for Cullimingo. A single-window desktop app, so no router yet
/// (see `BUILD_PLAN.md` §2 — go_router only when real multi-screen nav lands).
class CullimingoApp extends ConsumerStatefulWidget {
  /// Creates the root application widget.
  const CullimingoApp({super.key});

  @override
  ConsumerState<CullimingoApp> createState() => _CullimingoAppState();
}

class _CullimingoAppState extends ConsumerState<CullimingoApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Drain-on-quit guard: hold the exit until pending XMP-sidecar writes
    // flush, so a ⌘Q right after a batch of marks can't quit before disk.
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<AppExitResponse> _onExitRequested() async {
    await ref.read(sidecarSyncProvider.notifier).drain();
    return AppExitResponse.exit;
  }

  @override
  Widget build(BuildContext context) {
    final tooltips = ref.watch(tooltipsEnabledProvider);
    return MaterialApp(
      title: 'Cullimingo',
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),
      // Wrap above the Navigator so the toggle reaches dialog/overlay routes.
      builder: (context, child) => TooltipVisibility(
        visible: tooltips,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const CullPage(),
    );
  }
}
