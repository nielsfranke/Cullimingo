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
    _showNotice(
      Notice(
        kind: NoticeKind.info,
        icon: Icons.system_update_alt,
        message: 'Cullimingo ${update.version} is available.',
        actions: [
          (
            label: 'Download',
            onTap: () =>
                unawaited(openExternally(update.releaseUrl.toString())),
          ),
        ],
      ),
    );
  }
}
