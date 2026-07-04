part of 'cull_page.dart';

/// The single app-wide notification surface (`BUILD_PLAN.md` §7).
mixin _CullNotices on ConsumerState<CullPage> {
  // The single app-wide notification surface: a coloured bottom bar. Transient
  // messages (info/success) auto-dismiss; ones with actions or a warning/error
  // stay until dismissed. Null = nothing showing.
  Notice? _notice;

  Timer? _noticeTimer;

  void _dismissNotice() {
    _noticeTimer?.cancel();
    if (mounted) setState(() => _notice = null);
  }

  /// The single entry point for every app notification. Shows [notice] in the
  /// bottom bar; transient ones (no actions, info/success) clear themselves
  /// after a few seconds so the layout doesn't keep a stale message.
  void _showNotice(Notice notice) {
    _noticeTimer?.cancel();
    setState(() => _notice = notice);
    final transient =
        notice.actions.isEmpty &&
        (notice.kind == NoticeKind.info || notice.kind == NoticeKind.success);
    if (transient) {
      _noticeTimer = Timer(const Duration(seconds: 4), _dismissNotice);
    }
  }

  /// Convenience for a plain message (the common case, replaces SnackBars).
  void _notify(String message, {NoticeKind kind = NoticeKind.info}) =>
      _showNotice(Notice.of(kind, message));

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
