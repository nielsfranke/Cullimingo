// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'send_to_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The user's configured "Send to" editors, loaded from settings. Invalidated
/// by the Settings dialog after the list is edited so the context menu / ⌘E
/// pick up changes without a restart.

@ProviderFor(sendToEditors)
final sendToEditorsProvider = SendToEditorsProvider._();

/// The user's configured "Send to" editors, loaded from settings. Invalidated
/// by the Settings dialog after the list is edited so the context menu / ⌘E
/// pick up changes without a restart.

final class SendToEditorsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ExternalEditor>>,
          List<ExternalEditor>,
          FutureOr<List<ExternalEditor>>
        >
    with
        $FutureModifier<List<ExternalEditor>>,
        $FutureProvider<List<ExternalEditor>> {
  /// The user's configured "Send to" editors, loaded from settings. Invalidated
  /// by the Settings dialog after the list is edited so the context menu / ⌘E
  /// pick up changes without a restart.
  SendToEditorsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sendToEditorsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sendToEditorsHash();

  @$internal
  @override
  $FutureProviderElement<List<ExternalEditor>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<ExternalEditor>> create(Ref ref) {
    return sendToEditors(ref);
  }
}

String _$sendToEditorsHash() => r'5953cca136c1da4bccf77738f5093222497e1f4f';
