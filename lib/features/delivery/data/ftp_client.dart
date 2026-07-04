import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:cullimingo/features/delivery/data/delivery_client.dart';
import 'package:flutter/foundation.dart';

/// One FTP server reply: the 3-digit [code] plus the (possibly multiline,
/// joined) [text].
class FtpReply {
  /// Creates a reply.
  const FtpReply(this.code, this.text);

  /// The 3-digit reply code (RFC 959 §4.2).
  final int code;

  /// The human-readable part of the reply.
  final String text;

  @override
  String toString() => '$code $text';
}

/// Thrown when the server refuses a command, the reply is malformed, or the
/// connection breaks. [reply] carries the server's answer when there was one.
class FtpException extends DeliveryException {
  /// Creates an exception with a human-readable [message].
  const FtpException(super.message, [this.reply]);

  /// The offending server reply, if the server answered at all.
  final FtpReply? reply;

  @override
  String toString() => reply == null
      ? 'FtpException: $message'
      : 'FtpException: $message '
            '($reply)';
}

/// A minimal FTP / explicit-FTPS client — just enough protocol to deliver
/// exports to a wire/agency server (`BUILD_PLAN.md` §11): login, `TYPE I`,
/// `CWD`/`MKD`, passive-mode `STOR`, `QUIT`. Written on plain `dart:io`
/// sockets so we don't depend on the half-maintained FTP packages.
///
/// With [secure] the control channel is upgraded via `AUTH TLS` and the data
/// channel protected with `PROT P` (FTPES). Known limitation: `dart:io` can't
/// resume the control channel's TLS session on the data connection, which
/// servers configured with "require TLS session reuse" (e.g. vsftpd's
/// `require_ssl_reuse=YES`) reject — those need that switch off, or SFTP.
///
/// Not safe for concurrent commands; callers run one transfer at a time.
class FtpClient implements DeliveryClient {
  /// Creates a client; nothing happens until [connect].
  FtpClient({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.secure = false,
    this.timeout = const Duration(seconds: 20),
    this.onBadCertificate,
  });

  /// Server hostname or IP.
  final String host;

  /// Control-connection port (conventionally 21).
  final int port;

  /// Login name; empty logs in as `anonymous`.
  final String username;

  /// Login password.
  final String password;

  /// Upgrade to explicit TLS (FTPES) right after the greeting.
  final bool secure;

  /// Applied to every network wait (connect, reply, handshake).
  final Duration timeout;

  /// Test hook: accept the fake server's self-signed certificate. Production
  /// connections leave this null (strict verification).
  final bool Function(X509Certificate certificate)? onBadCertificate;

  Socket? _socket;
  StreamSubscription<Uint8List>? _subscription;
  final List<int> _pending = [];
  final Queue<String> _lines = Queue<String>();
  Completer<void>? _wakeup;
  bool _closed = false;
  Object? _socketError;

  /// Connects, upgrades to TLS when [secure], logs in and selects binary mode.
  /// Throws [FtpException] when any step is refused.
  @override
  Future<void> connect() async {
    final Socket socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
    } on Object catch (e) {
      throw FtpException('Could not connect to $host:$port — $e');
    }
    _attach(socket);
    _expect(await _readReply(), const {220}, 'greeting');

    if (secure) {
      _expect(await _command('AUTH TLS'), const {234}, 'AUTH TLS');
      // dart:io contract: pause the old subscription, then hand the socket to
      // SecureSocket.secure; it takes the connection over.
      _subscription!.pause();
      final SecureSocket tls;
      try {
        tls = await SecureSocket.secure(
          socket,
          host: host,
          onBadCertificate: onBadCertificate,
        ).timeout(timeout);
      } on Object catch (e) {
        throw FtpException('TLS handshake with $host failed — $e');
      }
      _pending.clear();
      _lines.clear();
      _attach(tls);
      _expect(await _command('PBSZ 0'), const {200}, 'PBSZ');
      _expect(await _command('PROT P'), const {200}, 'PROT P');
    }

    final user = await _command(
      'USER ${username.isEmpty ? 'anonymous' : username}',
    );
    if (user.code == 331 || user.code == 332) {
      _expect(await _command('PASS $password'), const {230, 202}, 'login');
    } else {
      _expect(user, const {230}, 'login');
    }
    _expect(await _command('TYPE I'), const {200}, 'TYPE I');
  }

  /// Changes into [remoteDir] (relative to the login root), creating missing
  /// components. Empty [remoteDir] is a no-op. Subsequent uploads land here.
  @override
  Future<void> ensureRemoteDir(String remoteDir) async {
    final segments = remoteDir
        .split('/')
        .where((s) => s.isNotEmpty && s != '.');
    for (final segment in segments) {
      final cwd = await _command('CWD $segment');
      if (cwd.code == 250) continue;
      final mkd = await _command('MKD $segment');
      if (mkd.code != 257) {
        throw FtpException('Could not create "$segment" on $host', mkd);
      }
      _expect(await _command('CWD $segment'), const {250}, 'CWD $segment');
    }
  }

  /// Uploads [bytes] as [remoteName] in the current remote directory over a
  /// passive-mode data connection.
  Future<void> upload(Stream<List<int>> bytes, String remoteName) async {
    var data = await _openDataConnection();
    try {
      final stor = await _command('STOR $remoteName');
      if (stor.code != 150 && stor.code != 125) {
        throw FtpException('Server refused upload of "$remoteName"', stor);
      }
      if (secure) {
        // PROT P: the data channel gets its own TLS handshake (after STOR is
        // accepted, matching FileZilla's order).
        data = await SecureSocket.secure(
          data,
          host: host,
          onBadCertificate: onBadCertificate,
        ).timeout(timeout);
      }
      await data.addStream(bytes);
      await data.flush();
      await data.close();
      _expect(await _readReply(), const {226, 250}, 'transfer of $remoteName');
    } finally {
      data.destroy();
    }
  }

  /// Uploads the file at [localPath] as [remoteName].
  @override
  Future<void> uploadFile(String localPath, String remoteName) =>
      upload(File(localPath).openRead(), remoteName);

  /// Sends `QUIT` (best effort) and tears the connection down.
  @override
  Future<void> close() async {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.write('QUIT\r\n');
      await _readReply().timeout(const Duration(seconds: 2));
    } on Object {
      // The server hanging up first is fine — we're leaving anyway.
    }
    await _subscription?.cancel();
    socket.destroy();
    _socket = null;
  }

  /// Enters passive mode (`EPSV`, falling back to `PASV`) and opens the data
  /// connection. Always connects to [host] — the address in a PASV reply is
  /// routinely wrong behind NAT.
  Future<Socket> _openDataConnection() async {
    int? dataPort;
    final epsv = await _command('EPSV');
    if (epsv.code == 229) {
      final match = RegExp(r'\((.)\1\1(\d+)\1\)').firstMatch(epsv.text);
      dataPort = match == null ? null : int.tryParse(match.group(2)!);
    } else {
      final pasv = await _command('PASV');
      _expect(pasv, const {227}, 'PASV');
      final match = RegExp(
        r'(\d+),(\d+),(\d+),(\d+),(\d+),(\d+)',
      ).firstMatch(pasv.text);
      if (match != null) {
        dataPort =
            int.parse(match.group(5)!) * 256 + int.parse(match.group(6)!);
      }
    }
    if (dataPort == null) {
      throw FtpException('Could not parse the passive-mode reply from $host');
    }
    try {
      return await Socket.connect(host, dataPort, timeout: timeout);
    } on Object catch (e) {
      throw FtpException('Data connection to $host:$dataPort failed — $e');
    }
  }

  /// Sends [command] and returns the reply.
  Future<FtpReply> _command(String command) {
    final socket = _socket;
    if (socket == null) throw const FtpException('Not connected');
    socket.write('$command\r\n');
    return _readReply();
  }

  void _expect(FtpReply reply, Set<int> allowed, String step) {
    if (!allowed.contains(reply.code)) {
      throw FtpException('$host refused $step', reply);
    }
  }

  /// Reads one full reply, following multiline replies (`123-…` … `123 …`).
  Future<FtpReply> _readReply() async {
    final first = await _readLine();
    final code = first.length >= 3 ? int.tryParse(first.substring(0, 3)) : null;
    if (code == null) {
      throw FtpException('Malformed reply from $host: "$first"');
    }
    final text = StringBuffer(first.length > 4 ? first.substring(4) : '');
    if (first.length > 3 && first[3] == '-') {
      while (true) {
        final line = await _readLine();
        if (line.startsWith('$code ')) {
          text.write('\n${line.substring(4)}');
          break;
        }
        text.write('\n$line');
      }
    }
    return FtpReply(code, text.toString());
  }

  Future<String> _readLine() async {
    while (_lines.isEmpty) {
      final error = _socketError;
      if (error != null) throw FtpException('Connection to $host — $error');
      if (_closed) throw FtpException('$host closed the connection');
      final wakeup = _wakeup = Completer<void>();
      try {
        await wakeup.future.timeout(timeout);
      } on TimeoutException {
        throw FtpException('$host did not answer within ${timeout.inSeconds}s');
      }
    }
    return _lines.removeFirst();
  }

  /// (Re-)attaches the reply reader — once on connect, again after the TLS
  /// upgrade hands us a new socket.
  void _attach(Socket socket) {
    _socket = socket;
    _closed = false;
    _subscription = socket.listen(
      _onBytes,
      onDone: () {
        _closed = true;
        _wake();
      },
      onError: (Object e) {
        _socketError = e;
        _wake();
      },
    );
  }

  void _onBytes(Uint8List bytes) {
    _pending.addAll(bytes);
    while (true) {
      final newline = _pending.indexOf(10);
      if (newline < 0) break;
      var end = newline;
      if (end > 0 && _pending[end - 1] == 13) end--;
      _lines.add(utf8.decode(_pending.sublist(0, end), allowMalformed: true));
      _pending.removeRange(0, newline + 1);
    }
    _wake();
  }

  void _wake() {
    final wakeup = _wakeup;
    _wakeup = null;
    if (wakeup != null && !wakeup.isCompleted) wakeup.complete();
  }
}
