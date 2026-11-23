import 'dart:convert';

import 'package:pinenacl/ed25519.dart';

/// The public half of Cullimingo's Ed25519 update key (raw 32 bytes, base64).
/// The private half is the release workflow's `UPDATE_SIGNING_KEY` secret;
/// `tool/update_manifest.py` signs each release's packages with it. Not code
/// signing — the downloads stay unsigned for the OS — but the app installs
/// nothing it can't verify against this key.
const String kUpdatePublicKey = 'Yom+2KAvbbdOUnrsF9cJNcEcHQGKcnBGx7fcsmx0mxk=';

/// The statement one package signature covers (keep in sync with
/// `tool/update_manifest.py`): binding the signature to the version, the
/// package kind and the file means a signed package can't be replayed as an
/// older version or as another platform's download.
String updateStatement({
  required String version,
  required String key,
  required String name,
  required String sha256,
}) => 'cullimingo-update-v1\n$version\n$key\n$name\n$sha256\n';

/// Whether [signature] (base64) is [publicKey]'s Ed25519 signature over
/// [statement]. Never throws.
bool verifyUpdateSignature({
  required String statement,
  required String signature,
  String publicKey = kUpdatePublicKey,
}) {
  try {
    return VerifyKey(Uint8List.fromList(base64.decode(publicKey))).verify(
      signature: Signature(Uint8List.fromList(base64.decode(signature))),
      message: Uint8List.fromList(utf8.encode(statement)),
    );
  } on Object {
    return false;
  }
}

/// One downloadable package of a release, as `latest.json` lists it.
class UpdatePackage {
  /// Creates a package entry.
  const UpdatePackage({
    required this.key,
    required this.name,
    required this.size,
    required this.sha256,
    required this.url,
    required this.signature,
  });

  /// The package kind (`windows-x64-nsis`, `macos-arm64-dmg`, …).
  final String key;

  /// The release asset's file name.
  final String name;

  /// Its size in bytes.
  final int size;

  /// Its SHA-256, lower-case hex.
  final String sha256;

  /// Where to download it.
  final Uri url;

  /// The Ed25519 signature over [updateStatement], base64.
  final String signature;
}

/// A release's `latest.json`: its version and the self-updatable packages.
class UpdateManifest {
  /// Creates a manifest.
  const UpdateManifest({required this.version, required this.packages});

  /// Parses `latest.json`; throws [FormatException] on anything unexpected.
  /// Package URLs must be https ([allowHttp] is for a local test server).
  factory UpdateManifest.parse(String json, {bool allowHttp = false}) {
    final Object? data = jsonDecode(json);
    if (data is! Map<String, dynamic> ||
        data['format'] != 1 ||
        data['version'] is! String ||
        data['packages'] is! Map<String, dynamic>) {
      throw const FormatException('not a Cullimingo update manifest');
    }
    final packages = <String, UpdatePackage>{};
    for (final MapEntry(:key, :value)
        in (data['packages'] as Map<String, dynamic>).entries) {
      if (value is! Map<String, dynamic>) continue;
      final url = Uri.tryParse(value['url'] as String? ?? '');
      if (url == null ||
          !(url.scheme == 'https' || (allowHttp && url.scheme == 'http')) ||
          value['name'] is! String ||
          value['size'] is! int ||
          value['sha256'] is! String ||
          value['signature'] is! String) {
        continue;
      }
      packages[key] = UpdatePackage(
        key: key,
        name: value['name'] as String,
        size: value['size'] as int,
        sha256: value['sha256'] as String,
        url: url,
        signature: value['signature'] as String,
      );
    }
    return UpdateManifest(
      version: data['version'] as String,
      packages: packages,
    );
  }

  /// The release's version (`1.14.0`).
  final String version;

  /// Packages by key.
  final Map<String, UpdatePackage> packages;

  /// Whether [package]'s signature is valid for this manifest's version.
  bool verifies(UpdatePackage package, {String publicKey = kUpdatePublicKey}) =>
      verifyUpdateSignature(
        statement: updateStatement(
          version: version,
          key: package.key,
          name: package.name,
          sha256: package.sha256,
        ),
        signature: package.signature,
        publicKey: publicKey,
      );
}
