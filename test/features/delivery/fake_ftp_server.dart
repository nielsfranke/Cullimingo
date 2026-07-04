import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A loopback FTP server speaking just enough protocol to exercise
/// `FtpClient`: login, optional explicit TLS (`AUTH TLS` + `PROT P`), `CWD`/
/// `MKD`, `EPSV`/`PASV` and `STOR`. Uploads land in [uploads] (keyed by
/// `cwd/name`), every received command line in [log].
class FakeFtpServer {
  /// Creates a server; call [start] to bind it.
  FakeFtpServer({
    this.password = 'secret',
    this.tlsContext,
    this.supportsEpsv = true,
  });

  /// The password `PASS` must match (any username is accepted).
  final String password;

  /// When set, `AUTH TLS` is offered and the control/data channels upgrade
  /// with this context; when null, `AUTH TLS` is refused.
  final SecurityContext? tlsContext;

  /// Whether `EPSV` is answered (off exercises the `PASV` fallback).
  final bool supportsEpsv;

  /// Uploaded files: absolute remote path → bytes.
  final Map<String, List<int>> uploads = {};

  /// Directories that exist (as absolute paths); `MKD` adds to it.
  final Set<String> dirs = {'/'};

  /// Every command line the server received, in order.
  final List<String> log = [];

  /// When > 0, the next `STOR` is refused with 550 (and this decremented) —
  /// for retry tests.
  int storFailuresRemaining = 0;

  late ServerSocket _server;
  final List<ServerSocket> _dataServers = [];

  /// The bound control port.
  int get port => _server.port;

  /// Binds to an ephemeral loopback port and serves connections until [stop].
  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((socket) {
      unawaited(_serve(socket));
    });
  }

  /// Stops listening and closes any pending data listeners.
  Future<void> stop() async {
    await _server.close();
    for (final s in _dataServers) {
      await s.close();
    }
  }

  Future<void> _serve(Socket control) async {
    var socket = control;
    var lines = _LineReader(socket);
    var authenticated = false;
    var protected = false;
    var cwd = '/';
    Future<Socket>? pendingData;

    socket.write('220 FakeFtpServer ready\r\n');
    try {
      while (true) {
        final line = await lines.next();
        if (line == null) return;
        log.add(line);
        final space = line.indexOf(' ');
        final cmd = (space < 0 ? line : line.substring(0, space)).toUpperCase();
        final arg = space < 0 ? '' : line.substring(space + 1);

        switch (cmd) {
          case 'AUTH':
            if (tlsContext == null || arg.toUpperCase() != 'TLS') {
              socket.write('534 TLS not available\r\n');
            } else {
              // Pause BEFORE replying: once the client sees 234 its
              // ClientHello races in, and it must reach the TLS handshake,
              // not this line reader.
              lines.pause();
              socket.write('234 proceed\r\n');
              await socket.flush();
              socket = await SecureSocket.secureServer(socket, tlsContext);
              lines = _LineReader(socket);
            }
          case 'PBSZ':
            socket.write('200 PBSZ=0\r\n');
          case 'PROT':
            protected = arg.toUpperCase() == 'P';
            socket.write('200 protection level set\r\n');
          case 'USER':
            socket.write('331 need password\r\n');
          case 'PASS':
            authenticated = arg == password;
            socket.write(
              authenticated ? '230 logged in\r\n' : '530 login incorrect\r\n',
            );
          case 'TYPE':
            socket.write('200 binary\r\n');
          case 'CWD':
            final target = _resolve(cwd, arg);
            if (dirs.contains(target)) {
              cwd = target;
              socket.write('250 CWD ok\r\n');
            } else {
              socket.write('550 no such directory\r\n');
            }
          case 'MKD':
            dirs.add(_resolve(cwd, arg));
            socket.write('257 created\r\n');
          case 'EPSV':
            if (!supportsEpsv) {
              socket.write('502 EPSV not implemented\r\n');
            } else {
              final data = await _bindDataServer();
              pendingData = data.first;
              socket.write(
                '229 Entering Extended Passive Mode (|||${data.port}|)\r\n',
              );
            }
          case 'PASV':
            final data = await _bindDataServer();
            pendingData = data.first;
            final p1 = data.port ~/ 256;
            final p2 = data.port % 256;
            socket.write('227 Entering Passive Mode (127,0,0,1,$p1,$p2)\r\n');
          case 'STOR':
            if (!authenticated) {
              socket.write('530 not logged in\r\n');
            } else if (storFailuresRemaining > 0) {
              storFailuresRemaining--;
              socket.write('550 transient failure, try again\r\n');
            } else if (pendingData == null) {
              socket.write('425 use PASV first\r\n');
            } else {
              socket.write('150 send it\r\n');
              await socket.flush();
              var data = await pendingData;
              pendingData = null;
              if (protected) {
                data = await SecureSocket.secureServer(data, tlsContext);
              }
              final bytes = <int>[];
              await data.forEach(bytes.addAll);
              data.destroy();
              uploads[_resolve(cwd, arg)] = bytes;
              socket.write('226 stored\r\n');
            }
          case 'QUIT':
            socket.write('221 bye\r\n');
            await socket.flush();
            socket.destroy();
            return;
          default:
            socket.write('502 not implemented\r\n');
        }
      }
    } on Object {
      socket.destroy();
    }
  }

  Future<ServerSocket> _bindDataServer() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _dataServers.add(server);
    return server;
  }

  static String _resolve(String cwd, String arg) =>
      arg.startsWith('/') ? arg : (cwd == '/' ? '/$arg' : '$cwd/$arg');
}

/// Splits a socket's byte stream into CRLF lines; [next] returns null on EOF.
/// [pause] detaches it before a TLS upgrade takes the socket over.
class _LineReader {
  _LineReader(Socket socket) {
    _subscription = socket.listen(
      (bytes) {
        _buffer.addAll(bytes);
        _drain();
      },
      onDone: () {
        _done = true;
        _drain();
      },
      onError: (Object _) {
        _done = true;
        _drain();
      },
    );
  }

  late final StreamSubscription<List<int>> _subscription;
  final List<int> _buffer = [];
  final List<String> _lines = [];
  final List<Completer<String?>> _waiters = [];
  bool _done = false;

  void pause() => _subscription.pause();

  Future<String?> next() {
    final completer = Completer<String?>();
    _waiters.add(completer);
    _drain();
    return completer.future;
  }

  void _drain() {
    while (true) {
      final newline = _buffer.indexOf(10);
      if (newline < 0) break;
      var end = newline;
      if (end > 0 && _buffer[end - 1] == 13) end--;
      _lines.add(utf8.decode(_buffer.sublist(0, end)));
      _buffer.removeRange(0, newline + 1);
    }
    while (_waiters.isNotEmpty && (_lines.isNotEmpty || _done)) {
      _waiters
          .removeAt(0)
          .complete(_lines.isNotEmpty ? _lines.removeAt(0) : null);
    }
  }
}
