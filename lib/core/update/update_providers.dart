import 'package:cullimingo/core/update/update_checker.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'update_providers.g.dart';

/// The result of the startup update check: a newer GitHub release than the
/// running build, or null when up to date / disabled / offline.
///
/// It **defaults to null** (a no-op) so widget tests never touch the network.
/// `main()` overrides it with the real, throttled [checkForUpdatesOnStartup]
/// when the user hasn't opted out — mirroring the `previewRetryEnabled`
/// production-opt-in pattern. `CullPage` listens to it and flashes an
/// "update available" notice when it resolves to a non-null value.
@Riverpod(keepAlive: true)
Future<UpdateInfo?> availableUpdate(Ref ref) async => null;
