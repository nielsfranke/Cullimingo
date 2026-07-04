import 'dart:io';

import 'package:cullimingo/features/delivery/data/ftp_client.dart';
import 'package:cullimingo/features/delivery/data/sftp_client.dart';
import 'package:cullimingo/features/delivery/domain/delivery_server.dart';

/// Base class for everything that can go wrong while delivering files; the
/// export UI shows [message] verbatim. `FtpException` extends it with the
/// server reply.
class DeliveryException implements Exception {
  /// Creates an exception with a human-readable [message].
  const DeliveryException(this.message);

  /// What went wrong, phrased for the error UI.
  final String message;

  @override
  String toString() => 'DeliveryException: $message';
}

/// One connection to a delivery server, protocol-agnostic: the export upload
/// path only ever talks to this (`BUILD_PLAN.md` §11). Implementations:
/// [FtpClient] (FTP/FTPS) and [SftpDeliveryClient].
abstract interface class DeliveryClient {
  /// Connects and authenticates. Throws [DeliveryException] on refusal.
  Future<void> connect();

  /// Changes into [remoteDir] (relative to the login root), creating missing
  /// components; subsequent uploads land there. Empty = login root.
  Future<void> ensureRemoteDir(String remoteDir);

  /// Uploads the file at [localPath] as [remoteName] in the remote directory.
  Future<void> uploadFile(String localPath, String remoteName);

  /// Tears the connection down (never throws).
  Future<void> close();
}

/// Builds the right client for [server], with the password fetched from the
/// secret store by the caller. [onBadCertificate] is a test hook for the
/// FTPS path's self-signed fixture cert; production callers leave it null.
DeliveryClient createDeliveryClient(
  DeliveryServer server,
  String password, {
  Duration timeout = const Duration(seconds: 20),
  bool Function(X509Certificate certificate)? onBadCertificate,
}) => switch (server.protocol) {
  DeliveryProtocol.ftp || DeliveryProtocol.ftps => FtpClient(
    host: server.host,
    port: server.port,
    username: server.username,
    password: password,
    secure: server.protocol == DeliveryProtocol.ftps,
    timeout: timeout,
    onBadCertificate:
        onBadCertificate ??
        // Per-server opt-in for the self-signed certs agency endpoints love.
        (server.allowSelfSigned ? (_) => true : null),
  ),
  DeliveryProtocol.sftp => SftpDeliveryClient(
    host: server.host,
    port: server.port,
    username: server.username,
    password: password,
    keyFilePath: server.keyFilePath,
    timeout: timeout,
  ),
};

/// Connects, changes into the server's remote dir and disconnects — the
/// Settings "Test connection" button. Returns null on success, otherwise the
/// message to show.
Future<String?> testDeliveryConnection(
  DeliveryClient client,
  String remoteDir,
) async {
  try {
    await client.connect();
    await client.ensureRemoteDir(remoteDir);
    return null;
  } on DeliveryException catch (e) {
    return e.message;
  } on Object catch (e) {
    return '$e';
  } finally {
    await client.close();
  }
}
