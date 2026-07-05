import 'package:cullimingo/core/settings/app_settings.dart';
import 'package:cullimingo/features/handoff/domain/external_editor.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'send_to_providers.g.dart';

/// The user's configured "Send to" editors, loaded from settings. Invalidated
/// by the Settings dialog after the list is edited so the context menu / ⌘E
/// pick up changes without a restart.
@riverpod
Future<List<ExternalEditor>> sendToEditors(Ref ref) async {
  final settings = await AppSettings.load();
  return [
    for (final raw in settings.sendToEditors) ?ExternalEditor.fromJson(raw),
  ];
}

/// Whether the ContactSheet integration is set up, so the grid context menu can
/// offer "Send to ContactSheet" / "Pull marks". Gated on the base URL alone
/// (pure settings, no secret-store read) so building a menu never triggers a
/// keychain prompt. Invalidated after the ContactSheet dialog closes, in case
/// the connection was just configured. Kept warm by the page, read
/// synchronously in the menu.
@riverpod
Future<bool> contactSheetConfigured(Ref ref) async {
  final settings = await AppSettings.load();
  return (settings.contactSheetBaseUrl ?? '').isNotEmpty;
}
