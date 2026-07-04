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
