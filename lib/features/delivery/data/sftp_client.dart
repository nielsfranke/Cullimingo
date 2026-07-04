import 'dart:io';

import 'package:cullimingo/features/delivery/data/delivery_client.dart';
import 'package:dartssh2/dartssh2.dart';

/// SFTP delivery via dartssh2 (pure Dart; the dependency Niels OK'd for the
/// FTP target, `BUILD_PLAN.md` §11). Password auth by default; a per-server
/// private-key PEM ([keyFilePath]) switches to key auth, with [password] as
/// the key's passphrase.
class SftpDeliveryClient implements DeliveryClient {
  /// Creates a client; nothing happens until [connect].
  SftpDeliveryClient({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.keyFilePath = '',
    this.timeout = const Duration(seconds: 20),
  });

  /// Server hostname or IP.
  final String host;

  /// SSH port (conventionally 22).
  final int port;

  /// Login name.
  final String username;

  /// Login password — or, when [keyFilePath] is set, the key's passphrase
  /// ('' for an unencrypted key).
  final String password;

  /// Path of a private-key PEM file for key-based auth ('' = password auth).
  final String keyFilePath;

  /// Applied to connect and authentication waits.
  final Duration timeout;

  SSHClient? _ssh;
  SftpClient? _sftp;
  String _remoteDir = '.';

  @override
  Future<void> connect() async {
    List<SSHKeyPair>? identities;
    if (keyFilePath.isNotEmpty) {
      try {
        identities = SSHKeyPair.fromPem(
          File(keyFilePath).readAsStringSync(),
          password.isEmpty ? null : password,
        );
      } on Object catch (e) {
        throw DeliveryException('Could not read the key "$keyFilePath" — $e');
      }
    }
    try {
      final socket = await SSHSocket.connect(host, port, timeout: timeout);
      final ssh = SSHClient(
        socket,
        username: username,
        identities: identities,
        onPasswordRequest: identities == null ? () => password : null,
      );
      _ssh = ssh;
      await ssh.authenticated.timeout(timeout);
      _sftp = await ssh.sftp();
    } on SSHAuthFailError {
      throw DeliveryException('$host refused the login for "$username"');
    } on DeliveryException {
      rethrow;
    } on Object catch (e) {
      throw DeliveryException('Could not connect to $host:$port — $e');
    }
  }

  @override
  Future<void> ensureRemoteDir(String remoteDir) async {
    final sftp = _requireSftp();
    final parts = <String>[];
    for (final segment in remoteDir.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      parts.add(segment);
      final path = './${parts.join('/')}';
      try {
        await sftp.mkdir(path);
      } on SftpStatusError {
        // Already exists (or truly un-creatable — then the stat below throws).
      }
      try {
        await sftp.stat(path);
      } on Object {
        throw DeliveryException('Could not create "$path" on $host');
      }
    }
    _remoteDir = parts.isEmpty ? '.' : './${parts.join('/')}';
  }

  @override
  Future<void> uploadFile(String localPath, String remoteName) async {
    final sftp = _requireSftp();
    try {
      final file = await sftp.open(
        '$_remoteDir/$remoteName',
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );
      try {
        await file.write(File(localPath).openRead().cast());
      } finally {
        await file.close();
      }
    } on DeliveryException {
      rethrow;
    } on Object catch (e) {
      throw DeliveryException('Upload of "$remoteName" to $host failed — $e');
    }
  }

  @override
  Future<void> close() async {
    try {
      _sftp?.close();
      _ssh?.close();
    } on Object {
      // Best effort — we're tearing down anyway.
    }
    _sftp = null;
    _ssh = null;
  }

  SftpClient _requireSftp() {
    final sftp = _sftp;
    if (sftp == null) throw const DeliveryException('Not connected');
    return sftp;
  }
}
