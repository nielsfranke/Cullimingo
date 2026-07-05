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

/// Whether the ContactSheet integration is set up, so the grid context menu can
/// offer "Send to ContactSheet" / "Pull marks". Gated on the base URL alone
/// (pure settings, no secret-store read) so building a menu never triggers a
/// keychain prompt. Invalidated after the ContactSheet dialog closes, in case
/// the connection was just configured. Kept warm by the page, read
/// synchronously in the menu.

@ProviderFor(contactSheetConfigured)
final contactSheetConfiguredProvider = ContactSheetConfiguredProvider._();

/// Whether the ContactSheet integration is set up, so the grid context menu can
/// offer "Send to ContactSheet" / "Pull marks". Gated on the base URL alone
/// (pure settings, no secret-store read) so building a menu never triggers a
/// keychain prompt. Invalidated after the ContactSheet dialog closes, in case
/// the connection was just configured. Kept warm by the page, read
/// synchronously in the menu.

final class ContactSheetConfiguredProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// Whether the ContactSheet integration is set up, so the grid context menu can
  /// offer "Send to ContactSheet" / "Pull marks". Gated on the base URL alone
  /// (pure settings, no secret-store read) so building a menu never triggers a
  /// keychain prompt. Invalidated after the ContactSheet dialog closes, in case
  /// the connection was just configured. Kept warm by the page, read
  /// synchronously in the menu.
  ContactSheetConfiguredProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'contactSheetConfiguredProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$contactSheetConfiguredHash();

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    return contactSheetConfigured(ref);
  }
}

String _$contactSheetConfiguredHash() =>
    r'747fcd64a3c12b97efecbb25df953790455e4c9a';
