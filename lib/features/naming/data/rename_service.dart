import 'dart:io';
import 'dart:isolate';

import 'package:cullimingo/core/files/sidecar_path.dart';
import 'package:cullimingo/core/naming/rename_template.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:path/path.dart' as p;

/// A photo an in-place rename acts on: its DB [id], absolute [path], capture
/// time and camera (the last two drive the date/camera tokens).
class RenameSource {
  /// Creates a rename source.
  const RenameSource({
    required this.id,
    required this.path,
    required this.capturedAt,
    this.camera,
  });

  /// The DB row id, so the caller can rewrite `photos.path` after the rename.
  final int id;

  /// Absolute current file path.
  final String path;

  /// Capture time for the date/time tokens (caller falls back to mtime).
  final DateTime capturedAt;

  /// Camera make/model for the `{camera}` token, when known.
  final String? camera;
}

/// One planned in-place rename: the file at [source] keeps its folder but takes
/// the new absolute name [target]. [sidecars] carry the matching `.xmp`
/// files that exist so the pairing survives. An [unchanged] item
/// is a no-op (the new name equals the old).
class RenameItem {
  /// Creates a rename item.
  const RenameItem({
    required this.photoId,
    required this.source,
    required this.target,
    this.sidecars = const [],
  });

  /// The DB row id this rename belongs to.
  final int photoId;

  /// Absolute current path.
  final String source;

  /// Absolute new path (same folder as [source]).
  final String target;

  /// The sidecars to rename alongside (current → new path): the pair's shared
  /// `DSC1.xmp` and/or a per-file `DSC1.JPG.xmp`. Empty when there are none.
  final List<({String source, String target})> sidecars;

  /// Whether this is a no-op (new name == old name).
  bool get unchanged => p.equals(source, target);
}

/// How one item's disk rename turned out.
enum RenameOutcome {
  /// File (and any sidecar) renamed to its target.
  renamed,

  /// New name equalled the old — nothing to do.
  unchanged,

  /// The rename threw (permission, vanished source, …). Original left in place.
  error,
}

/// Result of one item's disk rename, mapped back by [photoId].
class RenameResult {
  /// Creates a rename result.
  const RenameResult({
    required this.photoId,
    required this.source,
    required this.newPath,
    required this.outcome,
  });

  /// The DB row id.
  final int photoId;

  /// The path the file had before the rename.
  final String source;

  /// The path it now has, or null when unchanged or on error.
  final String? newPath;

  /// The outcome.
  final RenameOutcome outcome;

  /// Whether the file was actually moved to a new name.
  bool get ok => outcome == RenameOutcome.renamed && newPath != null;
}

/// Aggregate outcome of a rename run.
class RenameSummary {
  /// Creates a summary over [results].
  const RenameSummary(this.results);

  /// Per-item results.
  final List<RenameResult> results;

  /// Files actually renamed.
  int get renamed => results.where((r) => r.ok).length;

  /// No-ops (name already matched the pattern).
  int get unchanged =>
      results.where((r) => r.outcome == RenameOutcome.unchanged).length;

  /// Failures (left in place).
  int get failed =>
      results.where((r) => r.outcome == RenameOutcome.error).length;
}

/// Builds an in-place rename plan for [sources] using [template] (a
/// filename-only pattern — the file stays in its folder; any folder tokens are
/// flattened to the basename). Sequence tokens count from 1 in list order. New
/// names that would collide — with each other, or with a bystander already on
/// disk that isn't itself in this batch — get a `_2`, `_3`, … suffix, exactly
/// like ingest/transfer. An existing `.xmp` sidecar is renamed alongside.
///
/// Runs the planning (which stats the disk for collisions/sidecars) on a
/// background isolate so hundreds of files never touch the UI isolate
/// (rule #2).
Future<List<RenameItem>> buildRenamePlan(
  List<RenameSource> sources, {
  required RenameTemplate template,
  String shoot = '',
  bool includeSidecars = true,
}) {
  return Isolate.run(
    () => planRenames(
      sources,
      template: template,
      shoot: shoot,
      includeSidecars: includeSidecars,
      exists: (path) => File(path).existsSync(),
    ),
  );
}

/// The key [planRenames] groups by: folder + lower-cased basename stem.
String _stemKey(String path) =>
    '${p.canonicalize(p.dirname(path))}\u0000'
    '${p.basenameWithoutExtension(path).toLowerCase()}';

/// The ids in [targetIds] plus every photo in [all] that shares a folder and
/// basename stem with one of them — the other half of a RAW+JPEG pair. A rename
/// must take the whole group, or it splits the pair: with *Hide JPEG pairs* on
/// (or a Picks filter the unmarked JPEG fails) the twin isn't in the grid
/// selection, so renaming just the RAW would leave `DSC1.JPG` behind as the
/// RAW becomes `2026-10-05_001.RAF` (GitHub #12).
Set<int> withStemPartners(
  Set<int> targetIds,
  Iterable<({int id, String path})> all,
) {
  final photos = all.toList();
  final keys = {
    for (final photo in photos)
      if (targetIds.contains(photo.id)) _stemKey(photo.path),
  };
  return {
    ...targetIds,
    for (final photo in photos)
      if (keys.contains(_stemKey(photo.path))) photo.id,
  };
}

/// Pure planning core (no isolate), with an injectable [exists] predicate so
/// tests exercise collision resolution and sidecar pairing without a disk.
///
/// Photos that share a folder **and** a basename stem — a RAW+JPEG pair like
/// `DSC1.ARW` + `DSC1.JPG` — are treated as one unit: they get the same new
/// base, share one sequence number, and their common `.xmp` sidecar is renamed
/// once. So a `{seq}` rename keeps the pair together instead of splitting it.
List<RenameItem> planRenames(
  List<RenameSource> sources, {
  required RenameTemplate template,
  required bool Function(String path) exists,
  String shoot = '',
  bool includeSidecars = true,
}) {
  // Group by folder + stem, preserving first-appearance order for sequencing.
  final groups = <String, List<RenameSource>>{};
  for (final s in sources) {
    (groups[_stemKey(s.path)] ??= []).add(s);
  }

  final batchSources = {for (final s in sources) p.canonicalize(s.path)};
  // Assigned new stems, as `canonicalDir\u0000lowercasedStem`.
  final usedStems = <String>{};
  final items = <RenameItem>[];
  var seq = 1;
  for (final group in groups.values) {
    final rep = group.first;
    final dir = p.dirname(rep.path);
    // The engine may emit folder separators; a rename stays put, so collapse to
    // just the basename it produced, then drop the extension for the stem.
    final rendered = template.pathFor(
      RenameInput(
        capturedAt: rep.capturedAt,
        originalName: p.basename(rep.path),
        sequence: seq++,
        camera: rep.camera,
        shoot: shoot,
      ),
    );
    final exts = [for (final s in group) p.extension(s.path)];
    final stem = _uniqueStem(
      dir,
      p.basenameWithoutExtension(p.basename(rendered)),
      exts: exts,
      usedStems: usedStems,
      batchSources: batchSources,
      exists: exists,
    );
    usedStems.add('${p.canonicalize(dir)}\u0000${stem.toLowerCase()}');

    // The shared sidecar (oldstem.xmp) is renamed once, with the RAW member
    // it belongs to (else the first); each member's own per-file sidecar
    // (`DSC1.JPG.xmp`) rides with that member.
    final sharedOwner = group.indexWhere((s) => isRawPath(s.path));
    final sharedSidecar = stemSidecarPath(rep.path);
    final hasShared = includeSidecars && exists(sharedSidecar);
    for (var i = 0; i < group.length; i++) {
      final s = group[i];
      final target = p.join(dir, '$stem${p.extension(s.path)}');
      final ownSidecar = fileSidecarPath(s.path);
      items.add(
        RenameItem(
          photoId: s.id,
          source: s.path,
          target: target,
          sidecars: [
            if (hasShared && i == (sharedOwner < 0 ? 0 : sharedOwner))
              (source: sharedSidecar, target: p.join(dir, '$stem.xmp')),
            if (includeSidecars && exists(ownSidecar))
              (source: ownSidecar, target: fileSidecarPath(target)),
          ],
        ),
      );
    }
  }
  return items;
}

/// Resolves a free basename [stem] in [dir] for a group with extensions [exts]:
/// not already assigned to another group ([usedStems]), and not colliding with
/// a bystander file on disk — a path owned by a [batchSources] member counts as
/// free, since that source is being renamed away (two-phase frees it first).
String _uniqueStem(
  String dir,
  String stem, {
  required List<String> exts,
  required Set<String> usedStems,
  required Set<String> batchSources,
  required bool Function(String path) exists,
}) {
  final dirKey = p.canonicalize(dir);
  bool taken(String candidate) {
    if (usedStems.contains('$dirKey\u0000${candidate.toLowerCase()}')) {
      return true;
    }
    for (final ext in exts) {
      final path = p.join(dir, '$candidate$ext');
      if (batchSources.contains(p.canonicalize(path))) continue;
      if (exists(path)) return true;
    }
    return false;
  }

  if (!taken(stem)) return stem;
  var n = 2;
  while (taken('${stem}_$n')) {
    n++;
  }
  return '${stem}_$n';
}

/// Applies [plan] to disk off the UI isolate and returns a result per item.
Future<List<RenameResult>> runRename(List<RenameItem> plan) =>
    Isolate.run(() => applyRenamePlan(plan));

/// Renames [plan] on disk in two phases so a name shuffle within the batch
/// (a→b, b→c) never clobbers a not-yet-moved source: every file goes to a
/// unique temp name first, then each temp to its final name. The `.xmp` sidecar
/// rides along. Synchronous + isolate-free so a temp-dir test can drive it.
List<RenameResult> applyRenamePlan(List<RenameItem> plan) {
  final results = <RenameResult>[];
  final staged =
      <
        ({
          RenameItem item,
          String temp,
          List<({String source, String target, String temp})> sidecars,
        })
      >[];

  // Phase 1: source (+ sidecar) → unique temp in the same folder.
  var i = 0;
  for (final item in plan) {
    if (item.unchanged) {
      results.add(
        RenameResult(
          photoId: item.photoId,
          source: item.source,
          newPath: null,
          outcome: RenameOutcome.unchanged,
        ),
      );
      continue;
    }
    try {
      final temp = _tempPath(item.target, i);
      File(item.source).renameSync(temp);
      final sidecars = <({String source, String target, String temp})>[];
      for (final (j, sc) in item.sidecars.indexed) {
        if (!File(sc.source).existsSync()) continue;
        final tempSidecar = _tempPath(sc.target, i, j + 1);
        try {
          File(sc.source).renameSync(tempSidecar);
          sidecars.add((
            source: sc.source,
            target: sc.target,
            temp: tempSidecar,
          ));
        } on Object {
          // A lost sidecar is non-fatal.
        }
      }
      staged.add((item: item, temp: temp, sidecars: sidecars));
      i++;
    } on Object {
      results.add(
        RenameResult(
          photoId: item.photoId,
          source: item.source,
          newPath: null,
          outcome: RenameOutcome.error,
        ),
      );
    }
  }

  // Phase 2: temp → final.
  for (final s in staged) {
    try {
      File(s.temp).renameSync(s.item.target);
      for (final sc in s.sidecars) {
        try {
          File(sc.temp).renameSync(sc.target);
        } on Object {
          // Best effort — the photo itself is what matters.
        }
      }
      results.add(
        RenameResult(
          photoId: s.item.photoId,
          source: s.item.source,
          newPath: s.item.target,
          outcome: RenameOutcome.renamed,
        ),
      );
    } on Object {
      // Phase 2 failed after phase 1 moved the file to a temp name: roll it
      // (and any sidecar) back to the original path so a failed rename leaves
      // the file exactly where the DB row still points — never stranded at the
      // hidden temp name. If even the rollback fails there is nothing more we
      // can do; the item is still reported as an error either way.
      _rollBack(s.temp, s.item.source);
      for (final sc in s.sidecars) {
        _rollBack(sc.temp, sc.source);
      }
      results.add(
        RenameResult(
          photoId: s.item.photoId,
          source: s.item.source,
          newPath: null,
          outcome: RenameOutcome.error,
        ),
      );
    }
  }
  return results;
}

/// A unique hidden temp path in [finalPath]'s folder for the phase-1 stage.
/// [part] tells an item's sidecars (1, 2, …) apart from its photo (0).
String _tempPath(String finalPath, int i, [int part = 0]) => p.join(
  p.dirname(finalPath),
  '.cullrename_${i}_${part}_${DateTime.now().microsecondsSinceEpoch}.tmp',
);

/// Best-effort restore of a phase-1 temp file back to its original path when
/// phase 2 fails, so the file stays where the DB row expects it.
void _rollBack(String temp, String original) {
  try {
    File(temp).renameSync(original);
  } on Object {
    // Nothing more we can do; the item is already reported as an error.
  }
}
