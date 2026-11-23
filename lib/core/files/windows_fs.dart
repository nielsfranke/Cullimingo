import 'dart:ffi';

import 'package:ffi/ffi.dart';

// The Windows half of `posix_fs.dart`: kernel32 calls for publishing a file
// without replacing one, and for asking which volume a path lives on and how
// much room it has. Only reached when `Platform.isWindows`; the library is
// opened lazily, so macOS/Linux never touch it. Blocking calls: run them off
// the UI isolate.

typedef _MoveFileExD = int Function(Pointer<Utf16>, Pointer<Utf16>, int);
typedef _GetVolumePathNameD = int Function(Pointer<Utf16>, Pointer<Utf16>, int);
typedef _GetDiskFreeSpaceExD =
    int Function(
      Pointer<Utf16>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
    );

final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

final _MoveFileExD _moveFileEx = _kernel32
    .lookupFunction<
      Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
      _MoveFileExD
    >('MoveFileExW');

final _GetVolumePathNameD _getVolumePathName = _kernel32
    .lookupFunction<
      Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
      _GetVolumePathNameD
    >('GetVolumePathNameW');

final _GetDiskFreeSpaceExD _getDiskFreeSpaceEx = _kernel32
    .lookupFunction<
      Int32 Function(
        Pointer<Utf16>,
        Pointer<Uint64>,
        Pointer<Uint64>,
        Pointer<Uint64>,
      ),
      _GetDiskFreeSpaceExD
    >('GetDiskFreeSpaceExW');

/// `MOVEFILE_WRITE_THROUGH`: return only once the rename is on disk.
const int _moveFileWriteThrough = 0x8;

/// Renames [from] to [to] with `MoveFileExW` *without*
/// `MOVEFILE_REPLACE_EXISTING`, so the OS refuses — atomically, with no
/// check-then-rename window — when anything already exists at [to]. Works on
/// NTFS, exFAT and FAT alike. Both paths must be on one volume (a part file
/// always sits beside its final name). True when [from] now lives at [to].
bool windowsRenameNoReplace(String from, String to) {
  final f = from.toNativeUtf16();
  final t = to.toNativeUtf16();
  try {
    return _moveFileEx(f, t, _moveFileWriteThrough) != 0;
  } finally {
    malloc
      ..free(f)
      ..free(t);
  }
}

/// The volume root [path] (an existing directory) lives on — `C:\`, `E:\`, a
/// mounted-folder path or `\\server\share\` — and the bytes free to this
/// user there, or null when Windows can't tell.
({String mountPoint, int freeBytes})? windowsVolume(String path) {
  const maxPath = 32768;
  final cPath = path.toNativeUtf16();
  final root = calloc<Uint16>(maxPath).cast<Utf16>();
  final free = calloc<Uint64>(3);
  try {
    if (_getVolumePathName(cPath, root, maxPath) == 0) return null;
    if (_getDiskFreeSpaceEx(root, free, free + 1, free + 2) == 0) return null;
    return (mountPoint: root.toDartString(), freeBytes: free.value);
  } finally {
    malloc.free(cPath);
    calloc
      ..free(root)
      ..free(free);
  }
}
