import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/features/metadata/domain/iptc_editor_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iptcEditorInit', () {
    test('single target prefills every field, nothing mixed', () {
      final init = iptcEditorInit(const [
        IptcCore(caption: 'Hello', credit: 'AP'),
      ]);
      expect(init[IptcField.caption]!.value, 'Hello');
      expect(init[IptcField.caption]!.mixed, isFalse);
      expect(init[IptcField.credit]!.value, 'AP');
      expect(init[IptcField.headline]!.value, '');
    });

    test('a shared value across a batch is prefilled', () {
      final init = iptcEditorInit(const [
        IptcCore(credit: 'AP', caption: 'One'),
        IptcCore(credit: 'AP', caption: 'Two'),
      ]);
      expect(init[IptcField.credit]!.value, 'AP');
      expect(init[IptcField.credit]!.mixed, isFalse);
    });

    test('a field the targets disagree on is empty and mixed', () {
      final init = iptcEditorInit(const [
        IptcCore(caption: 'One', credit: 'AP'),
        IptcCore(caption: 'Two', credit: 'AP'),
      ]);
      expect(init[IptcField.caption]!.value, '');
      expect(init[IptcField.caption]!.mixed, isTrue);
      // credit still agrees.
      expect(init[IptcField.credit]!.mixed, isFalse);
    });
  });

  group('iptcEditorChanges', () {
    test('only fields whose text changed are returned', () {
      final init = iptcEditorInit(const [
        IptcCore(caption: 'Old', credit: 'AP'),
      ]);
      final changes = iptcEditorChanges(
        init,
        {
          for (final f in IptcField.values) f: init[f]!.value,
        }..[IptcField.caption] = 'New',
      );

      expect(changes, {IptcField.caption: 'New'});
    });

    test('untouched mixed fields are not written (stay per-photo)', () {
      final init = iptcEditorInit(const [
        IptcCore(caption: 'One'),
        IptcCore(caption: 'Two'),
      ]);
      // The user only fills the (mixed, empty) credit field.
      final current = {for (final f in IptcField.values) f: init[f]!.value}
        ..[IptcField.credit] = 'Reuters';

      final changes = iptcEditorChanges(init, current);
      expect(changes.containsKey(IptcField.caption), isFalse);
      expect(changes[IptcField.credit], 'Reuters');
    });

    test('clearing a field to empty is a change', () {
      final init = iptcEditorInit(const [IptcCore(credit: 'AP')]);
      final current = {for (final f in IptcField.values) f: init[f]!.value}
        ..[IptcField.credit] = '';

      expect(iptcEditorChanges(init, current), {IptcField.credit: ''});
    });
  });

  group('IptcCore.withOverrides', () {
    test('applies changes and leaves untouched fields intact', () {
      const base = IptcCore(caption: 'Cap', creator: 'Jane', credit: 'AP');
      final out = base.withOverrides({
        IptcField.credit: 'Reuters',
        IptcField.city: 'Munich',
      });
      expect(out.caption, 'Cap'); // untouched
      expect(out.creator, 'Jane'); // untouched
      expect(out.credit, 'Reuters'); // changed
      expect(out.city, 'Munich'); // added
    });

    test('an empty override clears the field', () {
      const base = IptcCore(credit: 'AP');
      expect(base.withOverrides({IptcField.credit: ''}).credit, '');
    });
  });
}
