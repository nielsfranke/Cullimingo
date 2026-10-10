import 'dart:io';

import 'package:cullimingo/core/files/trash_fallback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory shoot;

  String at(String name) => p.join(shoot.path, name);
  String rejected(String name) => p.join(shoot.path, kRejectedFolderName, name);
  void write(String path, [String content = 'x']) =>
      (File(path)..parent.createSync(recursive: true)).writeAsStringSync(
        content,
      );

  setUp(() => shoot = Directory.systemTemp.createTempSync('cm_fallback'));
  tearDown(() => shoot.deleteSync(recursive: true));

  group('moveIntoRejectedFolder', () {
    test('moves the photo and its sidecar into _Rejected beside it', () async {
      write(at('DSC1.ARW'), 'raw');
      write(at('DSC1.xmp'), 'marks');

      final failed = await moveIntoRejectedFolder([
        (photo: at('DSC1.ARW'), sidecar: at('DSC1.xmp')),
      ]);

      expect(failed, isEmpty);
      expect(File(at('DSC1.ARW')).existsSync(), isFalse);
      expect(File(at('DSC1.xmp')).existsSync(), isFalse);
      expect(File(rejected('DSC1.ARW')).readAsStringSync(), 'raw');
      expect(File(rejected('DSC1.xmp')).readAsStringSync(), 'marks');
    });

    test(
      'never replaces: a taken name gets a suffix, sidecar following',
      () async {
        write(rejected('DSC1.ARW'), 'older');
        write(rejected('DSC1.xmp'), 'older marks');
        write(at('DSC1.ARW'), 'raw');
        write(at('DSC1.xmp'), 'marks');
        write(at('DSC1.JPG'), 'jpeg');
        write(at('DSC1.JPG.xmp'), 'jpeg marks');

        final failed = await moveIntoRejectedFolder([
          (photo: at('DSC1.ARW'), sidecar: at('DSC1.xmp')),
          (photo: at('DSC1.JPG'), sidecar: at('DSC1.JPG.xmp')),
        ]);

        expect(failed, isEmpty);
        expect(File(rejected('DSC1.ARW')).readAsStringSync(), 'older');
        expect(File(rejected('DSC1.xmp')).readAsStringSync(), 'older marks');
        expect(File(rejected('DSC1 (2).ARW')).readAsStringSync(), 'raw');
        expect(File(rejected('DSC1 (2).xmp')).readAsStringSync(), 'marks');
        // The JPEG's own name is free; its per-file sidecar keeps the form.
        expect(File(rejected('DSC1.JPG')).readAsStringSync(), 'jpeg');
        expect(
          File(rejected('DSC1.JPG.xmp')).readAsStringSync(),
          'jpeg marks',
        );
      },
    );

    test('a photo without a sidecar moves alone', () async {
      write(at('IMG_2.HEIC'));

      final failed = await moveIntoRejectedFolder([
        (photo: at('IMG_2.HEIC'), sidecar: at('IMG_2.xmp')),
      ]);

      expect(failed, isEmpty);
      expect(File(rejected('IMG_2.HEIC')).existsSync(), isTrue);
      expect(File(rejected('IMG_2.xmp')).existsSync(), isFalse);
    });

    test('a photo that is already gone counts as done', () async {
      final failed = await moveIntoRejectedFolder([
        (photo: at('missing.ARW'), sidecar: at('missing.xmp')),
      ]);
      expect(failed, isEmpty);
    });
  });

  group('deletePermanently', () {
    test('deletes the photo and its sidecar', () async {
      write(at('DSC1.ARW'));
      write(at('DSC1.xmp'));
      write(at('DSC2.ARW'));

      final failed = await deletePermanently([
        (photo: at('DSC1.ARW'), sidecar: at('DSC1.xmp')),
        (photo: at('gone.ARW'), sidecar: at('gone.xmp')),
      ]);

      expect(failed, isEmpty);
      expect(shoot.listSync().map((e) => p.basename(e.path)), ['DSC2.ARW']);
    });
  });
}
