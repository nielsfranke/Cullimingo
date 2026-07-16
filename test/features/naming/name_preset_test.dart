import 'package:cullimingo/core/naming/rename_template.dart';
import 'package:cullimingo/features/naming/domain/name_element.dart';
import 'package:cullimingo/features/naming/domain/name_preset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NamePreset', () {
    test('combinedPattern joins folder and file with a slash', () {
      const preset = NamePreset(
        name: 'x',
        folderPattern: '{YYYY}/{MM}',
        filePattern: '{origname}',
      );
      expect(preset.combinedPattern, '{YYYY}/{MM}/{origname}');
    });

    test('combinedPattern is just the file when there is no folder', () {
      const preset = NamePreset(
        name: 'x',
        folderPattern: '',
        filePattern: '{origname}',
      );
      expect(preset.combinedPattern, '{origname}');
    });

    test('toTemplate carries the counter start into the engine', () {
      const preset = NamePreset(
        name: 'x',
        folderPattern: '',
        filePattern: '{seq:3}',
        counterStart: 10,
      );
      final path = preset.toTemplate().pathFor(
        RenameInput(
          capturedAt: DateTime(2026, 7, 2),
          originalName: 'a.jpg',
          sequence: 1,
        ),
      );
      expect(path, '010.jpg');
    });

    test('JSON round-trips', () {
      const preset = NamePreset(
        name: 'My scheme',
        folderPattern: '{YYYY}',
        filePattern: '{shoot}_{seq:4}',
        counterStart: 5,
      );
      final back = NamePreset.fromJson(preset.toJson());
      expect(back.name, preset.name);
      expect(back.folderPattern, preset.folderPattern);
      expect(back.filePattern, preset.filePattern);
      expect(back.counterStart, preset.counterStart);
      expect(back.builtIn, isFalse);
    });

    test('every built-in pattern is valid (no unknown tokens)', () {
      for (final preset in NamePreset.builtIns) {
        expect(
          preset.toTemplate().unknownTokens(),
          isEmpty,
          reason: preset.name,
        );
      }
    });
  });

  group('engineToDisplay / displayToEngine', () {
    test('rewrites engine tokens to friendly labels and back', () {
      const engine = '{shoot}_{seq:4}/{date:iso}';
      final display = engineToDisplay(engine);
      expect(display, '{Job name}_{Counter 4}/{Date (2026-07-02)}');
      expect(displayToEngine(display), engine);
    });

    test('free-typed literal text and unknown tokens pass through', () {
      expect(displayToEngine('my {Job name}-final'), 'my {shoot}-final');
      expect(engineToDisplay('my {shoot}-final'), 'my {Job name}-final');
      // An unknown token is left untouched (not a crash, not a rewrite).
      expect(displayToEngine('{Mystery}'), '{Mystery}');
    });

    test('every built-in pattern round-trips through the display layer', () {
      for (final p in NamePreset.builtIns) {
        expect(displayToEngine(engineToDisplay(p.filePattern)), p.filePattern);
        expect(
          displayToEngine(engineToDisplay(p.folderPattern)),
          p.folderPattern,
        );
      }
    });
  });

  group('name element catalog', () {
    test('every palette date format is a key the engine knows', () {
      for (final f in dateFormats) {
        final path = RenameTemplate('{date:${f.key}}').pathFor(
          RenameInput(
            capturedAt: DateTime(2026, 7, 2, 14, 30, 5),
            originalName: 'a.jpg',
            sequence: 1,
          ),
        );
        expect(path.contains('{'), isFalse, reason: f.key);
      }
    });
  });
}
