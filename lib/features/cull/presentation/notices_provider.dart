import 'dart:async';

import 'package:cullimingo/features/cull/presentation/widgets/notice_bar.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'notices_provider.g.dart';

/// The single app-wide notification surface (`BUILD_PLAN.md` §7), as state:
/// the page's bottom bar watches this, and long-running jobs (which outlive
/// any one page build — see `cull_job_runner.dart`) report through it without
/// holding a `BuildContext`. Transient messages (info/success without
/// actions) auto-dismiss; warnings and actionable notices stay until
/// dismissed. Null = nothing showing.
@Riverpod(keepAlive: true)
class NoticesController extends _$NoticesController {
  Timer? _timer;

  @override
  Notice? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  /// Shows [notice], replacing whatever is up. Transient ones (no actions,
  /// info/success) clear themselves after a few seconds so the layout doesn't
  /// keep a stale message.
  void show(Notice notice) {
    _timer?.cancel();
    state = notice;
    final transient =
        notice.actions.isEmpty &&
        (notice.kind == NoticeKind.info || notice.kind == NoticeKind.success);
    if (transient) {
      _timer = Timer(const Duration(seconds: 4), dismiss);
    }
  }

  /// Convenience for a plain message (the common case, replaces SnackBars).
  void notify(String message, {NoticeKind kind = NoticeKind.info}) =>
      show(Notice.of(kind, message));

  /// Clears the bar.
  void dismiss() {
    _timer?.cancel();
    state = null;
  }

  /// Cancels a pending auto-dismiss *without* touching the state. For the
  /// page's dispose only: mutating provider state there is unsafe (the
  /// disposing page still watches this provider), but the timer must not
  /// outlive the page — widget tests assert no pending timers after teardown.
  void stopAutoDismiss() => _timer?.cancel();
}
