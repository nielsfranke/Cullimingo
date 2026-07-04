import 'package:cullimingo/features/metadata/domain/code_replacements.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const table = CodeReplacements(
    codes: {
      'ff': ['staff', 'Jane Smith', 'Wilson Oluo'],
      'lbj': ['LeBron James'],
    },
  );

  group('expandCodes', () {
    test('expands a code to its default (first) replacement', () {
      expect(expandCodes('shot by =ff=', table), 'shot by staff');
      expect(expandCodes('=lbj= drives', table), 'LeBron James drives');
    });

    test('#n selects the nth alternate (1-based)', () {
      expect(expandCodes('=ff#2=', table), 'Jane Smith');
      expect(expandCodes('=ff#3=', table), 'Wilson Oluo');
    });

    test('unknown code or out-of-range alternate is left literal', () {
      expect(expandCodes('=nope=', table), '=nope=');
      expect(expandCodes('=ff#9=', table), '=ff#9=');
    });

    test('multiple codes in one string all expand', () {
      expect(
        expandCodes('=ff= and =ff#2=', table),
        'staff and Jane Smith',
      );
    });

    test('empty table is a passthrough', () {
      expect(expandCodes('=ff=', const CodeReplacements()), '=ff=');
    });

    test('honours a custom delimiter', () {
      const pct = CodeReplacements(
        delimiter: '%',
        codes: {
          'yr': ['2026'],
        },
      );
      expect(expandCodes('© %yr% Jane', pct), '© 2026 Jane');
      // The default '=' is now inert.
      expect(expandCodes('=yr=', pct), '=yr=');
    });
  });

  group('fromTabText', () {
    test('parses code + tab-separated replacements', () {
      final t = CodeReplacements.fromTabText(
        'ff\tstaff\tJane Smith\n'
        'lbj\tLeBron James\n'
        '\n' // blank line skipped
        'bad\n', // no replacement → skipped
      );
      expect(t.codes['ff'], ['staff', 'Jane Smith']);
      expect(t.codes['lbj'], ['LeBron James']);
      expect(t.codes.containsKey('bad'), isFalse);
    });
  });

  group('JSON', () {
    test('round-trips delimiter and codes', () {
      final back = CodeReplacements.fromJson(table.toJson());
      expect(back.delimiter, '=');
      expect(back.codes['ff'], ['staff', 'Jane Smith', 'Wilson Oluo']);
    });

    test('tolerates a malformed map', () {
      final back = CodeReplacements.fromJson({'codes': 'nonsense'});
      expect(back.isEmpty, isTrue);
      expect(back.delimiter, '=');
    });
  });
}
