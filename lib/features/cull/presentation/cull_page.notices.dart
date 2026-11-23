part of 'cull_page.dart';

/// The page's face of the app-wide notification surface (`BUILD_PLAN.md` §7):
/// thin forwarders onto [NoticesController] — where the state and the
/// auto-dismiss timer live, so long-running jobs report without a
/// `BuildContext` — plus the bar's build-time read.
mixin _CullNotices on ConsumerState<CullPage> {
  // Captured at init: `ref` is unsafe in dispose, but the auto-dismiss timer
  // must die with the page — widget tests assert no pending timers after
  // teardown. Only the timer: mutating the provider's state here would
  // notify the very element being unmounted.
  NoticesController? _noticesForDispose;

  @override
  void initState() {
    super.initState();
    _noticesForDispose = ref.read(noticesControllerProvider.notifier);
  }

  @override
  void dispose() {
    _noticesForDispose?.stopAutoDismiss();
    super.dispose();
  }

  /// The notice currently showing, watched so the bar rebuilds with it.
  /// Only read during build.
  Notice? get _notice => ref.watch(noticesControllerProvider);

  void _dismissNotice() =>
      ref.read(noticesControllerProvider.notifier).dismiss();

  /// The single entry point for every app notification — see
  /// [NoticesController.show].
  void _showNotice(Notice notice) =>
      ref.read(noticesControllerProvider.notifier).show(notice);

  /// Convenience for a plain message (the common case, replaces SnackBars).
  void _notify(String message, {NoticeKind kind = NoticeKind.info}) =>
      ref.read(noticesControllerProvider.notifier).notify(message, kind: kind);

  /// Announces a newer release found by the startup update check, with a
  /// "Download" action that opens the GitHub release page in the browser. Has
  /// an action, so the bar stays until the user dismisses it.
  void _showUpdateNotice(UpdateInfo update) {
    final target = detectInstallTarget();
    _showNotice(
      Notice(
        kind: NoticeKind.info,
        icon: Icons.system_update_alt,
        message: 'Cullimingo ${update.version} is available.',
        actions: [
          if (target != null)
            (
              label: 'Install update',
              onTap: () => unawaited(_installUpdate(update, target)),
            ),
          (
            label: target == null ? 'Download' : "What's new",
            onTap: () =>
                unawaited(openExternally(update.releaseUrl.toString())),
          ),
        ],
      ),
    );
  }

  /// Downloads and verifies [update] for [target], then offers the restart
  /// that installs it. The running app stays as it is until then — and on
  /// any failure, which falls back to the release page.
  Future<void> _installUpdate(UpdateInfo update, InstallTarget target) async {
    final notices = ref.read(noticesControllerProvider.notifier);
    final version = update.version;
    void failed(UpdateFailure failure, Object? detail) {
      appTalker.warning('Update to $version failed: ${failure.name}: $detail');
      notices.show(
        Notice(
          kind: NoticeKind.warning,
          icon: Icons.system_update_alt,
          message: failure.message,
          actions: [
            (
              label: 'Download page',
              onTap: () =>
                  unawaited(openExternally(update.releaseUrl.toString())),
            ),
          ],
        ),
      );
    }

    if (!canReplace(target)) {
      failed(UpdateFailure.permission, target.path);
      return;
    }
    void progress(int percent) => notices.show(
      Notice(
        kind: NoticeKind.info,
        icon: Icons.downloading,
        message: 'Downloading Cullimingo $version… $percent %',
        log: false,
      ),
    );
    progress(0);
    try {
      var shown = 0;
      final staged = await downloadUpdate(
        version: version,
        target: target,
        workDir: await updateWorkDir(),
        onProgress: (received, total) {
          final percent = total == 0 ? 0 : received * 100 ~/ total;
          if (percent >= shown + 5) progress(shown = percent);
        },
      );
      appTalker.info(
        'Update $version downloaded and verified (${target.method.name}): '
        '${staged.file.path}',
      );
      notices.show(
        Notice(
          kind: NoticeKind.success,
          icon: Icons.system_update_alt,
          message: 'Cullimingo $version is ready to install.',
          actions: [
            (
              label: 'Restart now',
              onTap: () => unawaited(_restartIntoUpdate(staged, failed)),
            ),
          ],
        ),
      );
    } on UpdateException catch (e) {
      failed(e.failure, e.detail);
    } on Object catch (e) {
      failed(UpdateFailure.network, e);
    }
  }

  /// Hands [staged] to the installer helper and quits; the helper installs
  /// once this process is gone and starts the new version.
  Future<void> _restartIntoUpdate(
    StagedUpdate staged,
    void Function(UpdateFailure, Object?) failed,
  ) async {
    try {
      await installAndRelaunch(staged);
    } on UpdateException catch (e) {
      failed(e.failure, e.detail);
      return;
    }
    appTalker.info('Restarting into Cullimingo ${staged.version}');
    // Let pending settings saves and the log reach the disk first.
    await AppSettings.flushWrites().timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );
    await flushFileLogging();
    exit(0);
  }
}
