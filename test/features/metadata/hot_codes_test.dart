import 'package:cullimingo/features/metadata/domain/hot_codes.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const table = HotCodes(
    codes: {
      'arena': {
        IptcField.location: 'Allianz Arena',
        IptcField.city: 'München',
        IptcField.state: 'Bayern',
        IptcField.country: 'Germany',
      },
      'staff': {IptcField.creator: 'Jane Doe', IptcField.credit: 'Wire'},
    },
  );

  test('JSON round-trip; unknown field names are skipped', () {
    final back = HotCodes.fromJson(table.toJson());
    expect(back.codes, table.codes);

    final tolerant = HotCodes.fromJson({
      'codes': {
        'x': {'city': 'Bonn', 'bogusField': 'dropped', 'credit': 7},
      },
    });
    expect(tolerant.codes, {
      'x': {IptcField.city: 'Bonn'},
    });
  });

  test('a matched token is stripped and its fields returned', () {
    final out = expandHotCodes(
      '=arena= after the whistle',
      delimiter: '=',
      hotCodes: table,
    );
    expect(out!.text, ' after the whistle');
    expect(out.fields[IptcField.city], 'München');
    expect(out.fields[IptcField.country], 'Germany');
  });

  test('multiple tokens merge; later wins on overlap', () {
    const overlapping = HotCodes(
      codes: {
        'a': {IptcField.city: 'One', IptcField.state: 'S'},
        'b': {IptcField.city: 'Two'},
      },
    );
    final out = expandHotCodes('=a==b=', delimiter: '=', hotCodes: overlapping);
    expect(out!.text, isEmpty);
    expect(out.fields, {IptcField.city: 'Two', IptcField.state: 'S'});
  });

  test('unmatched tokens are left for the text pass; no match → null', () {
    final out = expandHotCodes(
      '=arena= shot by =ff=',
      delimiter: '=',
      hotCodes: table,
    );
    expect(out!.text, ' shot by =ff='); // =ff= is not a hot code

    expect(
      expandHotCodes('=ff= only', delimiter: '=', hotCodes: table),
      isNull,
    );
    expect(
      expandHotCodes('=arena=', delimiter: '#', hotCodes: table),
      isNull, // wrong delimiter
    );
  });
}
