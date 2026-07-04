import 'package:cullimingo/features/cull/presentation/background_jobs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;
  BackgroundJobs notifier() => container.read(backgroundJobsProvider.notifier);
  BackgroundJobsState read() => container.read(backgroundJobsProvider);

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  test('starts empty', () {
    expect(read().export, isNull);
    expect(read().contactSheet, isNull);
    expect(read().findSimilar, isNull);
  });

  group('export', () {
    test('start → tick → clear', () {
      notifier().startExport(10);
      expect(
        read().export,
        const JobProgress(verb: 'Exporting', done: 0, total: 10),
      );
      notifier().tickExport(4);
      expect(read().export!.done, 4);
      notifier().clearExport();
      expect(read().export, isNull);
    });

    test('tick is a no-op when not running (no card resurrection)', () {
      notifier().tickExport(3);
      expect(read().export, isNull);
    });

    test('clear leaves other jobs untouched', () {
      notifier()
        ..startExport(5)
        ..startFindSimilar(8)
        ..clearExport();
      expect(read().export, isNull);
      expect(read().findSimilar!.total, 8);
    });
  });

  group('contactSheet', () {
    test('start → update verb/total/done → clear', () {
      notifier().startContactSheet('Rendering', 3);
      expect(
        read().contactSheet,
        const JobProgress(verb: 'Rendering', done: 0, total: 3),
      );
      notifier().updateContactSheet(verb: 'Uploading', total: 12, done: 0);
      expect(
        read().contactSheet,
        const JobProgress(verb: 'Uploading', done: 0, total: 12),
      );
      notifier().updateContactSheet(done: 6);
      expect(read().contactSheet!.done, 6);
      notifier().clearContactSheet();
      expect(read().contactSheet, isNull);
    });

    test('update after clear does not resurrect the card', () {
      notifier()
        ..startContactSheet('Rendering', 3)
        ..clearContactSheet()
        ..updateContactSheet(done: 2);
      expect(read().contactSheet, isNull);
    });
  });

  group('findSimilar', () {
    test('start → tick → clear', () {
      notifier().startFindSimilar(50);
      expect(
        read().findSimilar,
        const JobProgress(verb: 'Finding similar', done: 0, total: 50),
      );
      notifier().tickFindSimilar(48);
      expect(read().findSimilar!.done, 48);
      notifier().clearFindSimilar();
      expect(read().findSimilar, isNull);
    });

    test('tick after clear does not resurrect', () {
      notifier()
        ..startFindSimilar(4)
        ..clearFindSimilar()
        ..tickFindSimilar(2);
      expect(read().findSimilar, isNull);
    });
  });

  test('three jobs can run and clear independently', () {
    notifier()
      ..startExport(2)
      ..startContactSheet('Rendering', 3)
      ..startFindSimilar(4);
    expect(read().export!.total, 2);
    expect(read().contactSheet!.total, 3);
    expect(read().findSimilar!.total, 4);

    notifier().clearContactSheet();
    expect(read().export, isNotNull);
    expect(read().contactSheet, isNull);
    expect(read().findSimilar, isNotNull);
  });
}
