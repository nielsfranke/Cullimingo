import 'package:cullimingo/core/logging/provider_diagnostics.dart';
import 'package:flutter/foundation.dart';
import 'package:talker_flutter/talker_flutter.dart';

/// Whether the benign "rebuild scheduled during build" has been noted already
/// (we log it once per session, not on every occurrence).
bool _buildPhaseNoted = false;

/// The app-wide [Talker] log/error sink (`BUILD_PLAN.md` §8). A single instance
/// so the log viewer and every logging call share one history. Call
/// `appTalker.info/warning/error/handle(...)` for runtime diagnostics.
final Talker appTalker = TalkerFlutter.init();

/// Routes Flutter's framework + platform error hooks into [appTalker] so
/// crashes and uncaught async errors land in the in-app log viewer (not just
/// the console). Call once from `main()` after the binding is initialised; it
/// chains the previous [FlutterError.onError] so the default red-screen/console
/// report still fires in debug.
void setupLogging() {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    final message = details.exceptionAsString();
    // A "setState/markNeedsBuild called during build" from Riverpod is a benign,
    // framework-recovered scheduling artifact: reading a provider during a
    // widget build (e.g. the grouping providers when the open folder changes on
    // a rapid tab/folder switch) coalesces a rebuild to the next frame — no
    // crash, no data loss. It's a Riverpod 3.3 behaviour, not an app bug, so we
    // don't surface it as an error or escalate to the red screen. Note it once
    // per session (with the recent provider cascade) for context.
    if (message.contains('called during build')) {
      if (!_buildPhaseNoted) {
        _buildPhaseNoted = true;
        appTalker.info(
          'Coalesced a Riverpod rebuild scheduled during build (benign, '
          'recovered by Flutter; happens on rapid tab/folder switches). '
          'Recent provider activity:\n${appProviderDiagnostics.recentDump()}',
        );
      }
      return;
    }
    appTalker.handle(details.exception, details.stack, 'Flutter error');
    previousOnError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    appTalker.handle(error, stack, 'Uncaught error');
    return true;
  };
}
