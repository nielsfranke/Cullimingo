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

/// What `GetDriveTypeW` says a drive is.
enum WindowsDriveType {
  /// Unknown or no root directory.
  unknown,

  /// A card reader, USB stick or other removable-media drive.
  removable,

  /// An internal or external hard disk / SSD.
  fixed,

  /// A mapped network drive.
  remote,

  /// An optical drive.
  cdrom,

  /// A RAM disk.
  ramdisk,
}

/// One drive letter with media in it.
typedef WindowsDrive = ({String root, WindowsDriveType type, String label});

typedef _GetDriveTypeD = int Function(Pointer<Utf16>);
typedef _GetVolumeInformationD =
    int Function(
      Pointer<Utf16>,
      Pointer<Utf16>,
      int,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Utf16>,
      int,
    );
typedef _SetThreadErrorModeD = int Function(int, Pointer<Uint32>);

final int Function() _getLogicalDrives = _kernel32
    .lookupFunction<Uint32 Function(), int Function()>('GetLogicalDrives');

final _GetDriveTypeD _getDriveType = _kernel32
    .lookupFunction<Uint32 Function(Pointer<Utf16>), _GetDriveTypeD>(
      'GetDriveTypeW',
    );

final _GetVolumeInformationD _getVolumeInformation = _kernel32
    .lookupFunction<
      Int32 Function(
        Pointer<Utf16>,
        Pointer<Utf16>,
        Uint32,
        Pointer<Uint32>,
        Pointer<Uint32>,
        Pointer<Uint32>,
        Pointer<Utf16>,
        Uint32,
      ),
      _GetVolumeInformationD
    >('GetVolumeInformationW');

final _SetThreadErrorModeD _setThreadErrorMode = _kernel32
    .lookupFunction<
      Int32 Function(Uint32, Pointer<Uint32>),
      _SetThreadErrorModeD
    >('SetThreadErrorMode');

/// `SEM_FAILCRITICALERRORS`: an empty card-reader slot fails quietly instead
/// of popping a "There is no disk in the drive" dialog.
const int _semFailCriticalErrors = 0x1;

/// Every drive letter (`A:\` … `Z:\`) that currently has media, with its type
/// and volume label. An empty card-reader slot is skipped (no volume info).
/// Blocking: run it off the UI isolate.
List<WindowsDrive> windowsDrives() {
  final oldMode = calloc<Uint32>();
  _setThreadErrorMode(_semFailCriticalErrors, oldMode);
  final label = calloc<Uint16>(261).cast<Utf16>();
  try {
    final mask = _getLogicalDrives();
    final drives = <WindowsDrive>[];
    for (var i = 0; i < 26; i++) {
      if (mask & (1 << i) == 0) continue;
      final root = '${String.fromCharCode(0x41 + i)}:\\';
      final cRoot = root.toNativeUtf16();
      try {
        final type = _getDriveType(cRoot);
        if (_getVolumeInformation(
              cRoot,
              label,
              261,
              nullptr,
              nullptr,
              nullptr,
              nullptr,
              0,
            ) ==
            0) {
          continue; // no media (empty reader slot, ejected disc)
        }
        drives.add((
          root: root,
          type: switch (type) {
            2 => WindowsDriveType.removable,
            3 => WindowsDriveType.fixed,
            4 => WindowsDriveType.remote,
            5 => WindowsDriveType.cdrom,
            6 => WindowsDriveType.ramdisk,
            _ => WindowsDriveType.unknown,
          },
          label: label.toDartString(),
        ));
      } finally {
        malloc.free(cRoot);
      }
    }
    return drives;
  } finally {
    _setThreadErrorMode(oldMode.value, nullptr);
    calloc
      ..free(oldMode)
      ..free(label);
  }
}
