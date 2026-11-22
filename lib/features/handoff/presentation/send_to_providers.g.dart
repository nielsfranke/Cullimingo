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

/// The app icon of a "Send to" editor as PNG bytes, for the toolbar button.
/// macOS only (the Finder icon of the `.app` bundle, via the native channel);
/// null elsewhere or when the lookup fails, and the button falls back to a
/// generic glyph. Kept alive: the icon doesn't change while the app runs.

@ProviderFor(editorIcon)
final editorIconProvider = EditorIconFamily._();

/// The app icon of a "Send to" editor as PNG bytes, for the toolbar button.
/// macOS only (the Finder icon of the `.app` bundle, via the native channel);
/// null elsewhere or when the lookup fails, and the button falls back to a
/// generic glyph. Kept alive: the icon doesn't change while the app runs.

final class EditorIconProvider
    extends
        $FunctionalProvider<
          AsyncValue<Uint8List?>,
          Uint8List?,
          FutureOr<Uint8List?>
        >
    with $FutureModifier<Uint8List?>, $FutureProvider<Uint8List?> {
  /// The app icon of a "Send to" editor as PNG bytes, for the toolbar button.
  /// macOS only (the Finder icon of the `.app` bundle, via the native channel);
  /// null elsewhere or when the lookup fails, and the button falls back to a
  /// generic glyph. Kept alive: the icon doesn't change while the app runs.
  EditorIconProvider._({
    required EditorIconFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'editorIconProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$editorIconHash();

  @override
  String toString() {
    return r'editorIconProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Uint8List?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Uint8List?> create(Ref ref) {
    final argument = this.argument as String;
    return editorIcon(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is EditorIconProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$editorIconHash() => r'8c7a7787ecd372a9e9f746002557f3abac18db1a';

/// The app icon of a "Send to" editor as PNG bytes, for the toolbar button.
/// macOS only (the Finder icon of the `.app` bundle, via the native channel);
/// null elsewhere or when the lookup fails, and the button falls back to a
/// generic glyph. Kept alive: the icon doesn't change while the app runs.

final class EditorIconFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Uint8List?>, String> {
  EditorIconFamily._()
    : super(
        retry: null,
        name: r'editorIconProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// The app icon of a "Send to" editor as PNG bytes, for the toolbar button.
  /// macOS only (the Finder icon of the `.app` bundle, via the native channel);
  /// null elsewhere or when the lookup fails, and the button falls back to a
  /// generic glyph. Kept alive: the icon doesn't change while the app runs.

  EditorIconProvider call(String appPath) =>
      EditorIconProvider._(argument: appPath, from: this);

  @override
  String toString() => r'editorIconProvider';
}

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
