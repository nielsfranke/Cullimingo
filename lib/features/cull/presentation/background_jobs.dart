import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'background_jobs.g.dart';

/// The display state of one non-modal background job — what the floating
/// progress card shows (`BUILD_PLAN.md` §6/§7b). Cancellation is deliberately
/// *not* here: a running job's cancel token must stay reachable after the page
/// is disposed (a provider read would throw), so it lives with the runner.
@immutable
class JobProgress {
  /// Creates a progress snapshot.
  const JobProgress({
    required this.verb,
    required this.done,
    required this.total,
  });

  /// Present-participle label ("Exporting", "Uploading", "Finding similar").
  final String verb;

  /// Items completed so far.
  final int done;

  /// Total items in the job.
  final int total;

  /// Returns a copy with the given fields replaced.
  JobProgress copyWith({String? verb, int? done, int? total}) => JobProgress(
    verb: verb ?? this.verb,
    done: done ?? this.done,
    total: total ?? this.total,
  );

  @override
  bool operator ==(Object other) =>
      other is JobProgress &&
      other.verb == verb &&
      other.done == done &&
      other.total == total;

  @override
  int get hashCode => Object.hash(verb, done, total);
}

/// Progress of every in-flight background job. Each slot is null when that job
/// isn't running; the page shows one floating card per non-null slot. The three
/// jobs are independent and may overlap.
@immutable
class BackgroundJobsState {
  /// Creates a jobs snapshot.
  const BackgroundJobsState({
    this.export,
    this.contactSheet,
    this.findSimilar,
    this.transfer,
  });

  /// The running export, or null.
  final JobProgress? export;

  /// The running ContactSheet send, or null.
  final JobProgress? contactSheet;

  /// The running find-similar pass, or null.
  final JobProgress? findSimilar;

  /// The running copy/move transfer, or null.
  final JobProgress? transfer;

  @override
  bool operator ==(Object other) =>
      other is BackgroundJobsState &&
      other.export == export &&
      other.contactSheet == contactSheet &&
      other.findSimilar == findSimilar &&
      other.transfer == transfer;

  @override
  int get hashCode => Object.hash(export, contactSheet, findSimilar, transfer);
}

/// Holds the progress of the page's non-modal background jobs (export,
/// ContactSheet send, find-similar). Pure state transitions — the runner drives
/// these and the page watches them to render the floating progress cards.
///
/// Every `tick`/`update` is a no-op when its slot is null, so a late progress
/// event that arrives after the job was cancelled (its slot cleared) can never
/// resurrect the card.
@riverpod
class BackgroundJobs extends _$BackgroundJobs {
  @override
  BackgroundJobsState build() => const BackgroundJobsState();

  /// Starts an export of [total] items.
  void startExport(int total) => state = BackgroundJobsState(
    export: JobProgress(verb: 'Exporting', done: 0, total: total),
    contactSheet: state.contactSheet,
    findSimilar: state.findSimilar,
    transfer: state.transfer,
  );

  /// Advances the export to [done] items (no-op if not running).
  void tickExport(int done) {
    final e = state.export;
    if (e == null) return;
    state = BackgroundJobsState(
      export: e.copyWith(done: done),
      contactSheet: state.contactSheet,
      findSimilar: state.findSimilar,
      transfer: state.transfer,
    );
  }

  /// Updates the export card's [verb]/[done]/[total] (no-op if not running) —
  /// a delivered export flips it from "Exporting" to "Uploading".
  void updateExport({String? verb, int? done, int? total}) {
    final e = state.export;
    if (e == null) return;
    state = BackgroundJobsState(
      export: e.copyWith(verb: verb, done: done, total: total),
      contactSheet: state.contactSheet,
      findSimilar: state.findSimilar,
      transfer: state.transfer,
    );
  }

  /// Clears the export card.
  void clearExport() => state = BackgroundJobsState(
    contactSheet: state.contactSheet,
    findSimilar: state.findSimilar,
    transfer: state.transfer,
  );

  /// Starts a ContactSheet send with the given [verb] and [total].
  void startContactSheet(String verb, int total) => state = BackgroundJobsState(
    export: state.export,
    contactSheet: JobProgress(verb: verb, done: 0, total: total),
    findSimilar: state.findSimilar,
    transfer: state.transfer,
  );

  /// Updates the ContactSheet card's [verb]/[done]/[total] (no-op if not
  /// running).
  void updateContactSheet({String? verb, int? done, int? total}) {
    final c = state.contactSheet;
    if (c == null) return;
    state = BackgroundJobsState(
      export: state.export,
      contactSheet: c.copyWith(verb: verb, done: done, total: total),
      findSimilar: state.findSimilar,
      transfer: state.transfer,
    );
  }

  /// Clears the ContactSheet card.
  void clearContactSheet() => state = BackgroundJobsState(
    export: state.export,
    findSimilar: state.findSimilar,
    transfer: state.transfer,
  );

  /// Starts a find-similar pass over [total] photos.
  void startFindSimilar(int total) => state = BackgroundJobsState(
    export: state.export,
    contactSheet: state.contactSheet,
    findSimilar: JobProgress(verb: 'Finding similar', done: 0, total: total),
    transfer: state.transfer,
  );

  /// Advances the find-similar pass to [done] photos (no-op if not running).
  void tickFindSimilar(int done) {
    final h = state.findSimilar;
    if (h == null) return;
    state = BackgroundJobsState(
      export: state.export,
      contactSheet: state.contactSheet,
      findSimilar: h.copyWith(done: done),
      transfer: state.transfer,
    );
  }

  /// Clears the find-similar card.
  void clearFindSimilar() => state = BackgroundJobsState(
    export: state.export,
    contactSheet: state.contactSheet,
    transfer: state.transfer,
  );

  /// Starts a copy/move transfer of [total] photos with the given [verb]
  /// ("Copying" / "Moving").
  void startTransfer(String verb, int total) => state = BackgroundJobsState(
    export: state.export,
    contactSheet: state.contactSheet,
    findSimilar: state.findSimilar,
    transfer: JobProgress(verb: verb, done: 0, total: total),
  );

  /// Advances the transfer to [done] photos (no-op if not running).
  void tickTransfer(int done) {
    final t = state.transfer;
    if (t == null) return;
    state = BackgroundJobsState(
      export: state.export,
      contactSheet: state.contactSheet,
      findSimilar: state.findSimilar,
      transfer: t.copyWith(done: done),
    );
  }

  /// Clears the transfer card.
  void clearTransfer() => state = BackgroundJobsState(
    export: state.export,
    contactSheet: state.contactSheet,
    findSimilar: state.findSimilar,
  );
}
