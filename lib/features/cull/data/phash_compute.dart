import 'dart:typed_data';

import 'package:cullimingo/features/cull/domain/perceptual_hash.dart';
import 'package:image/image.dart' as img;

/// Decodes [bytes] (a cached thumbnail JPEG), reduces it to a 9×8 grayscale and
/// returns its [dHashBits], or null when it can't be decoded. CPU-bound — run
/// from a background isolate (Rule 2). Never throws (a malformed image just
/// yields null, so one bad file can't abort a whole "find similar" pass).
int? computeDHash(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    // Average (box) downscale, NOT nearest — sampling 72 points from a 1024px
    // image with nearest-neighbour is essentially random, so near-duplicates
    // would hash far apart. Averaging makes the 9×8 represent the whole frame.
    final small = img.copyResize(
      decoded,
      width: 9,
      height: 8,
      interpolation: img.Interpolation.average,
    );
    final gray = <int>[
      for (var y = 0; y < 8; y++)
        for (var x = 0; x < 9; x++) small.getPixel(x, y).luminance.round(),
    ];
    return dHashBits(gray);
  } on Object {
    return null;
  }
}

/// Hashes a batch of thumbnail byte arrays ([computeDHash] each). A top-level
/// function so it can be handed to `compute` without a closure that might
/// capture unsendable state (e.g. a Timer on the calling widget's State).
List<int?> hashThumbnails(List<Uint8List> thumbnails) => [
  for (final bytes in thumbnails) computeDHash(bytes),
];
