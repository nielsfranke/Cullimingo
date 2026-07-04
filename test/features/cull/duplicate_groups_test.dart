import 'package:cullimingo/features/cull/domain/duplicate_groups.dart';
import 'package:flutter_test/flutter_test.dart';

GroupablePhoto _p(int id, DateTime? t, {String? cam = 'Sony A'}) =>
    (id: id, capturedAt: t, camera: cam);

DateTime _t(int s) => DateTime(2026, 6, 25, 10, 0, s);

void main() {
  test('consecutive shots within the gap form one burst', () {
    final groups = groupByCaptureTime([
      _p(1, _t(0)),
      _p(2, _t(1)),
      _p(3, _t(2)),
    ]);
    expect(groups, [
      [1, 2, 3],
    ]);
  });

  test('a gap larger than maxGap starts a new group', () {
    final groups = groupByCaptureTime([
      _p(1, _t(0)),
      _p(2, _t(1)),
      _p(3, _t(10)),
      _p(4, _t(11)),
    ]);
    expect(groups, [
      [1, 2],
      [3, 4],
    ]);
  });

  test('different camera breaks the burst even when times are close', () {
    final groups = groupByCaptureTime([
      _p(1, _t(0)),
      _p(2, _t(1), cam: 'Canon B'),
    ], maxGap: const Duration(seconds: 5));
    expect(groups, [
      [1],
      [2],
    ]);
  });

  test('sorts by capture time regardless of input order', () {
    final groups = groupByCaptureTime([
      _p(3, _t(2)),
      _p(1, _t(0)),
      _p(2, _t(1)),
    ]);
    expect(groups, [
      [1, 2, 3],
    ]);
  });

  test('undated photos are singletons appended after timed groups', () {
    final groups = groupByCaptureTime([
      _p(1, _t(0)),
      _p(2, _t(1)),
      _p(3, null),
      _p(4, null),
    ]);
    expect(groups, [
      [1, 2],
      [3],
      [4],
    ]);
  });

  group('BurstGroups indexing', () {
    final bg = BurstGroups([
      [1, 2], // burst index 0
      [3], // singleton — no index
      [4, 5, 6], // burst index 1
    ]);

    test('members get a running burst index, singletons get null', () {
      expect(bg.groupIndexOf(1), 0);
      expect(bg.groupIndexOf(2), 0);
      expect(bg.groupIndexOf(3), isNull);
      expect(bg.groupIndexOf(4), 1);
      expect(bg.groupIndexOf(6), 1);
    });

    test('sizeOf and memberIds', () {
      expect(bg.sizeOf(1), 2);
      expect(bg.sizeOf(3), 1);
      expect(bg.memberIds, {1, 2, 4, 5, 6});
      expect(bg.burstCount, 2);
    });
  });

  group('groupContiguous', () {
    final byId = {for (var i = 1; i <= 6; i++) i: 'p$i'};

    test('lays group members together, drops singletons', () {
      final out = groupContiguous(
        [
          [1, 2],
          [3], // singleton → dropped
          [4, 5, 6],
        ],
        byId,
        (_) => true,
      );
      expect(out, ['p1', 'p2', 'p4', 'p5', 'p6']);
    });

    test('applies the keep predicate within groups', () {
      final out = groupContiguous(
        [
          [1, 2, 3],
        ],
        byId,
        (p) => p != 'p2', // p2 filtered out by another active filter
      );
      expect(out, ['p1', 'p3']);
    });
  });
}
