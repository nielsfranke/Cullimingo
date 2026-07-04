import 'package:cullimingo/features/ingest/domain/rename_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final when = DateTime(2026, 6, 24, 9, 8, 7);

  RenameInput input({
    String name = 'DSC0001.ARW',
    int seq = 1,
    String? camera,
    String shoot = '',
  }) => RenameInput(
    capturedAt: when,
    originalName: name,
    sequence: seq,
    camera: camera,
    shoot: shoot,
  );

  group('RenameTemplate.pathFor', () {
    test('dated-shoot preset keeps the original name and appends the ext', () {
      final path = RenameTemplate.datedShoot.pathFor(input(shoot: 'Klima'));
      expect(path, '2026/2026-06-24_Klima/DSC0001.ARW');
    });

    test('date/time tokens pad to two/four digits', () {
      const t = RenameTemplate('{YYYY}{MM}{DD}_{HHmmss}');
      expect(t.pathFor(input()), '20260624_090807.ARW');
    });

    test('seq token zero-pads to the configured width', () {
      const t = RenameTemplate('{YYYY}_{seq}', sequenceWidth: 5);
      expect(t.pathFor(input(seq: 42)), '2026_00042.ARW');
    });

    test('{seq:N} sets the width per-token, overriding sequenceWidth', () {
      const t = RenameTemplate('{seq:3}_{origname}', sequenceWidth: 5);
      expect(t.pathFor(input(seq: 7)), '007_DSC0001.ARW');
    });

    test('counterStart shifts the counter value', () {
      const t = RenameTemplate('{seq:4}', counterStart: 100);
      expect(t.pathFor(input()), '0100.ARW');
      expect(t.pathFor(input(seq: 3)), '0102.ARW');
    });

    test('{date:key} renders each named format', () {
      String date(String key) =>
          RenameTemplate('{date:$key}').pathFor(input(name: 'x.jpg'));
      expect(date('iso'), '2026-06-24.jpg');
      expect(date('dmyDots'), '24.06.2026.jpg');
      expect(date('dmyDotsShort'), '24.06.26.jpg');
      expect(date('compact'), '20260624.jpg');
      expect(date('year'), '2026.jpg');
      expect(date('yearMonth'), '2026-06.jpg');
      expect(date('monthName'), 'Jun.jpg');
      expect(date('monthNameFull'), 'June.jpg');
      expect(date('monthDayYear'), 'Jun 24 2026.jpg');
      // 2026-06-24 is a Wednesday.
      expect(date('weekday'), 'Wed.jpg');
      expect(date('time'), '090807.jpg');
    });

    test('an unknown date key stays literal and is reported', () {
      const t = RenameTemplate('{date:bogus}_{origname}');
      expect(t.unknownTokens(), ['date:bogus']);
      // Left literal in substitution; the illegal ':' is then sanitised to '_'.
      expect(t.pathFor(input()), '{date_bogus}_DSC0001.ARW');
    });

    test('a bad {seq:N} width is reported and left literal', () {
      const t = RenameTemplate('{seq:x}');
      expect(t.unknownTokens(), ['seq:x']);
    });

    test('valid parametrized tokens report no unknowns', () {
      const t = RenameTemplate('{date:monthDayYear}/{seq:2}_{origname}');
      expect(t.unknownTokens(), isEmpty);
    });

    test('preserves the source extension exactly (case included)', () {
      const t = RenameTemplate.keepNames;
      expect(t.pathFor(input(name: 'a.JPEG')), 'a.JPEG');
      expect(t.pathFor(input(name: 'b.cr3')), 'b.cr3');
    });

    test('camera token is used verbatim when valid', () {
      const t = RenameTemplate('{camera}/{origname}');
      expect(
        t.pathFor(input(camera: 'Sony ILCE-7M4')),
        'Sony ILCE-7M4/DSC0001.ARW',
      );
    });

    test('sanitises path separators and illegal chars inside token values', () {
      const t = RenameTemplate('{shoot}/{origname}');
      // The shoot name must not be able to inject sub-folders or illegal chars.
      final path = t.pathFor(input(shoot: 'a/b:c'));
      expect(path, 'a_b_c/DSC0001.ARW');
    });

    test('drops empty segments (e.g. a missing camera value)', () {
      const t = RenameTemplate('{camera}/{YYYY}/{origname}');
      expect(t.pathFor(input()), '2026/DSC0001.ARW');
    });

    test('unknown tokens are reported and left literal', () {
      const t = RenameTemplate('{YYYY}/{bogus}_{origname}');
      expect(t.unknownTokens(), ['bogus']);
      expect(t.pathFor(input()), '2026/{bogus}_DSC0001.ARW');
    });

    test('valid pattern reports no unknown tokens', () {
      expect(RenameTemplate.datedShoot.unknownTokens(), isEmpty);
      expect(RenameTemplate.timestamped.unknownTokens(), isEmpty);
      expect(RenameTemplate.byMonth.unknownTokens(), isEmpty);
    });
  });
}
