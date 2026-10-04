import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

// Small libc bindings the copy pipeline needs and `dart:io` doesn't offer:
// publishing a file under a name *without ever replacing* one that exists, and
// asking which volume a path lives on and how much room it has. Only stable,
// pointer-and-int ABIs are used; the two structs read here are laid out for
// 64-bit glibc (statvfs) and 64-bit macOS (statfs, 64-bit-inode variant) —
// the only targets Cullimingo ships. Blocking calls: run them off the UI
// isolate.

/// What happened when [publishNoReplace] tried to give a file its final name.
enum PublishOutcome {
  /// The file now lives under the destination name.
  published,

  /// Something already exists at the destination name (a file, a directory, a
  /// dangling symlink, …) and was left exactly as it was.
  taken,
}

typedef _LinkD = int Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _RenameAt2D = int Function(int, Pointer<Utf8>, int, Pointer<Utf8>, int);
typedef _RenamexNpD = int Function(Pointer<Utf8>, Pointer<Utf8>, int);
typedef _StatN = Int32 Function(Pointer<Utf8>, Pointer<Uint8>);
typedef _StatD = int Function(Pointer<Utf8>, Pointer<Uint8>);

final DynamicLibrary _libc = DynamicLibrary.process();

final _LinkD _link = _libc
    .lookupFunction<Int32 Function(Pointer<Utf8>, Pointer<Utf8>), _LinkD>(
      'link',
    );

// Linux: renameat2(AT_FDCWD, old, AT_FDCWD, new, RENAME_NOREPLACE), glibc ≥
// 2.28. macOS: renamex_np(old, new, RENAME_EXCL). Either may be missing or
// refused by the filesystem — then we fall back further (see below).
const int _atFdCwd = -100;
const int _renameNoReplace = 1;
const int _renameExcl = 0x4;

final _RenameAt2D? _renameAt2 =
    Platform.isLinux && _libc.providesSymbol('renameat2')
    ? _libc.lookupFunction<
        Int32 Function(Int32, Pointer<Utf8>, Int32, Pointer<Utf8>, Uint32),
        _RenameAt2D
      >('renameat2')
    : null;

final _RenamexNpD? _renamexNp =
    Platform.isMacOS && _libc.providesSymbol('renamex_np')
    ? _libc.lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Uint32),
        _RenamexNpD
      >('renamex_np')
    : null;

/// Gives [from] the name [to], refusing — never overwriting — when anything
/// already exists at [to]. On [PublishOutcome.published] [from] is gone; on
/// [PublishOutcome.taken] it is still there for the caller to deal with.
///
/// `File.renameSync` replaces an existing target, and checking first leaves a
/// window in which another copy (a second handoff into the same folder) can
/// land. So: `link(2)`, which fails rather than replace and works on every
/// POSIX filesystem with hard links; then an atomic no-replace rename for
/// filesystems without hard links (exFAT/FAT camera cards and drives, some
/// SMB shares); only if both are refused, [publishWithLock]. Measured: Linux
/// refuses `link` on exFAT and vfat but honours `renameat2` there; macOS
/// honours `renamex_np` on FAT32 but refuses both on exFAT — the usual
/// format of a Mac's external drives — so that's where the lock runs. errno
/// isn't read (the Dart VM may clobber it between the call and the read) —
/// whether the name is taken is asked of the filesystem instead.
PublishOutcome publishNoReplace(String from, String to) {
  if (_exists(to)) return PublishOutcome.taken;
  final f = from.toNativeUtf8();
  final t = to.toNativeUtf8();
  try {
    if (_link(f, t) == 0) {
      try {
        File(from).deleteSync();
      } on Object {
        // Harmless: the copy is published; a stray hidden part file is left.
      }
      return PublishOutcome.published;
    }
    if (_exists(to)) return PublishOutcome.taken;

    final renameAt2 = _renameAt2;
    if (renameAt2 != null &&
        renameAt2(_atFdCwd, f, _atFdCwd, t, _renameNoReplace) == 0) {
      return PublishOutcome.published;
    }
    final renamexNp = _renamexNp;
    if (renamexNp != null && renamexNp(f, t, _renameExcl) == 0) {
      return PublishOutcome.published;
    }
    if (_exists(to)) return PublishOutcome.taken;

    return publishWithLock(from, to);
  } finally {
    malloc
      ..free(f)
      ..free(t);
  }
}

/// How old a publish lock must be before it's taken for a crash's leftover.
/// Publishing is a check and a rename — milliseconds — so a minute is ample.
const Duration kPublishLockStale = Duration(minutes: 1);

/// [publishNoReplace] for a filesystem with no atomic no-replace call: a
/// check-then-rename, serialised by a hidden lock file beside [to].
///
/// The lock (`.<name>.publish`) is created exclusively — which exFAT does
/// support — so two Cullimingo copies racing for one name (two handoffs into
/// the same folder) can't both pass the check: the second finds the lock and
/// reports the name taken, and its caller compares the files as usual. A lock
/// a crash left behind is cleared once it's [kPublishLockStale]. Writers other
/// than Cullimingo don't take the lock, so against them a narrow window
/// remains — only where the OS offers nothing better.
PublishOutcome publishWithLock(String from, String to) {
  final lock = File(p.join(p.dirname(to), '.${p.basename(to)}.publish'));
  if (!_claim(lock)) return PublishOutcome.taken;
  try {
    if (_exists(to)) return PublishOutcome.taken;
    File(from).renameSync(to);
    return PublishOutcome.published;
  } finally {
    try {
      lock.deleteSync();
    } on Object {
      // A stray lock only delays this name for [kPublishLockStale].
    }
  }
}

// Takes [lock] exclusively; a stale one (a crash's) is removed and retried
// once. False: another publish of this name is in progress.
bool _claim(File lock) {
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      lock.createSync(exclusive: true);
      return true;
    } on FileSystemException {
      try {
        final age = DateTime.now().difference(lock.lastModifiedSync());
        if (age < kPublishLockStale) return false;
        lock.deleteSync();
      } on FileSystemException {
        // Vanished meanwhile (its publish finished): just retry.
      }
    }
  }
  return false;
}

// Anything at all at [path] — including a dangling symlink, which
// `File.existsSync` reports as absent.
bool _exists(String path) =>
    FileSystemEntity.typeSync(path, followLinks: false) !=
    FileSystemEntityType.notFound;

/// Which volume a path lives on, and how much room it has left.
class VolumeInfo {
  /// Creates volume info.
  const VolumeInfo({required this.mountPoint, required this.freeBytes});

  /// Where the filesystem holding the path is mounted (`/`, `/Volumes/Card`,
  /// `/mnt/nas`, …).
  final String mountPoint;

  /// Bytes available to an unprivileged writer.
  final int freeBytes;

  @override
  String toString() => 'VolumeInfo($mountPoint, $freeBytes free)';
}

/// The volume [path] lives on, or null when that can't be determined (an
/// unsupported platform, or no part of [path] exists). A missing [path] is
/// resolved through its nearest existing ancestor — exactly what the OS would
/// write into if the folders were created — so a destination whose drive was
/// unplugged reports the *system* volume, not its own.
VolumeInfo? volumeInfo(String path) {
  final existing = nearestExistingDirectory(path);
  if (existing == null) return null;
  final String real;
  try {
    real = Directory(existing).resolveSymbolicLinksSync();
  } on FileSystemException {
    return null;
  }
  if (Platform.isMacOS) return _macStatfs(real);
  if (Platform.isLinux) return _linuxVolume(real);
  return null;
}

/// [path] itself when it's a directory, else its nearest ancestor that is —
/// the folder anything created under [path] would actually land in. Null
/// when not even the filesystem root resolves.
String? nearestExistingDirectory(String path) {
  var dir = p.absolute(path);
  while (true) {
    if (FileSystemEntity.isDirectorySync(dir)) return dir;
    final parent = p.dirname(dir);
    if (parent == dir) return null;
    dir = parent;
  }
}

// statfs(2), 64-bit-inode layout (the only one on arm64; `statfs$INODE64` on
// x86_64): f_bsize u32 @0, f_bavail u64 @24, f_mntonname char[1024] @88;
// 2168 bytes in all.
const int _macStatfsSize = 2168;

VolumeInfo? _macStatfs(String path) {
  final symbol = _libc.providesSymbol(r'statfs$INODE64')
      ? r'statfs$INODE64'
      : 'statfs';
  final statfs = _libc.lookupFunction<_StatN, _StatD>(symbol);
  final buf = calloc<Uint8>(_macStatfsSize);
  final cPath = path.toNativeUtf8();
  try {
    if (statfs(cPath, buf) != 0) return null;
    final data = buf.asTypedList(_macStatfsSize).buffer.asByteData();
    final bsize = data.getUint32(0, Endian.host);
    final bavail = data.getUint64(24, Endian.host);
    final mount = (buf + 88).cast<Utf8>().toDartString();
    return VolumeInfo(mountPoint: mount, freeBytes: bsize * bavail);
  } finally {
    calloc.free(buf);
    malloc.free(cPath);
  }
}

// statvfs(3), 64-bit glibc layout (x86_64 and aarch64 alike): f_frsize u64 @8,
// f_bavail u64 @32; 112 bytes in all.
const int _linuxStatvfsSize = 112;

VolumeInfo? _linuxVolume(String path) {
  final mount = linuxMountPointOf(path, _readMountInfo());
  if (mount == null) return null;
  final statvfs = _libc.lookupFunction<_StatN, _StatD>('statvfs');
  final buf = calloc<Uint8>(_linuxStatvfsSize);
  final cPath = path.toNativeUtf8();
  try {
    if (statvfs(cPath, buf) != 0) return null;
    final data = buf.asTypedList(_linuxStatvfsSize).buffer.asByteData();
    final frsize = data.getUint64(8, Endian.host);
    final bavail = data.getUint64(32, Endian.host);
    return VolumeInfo(mountPoint: mount, freeBytes: frsize * bavail);
  } finally {
    calloc.free(buf);
    malloc.free(cPath);
  }
}

String _readMountInfo() {
  try {
    return File('/proc/self/mountinfo').readAsStringSync();
  } on FileSystemException {
    return '';
  }
}

/// The mount point (from a `/proc/self/mountinfo` dump) that [path] — an
/// absolute, symlink-free path — lives under: the longest mount point that
/// is [path] or one of its ancestors. Pure, for tests.
String? linuxMountPointOf(String path, String mountInfo) {
  String? best;
  for (final line in mountInfo.split('\n')) {
    final fields = line.split(' ');
    if (fields.length < 5) continue;
    final mount = _unescapeMountField(fields[4]);
    final covers = mount == '/' || path == mount || p.isWithin(mount, path);
    if (covers && (best == null || mount.length >= best.length)) best = mount;
  }
  return best;
}

// mountinfo escapes space, tab, newline and backslash as `\ooo` octal.
String _unescapeMountField(String field) => field.replaceAllMapped(
  RegExp(r'\\([0-7]{3})'),
  (m) => String.fromCharCode(int.parse(m[1]!, radix: 8)),
);
