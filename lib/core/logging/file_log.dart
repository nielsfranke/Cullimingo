import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:talker_flutter/talker_flutter.dart';

/// Default size at which [FileLog] starts a new file (the previous one is
/// kept as `cullimingo.1.log`).
const int kLogFileMaxBytes = 2 * 1024 * 1024;

/// Mirrors every [Talker] entry into `<dir>/cullimingo.log`, so a problem can
/// be read after the fact — the in-app viewer only holds this session, and a
/// failure the UI swallowed (the Windows spike's silent trash fallback) left
/// no trace anywhere. Plain text, one entry per block, appended through an
/// async `IOSink` so the UI isolate never waits on disk. When the file passes
/// `maxBytes` it becomes `cullimingo.1.log` (replacing an older one) and a
/// fresh file starts: at most two files, about 2 × `maxBytes` on disk.
class FileLog {
  FileLog._(this.file, this._maxBytes, this._sink, this._bytes);

  /// The current log file.
  final File file;

  final int _maxBytes;
  IOSink _sink;
  int _bytes;
  StreamSubscription<TalkerData>? _subscription;
  Future<void> _queue = Future<void>.value();

  /// Starts mirroring [talker] into [dir] (created if needed), opening with a
  /// session header. Null when the folder can't be written — logging to a
  /// file is best effort and never stops the app.
  static Future<FileLog?> start(
    Talker talker, {
    required Directory dir,
    String header = '',
    int maxBytes = kLogFileMaxBytes,
  }) async {
    try {
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'cullimingo.log'));
      // ignore: avoid_slow_async_io — once per start.
      if (await file.exists() && await file.length() >= maxBytes) {
        await _rotate(file);
      }
      // ignore: avoid_slow_async_io — once per start.
      final existing = await file.exists() ? await file.length() : 0;
      final log = FileLog._(
        file,
        maxBytes,
        file.openWrite(mode: FileMode.append),
        existing,
      );
      const line = TimeFormat.yearMonthDayAndTime;
      log
        .._write(
          '==== ${DateTime.now().toIso8601String()} '
          '${header.isEmpty ? '' : '$header '}====\n',
        )
        .._subscription = talker.stream.listen(
          (data) =>
              log._write('${data.generateTextMessage(timeFormat: line)}\n'),
        );
      return log;
    } on Object {
      return null;
    }
  }

  void _write(String text) {
    _queue = _queue.then((_) async {
      try {
        _sink.write(text);
        _bytes += text.length;
        if (_bytes >= _maxBytes) {
          await _sink.close();
          await _rotate(file);
          _sink = file.openWrite(mode: FileMode.append);
          _bytes = 0;
        }
      } on Object {
        // Best effort: a full disk must not take logging (or the app) down.
      }
    });
  }

  /// Waits until everything logged so far is on disk.
  Future<void> flush() => _queue = _queue.then((_) => _sink.flush());

  /// Stops mirroring and closes the file.
  Future<void> close() async {
    await _subscription?.cancel();
    await flush();
    await _sink.close();
  }

  static Future<void> _rotate(File file) async {
    final old = File(p.join(p.dirname(file.path), 'cullimingo.1.log'));
    // ignore: avoid_slow_async_io — only on rotation.
    if (await old.exists()) await old.delete();
    await file.rename(old.path);
  }
}
