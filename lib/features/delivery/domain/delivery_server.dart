import 'dart:math';

import 'package:flutter/foundation.dart';

/// Wire protocol a [DeliveryServer] speaks (`BUILD_PLAN.md` §11 — the
/// first-class FTP target).
enum DeliveryProtocol {
  /// Plain FTP (RFC 959). Credentials travel unencrypted — fine on a LAN or
  /// VPN, discouraged on the open internet.
  ftp,

  /// Explicit FTP over TLS (FTPES): plain connect, then `AUTH TLS` upgrades
  /// the control channel and `PROT P` the data channel.
  ftps,

  /// SFTP (file transfer over SSH).
  sftp;

  /// The conventional port when the user leaves the field empty.
  int get defaultPort => switch (this) {
    DeliveryProtocol.ftp || DeliveryProtocol.ftps => 21,
    DeliveryProtocol.sftp => 22,
  };

  /// Short label for dropdowns.
  String get label => switch (this) {
    DeliveryProtocol.ftp => 'FTP',
    DeliveryProtocol.ftps => 'FTPS (explicit TLS)',
    DeliveryProtocol.sftp => 'SFTP',
  };

  /// Parses a persisted [name], or null when unknown (forward compat).
  static DeliveryProtocol? fromName(String? name) {
    for (final p in values) {
      if (p.name == name) return p;
    }
    return null;
  }
}

/// A user-configured upload destination for exports — an agency/wire FTP(S) or
/// SFTP endpoint (`BUILD_PLAN.md` §11). The password is deliberately **not**
/// part of this object: it lives in the platform secret store (Keychain /
/// libsecret), keyed by [id], so `settings.json` never holds credentials.
@immutable
class DeliveryServer {
  /// Creates a server entry.
  const DeliveryServer({
    required this.id,
    required this.name,
    required this.protocol,
    required this.host,
    required this.port,
    required this.username,
    this.remoteDir = '',
    this.allowSelfSigned = false,
    this.keyFilePath = '',
  });

  /// Stable identity — survives renames so the stored password stays attached.
  final String id;

  /// Display name shown in the export dialog (e.g. "AP wire").
  final String name;

  /// How to talk to [host].
  final DeliveryProtocol protocol;

  /// Hostname or IP address.
  final String host;

  /// TCP port (pre-filled with [DeliveryProtocol.defaultPort] in the UI).
  final int port;

  /// Login name. Empty means anonymous (FTP only).
  final String username;

  /// Directory to upload into, relative to the login root ('' = login root).
  /// Missing components are created on upload.
  final String remoteDir;

  /// FTPS only: accept the server's certificate even when it doesn't verify
  /// (self-signed — common on agency endpoints). Off by default.
  final bool allowSelfSigned;

  /// SFTP only: path of a private-key PEM file for key-based auth ('' =
  /// password auth). When set, the stored password is used as the key's
  /// passphrase (leave it empty for an unencrypted key).
  final String keyFilePath;

  /// Generates a new stable id (time + randomness; no dependency needed).
  static String newId() {
    final rand = Random().nextInt(0xFFFFFF);
    final time = DateTime.now().microsecondsSinceEpoch;
    return '${time.toRadixString(36)}-${rand.toRadixString(36)}';
  }

  /// Parses a persisted map, or null when it's malformed (so a hand-edited
  /// settings file can't crash the list).
  static DeliveryServer? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final protocol = DeliveryProtocol.fromName(json['protocol'] as String?);
    final host = json['host'];
    final port = json['port'];
    final username = json['username'];
    final remoteDir = json['remoteDir'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        protocol == null ||
        host is! String ||
        host.isEmpty ||
        port is! num ||
        username is! String) {
      return null;
    }
    return DeliveryServer(
      id: id,
      name: name,
      protocol: protocol,
      host: host,
      port: port.toInt(),
      username: username,
      remoteDir: remoteDir is String ? remoteDir : '',
      allowSelfSigned: json['allowSelfSigned'] == true,
      keyFilePath: json['keyFilePath'] is String
          ? json['keyFilePath'] as String
          : '',
    );
  }

  /// The persisted form.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'protocol': protocol.name,
    'host': host,
    'port': port,
    'username': username,
    'remoteDir': remoteDir,
    'allowSelfSigned': allowSelfSigned,
    'keyFilePath': keyFilePath,
  };

  /// Returns a copy with the given fields replaced ([id] is immutable).
  DeliveryServer copyWith({
    String? name,
    DeliveryProtocol? protocol,
    String? host,
    int? port,
    String? username,
    String? remoteDir,
    bool? allowSelfSigned,
    String? keyFilePath,
  }) => DeliveryServer(
    id: id,
    name: name ?? this.name,
    protocol: protocol ?? this.protocol,
    host: host ?? this.host,
    port: port ?? this.port,
    username: username ?? this.username,
    remoteDir: remoteDir ?? this.remoteDir,
    allowSelfSigned: allowSelfSigned ?? this.allowSelfSigned,
    keyFilePath: keyFilePath ?? this.keyFilePath,
  );

  @override
  bool operator ==(Object other) =>
      other is DeliveryServer &&
      other.id == id &&
      other.name == name &&
      other.protocol == protocol &&
      other.host == host &&
      other.port == port &&
      other.username == username &&
      other.remoteDir == remoteDir &&
      other.allowSelfSigned == allowSelfSigned &&
      other.keyFilePath == keyFilePath;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    protocol,
    host,
    port,
    username,
    remoteDir,
    allowSelfSigned,
    keyFilePath,
  );
}
