import 'package:cullimingo/features/cull/domain/exposure_brackets.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _t(int s) => DateTime(2026, 5, 29, 12, 44).add(Duration(seconds: s));

BracketablePhoto _p(
  int id,
  int atSec, {
  double? bias,
  double? shutter,
  String? cam = 'Fujifilm X-H2S',
}) => (
  id: id,
  capturedAt: _t(atSec),
  camera: cam,
  exposureBias: bias,
  exposureTime: shutter,
);

void main() {
  group('groupExposureBrackets', () {
    test('a shutter-only triple with a long-exposure gap is one bracket', () {
      // Fuji .RAF: no exposure bias, shutter sweeps 2.5 / 20 / 0.33 s, and the
      // 20 s exposure (plus NR) pushes the next frame 40 s later.
      final groups = groupExposureBrackets([
        _p(1, 0, shutter: 2.5),
        _p(2, 2, shutter: 20),
        _p(3, 42, shutter: 1 / 3),
      ]);
      expect(groups, [
        [1, 2, 3],
      ]);
    });

    test('back-to-back brackets split on the repeated exposure', () {
      final groups = groupExposureBrackets([
        _p(1, 0, bias: 0),
        _p(2, 1, bias: 3),
        _p(3, 2, bias: -3),
        _p(4, 3, bias: 0),
        _p(5, 4, bias: 3),
        _p(6, 5, bias: -3),
      ]);
      expect(groups, [
        [1, 2, 3],
        [4, 5, 6],
      ]);
    });

    test('a constant-exposure sequence collapses to singletons', () {
      // Drone frames: every frame 0 EV, so each closes the run immediately.
      final groups = groupExposureBrackets([
        _p(1, 0, bias: 0, shutter: 1 / 5000, cam: 'DJI FC9313'),
        _p(2, 38, bias: 0, shutter: 1 / 6000, cam: 'DJI FC9313'),
        _p(3, 61, bias: 0, shutter: 1 / 3200, cam: 'DJI FC9313'),
      ]);
      expect(groups, [
        [1],
        [2],
        [3],
      ]);
    });

    test('a second camera never joins the bracket', () {
      // A drone frame lands between two Fuji bracket frames by timestamp; it
      // must not split the Fuji bracket.
      final groups = groupExposureBrackets([
        _p(1, 0, shutter: 2.5),
        _p(2, 1, bias: 0, shutter: 1 / 5000, cam: 'DJI FC9313'),
        _p(3, 2, shutter: 20),
        _p(4, 42, shutter: 1 / 3),
      ]);
      expect(
        groups,
        containsAll([
          [1, 3, 4],
          [2],
        ]),
      );
    });

    test('a large gap between fast frames is not a bracket', () {
      // Two 1/100 s frames a minute apart: the shutter-aware tolerance stays
      // near the 15 s base, so the gap breaks them apart.
      final groups = groupExposureBrackets([
        _p(1, 0, shutter: 1 / 100),
        _p(2, 60, shutter: 1 / 100),
      ]);
      expect(groups, [
        [1],
        [2],
      ]);
    });

    test('frames without a signature or capture time are singletons', () {
      final groups = groupExposureBrackets([
        _p(1, 0, bias: 0),
        _p(2, 1, bias: 3),
        (
          id: 3,
          capturedAt: null,
          camera: 'Fujifilm X-H2S',
          exposureBias: 0.0,
          exposureTime: null,
        ),
        (
          id: 4,
          capturedAt: _t(2),
          camera: 'Fujifilm X-H2S',
          exposureBias: null,
          exposureTime: null,
        ),
      ]);
      expect(
        groups,
        containsAll([
          [1, 2],
          [3],
          [4],
        ]),
      );
    });
  });

  group('BracketGroups', () {
    List<BracketablePhoto> triple() => [
      _p(1, 0, shutter: 2.5),
      _p(2, 2, shutter: 20),
      _p(3, 42, shutter: 1 / 3),
    ];

    test('indexes the bracket and picks the middle shutter as reference', () {
      final b = BracketGroups(triple());
      expect(b.bracketCount, 1);
      expect(b.memberIds, {1, 2, 3});
      expect(b.sizeOf(1), 3);
      expect(b.groupOf(2), containsAll([1, 2, 3]));
      // 2.5 s is the median exposure between 0.33 s and 20 s → the normal shot.
      expect(b.referenceIds, {1});
      expect(b.isReference(1), isTrue);
      expect(b.isReference(2), isFalse);
      expect(b.collapsedHiddenIds, {2, 3});
    });

    test('exposure-bias reference is the frame nearest 0 EV', () {
      final b = BracketGroups([
        _p(1, 0, bias: 0),
        _p(2, 1, bias: 3),
        _p(3, 2, bias: -3),
      ]);
      expect(b.referenceIds, {1});
    });

    test('folds RAW+JPEG siblings into the bracket without inflating size', () {
      // ids 1..3 are the RAWs; 11..13 their hidden JPEG siblings.
      final b = BracketGroups(
        triple(),
        siblings: const {
          1: [11],
          2: [12],
          3: [13],
        },
      );
      expect(b.memberIds, {1, 2, 3, 11, 12, 13});
      expect(b.groupOf(1), containsAll([1, 2, 3, 11, 12, 13]));
      // Badge count is the exposure count, not the doubled file count.
      expect(b.sizeOf(1), 3);
      // A sibling of a non-reference frame is hidden by collapse.
      expect(b.collapsedHiddenIds, containsAll([2, 3, 11, 12, 13]));
      expect(b.collapsedHiddenIds, isNot(contains(1)));
    });

    test('a lone frame reports size 1 and no bracket', () {
      final b = BracketGroups([_p(1, 0, shutter: 2.5)]);
      expect(b.bracketCount, 0);
      expect(b.sizeOf(1), 1);
      expect(b.groupOf(1), [1]);
      expect(b.isReference(1), isFalse);
    });
  });
}
