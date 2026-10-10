import 'dart:io';
import 'dart:isolate';

import 'package:cullimingo/core/files/posix_fs.dart';
import 'package:cullimingo/core/files/sidecar_path.dart';
import 'package:path/path.dart' as p;

// What to do with photos the OS refused to trash — a network share (SMB via
// gvfs, the Flatpak document portal, …) has no trash at all (GitHub #14).
// Detecting such a location up front is guesswork, so these only run after a
// real refusal, and only when the user picked them.

/// The folder that stands in for the Trash where there is none: created beside
/// the photos, skipped by the folder scan (so a refresh or a recursive import
/// doesn't bring its contents back), emptied — or restored from — by the user.
const String kRejectedFolderName = '_Rejected';

/// A photo plus the sidecar that travels with it (which may not exist).
typedef PhotoFiles = ({String photo, String sidecar});

/// Moves each photo (and its sidecar, if any) into a [kRejectedFolderName]
/// folder beside it. A rename on the same volume — instant, no copy, fully
/// reversible. Never replaces anything: a name already taken there gets a
/// ` (2)`, ` (3)`, … suffix, its sidecar following. Returns the photo paths
/// that could not be moved (they stay where they were, sidecar included).
Future<List<String>> moveIntoRejectedFolder(List<PhotoFiles> items) =>
    Isolate.run(
      () => [
        for (final item in items)
          if (!_moveOne(item)) item.photo,
      ],
    );

/// Deletes each photo and its sidecar for good — no trash, no undo. Only for
/// photos the user explicitly chose to delete permanently. A photo that is
/// already gone counts as deleted. Returns the photo paths that could not be
/// deleted (their sidecars are kept with them).
Future<List<String>> deletePermanently(List<PhotoFiles> items) => Isolate.run(
  () => [
    for (final item in items)
      if (!_deleteOne(item)) item.photo,
  ],
);

bool _moveOne(PhotoFiles item) {
  if (!File(item.photo).existsSync()) return true;
  final dir = p.join(p.dirname(item.photo), kRejectedFolderName);
  try {
    Directory(dir).createSync();
  } on FileSystemException {
    return false;
  }
  final hasSidecar = File(item.sidecar).existsSync();
  final stem = p.basenameWithoutExtension(item.photo);
  final ext = p.extension(item.photo);
  for (var n = 1; n < 1000; n++) {
    final target = p.join(dir, n == 1 ? '$stem$ext' : '$stem ($n)$ext');
    final sidecarTarget = followSidecarPath(item.sidecar, item.photo, target);
    // The sidecar's name must be free too, or the photo would arrive without
    // its marks.
    if (hasSidecar &&
        FileSystemEntity.typeSync(sidecarTarget, followLinks: false) !=
            FileSystemEntityType.notFound) {
      continue;
    }
    final PublishOutcome outcome;
    try {
      outcome = publishNoReplace(item.photo, target);
    } on FileSystemException {
      return false;
    }
    if (outcome == PublishOutcome.taken) continue;
    if (!hasSidecar) return true;
    try {
      if (publishNoReplace(item.sidecar, sidecarTarget) ==
          PublishOutcome.published) {
        return true;
      }
    } on FileSystemException {
      // Handled below.
    }
    // The sidecar couldn't follow: put the photo back beside it rather than
    // separate a photo from its marks.
    try {
      if (publishNoReplace(target, item.photo) == PublishOutcome.published) {
        return false;
      }
    } on FileSystemException {
      // Left in the folder — still restorable, and reported as failed.
    }
    return false;
  }
  return false;
}

bool _deleteOne(PhotoFiles item) {
  try {
    final photo = File(item.photo);
    if (photo.existsSync()) photo.deleteSync();
  } on FileSystemException {
    return false;
  }
  try {
    final sidecar = File(item.sidecar);
    if (sidecar.existsSync()) sidecar.deleteSync();
  } on FileSystemException {
    // The photo is gone; a leftover sidecar is harmless (and re-pairs with
    // nothing).
  }
  return true;
}
