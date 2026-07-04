import 'package:cullimingo/core/files/supported_files.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isVideoPath matches video extensions, case-insensitive', () {
    expect(isVideoPath('clip.mp4'), isTrue);
    expect(isVideoPath('CLIP.MOV'), isTrue);
    expect(isVideoPath('a.mts'), isTrue);
    expect(isVideoPath('a.jpg'), isFalse);
    expect(isVideoPath('a.arw'), isFalse);
  });

  test('isSupportedPhoto excludes videos', () {
    expect(isSupportedPhoto('a.arw'), isTrue);
    expect(isSupportedPhoto('a.jpg'), isTrue);
    expect(isSupportedPhoto('a.mp4'), isFalse);
  });

  test('isSupportedMedia covers photos and videos but not junk', () {
    expect(isSupportedMedia('a.arw'), isTrue);
    expect(isSupportedMedia('a.mp4'), isTrue);
    expect(isSupportedMedia('.DS_Store'), isFalse);
    expect(isSupportedMedia('notes.txt'), isFalse);
  });

  test('HEIF photo containers count as photos', () {
    expect(isSupportedPhoto('IMG.heic'), isTrue);
    expect(isSupportedPhoto('a.hif'), isTrue); // Sony HEIF
    expect(isSupportedPhoto('a.avif'), isTrue);
  });

  test('cinema / extra video containers are recognised', () {
    for (final name in ['a.braw', 'a.r3d', 'a.crm', 'a.webm', 'a.ts']) {
      expect(isVideoPath(name), isTrue, reason: name);
    }
  });

  test('isSidecarPath matches companion metadata files', () {
    expect(isSidecarPath('a.xmp'), isTrue);
    expect(isSidecarPath('a.THM'), isTrue);
    expect(isSidecarPath('a.aae'), isTrue);
    expect(isSidecarPath('a.jpg'), isFalse);
  });
}
