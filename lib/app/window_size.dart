import 'dart:math' as math;
import 'dart:ui';

/// The window size Cullimingo opens with before the user has sized it.
const Size kDefaultWindowSize = Size(1280, 800);

/// The smallest window the layout supports.
const Size kMinimumWindowSize = Size(960, 640);

/// Room left around a first-run window for the taskbar / Dock / menu bar and
/// the window's own title bar, in logical pixels.
const double _horizontalMargin = 32;
const double _verticalMargin = 112;

/// The first-run window size for a primary display of [display] logical
/// pixels: [kDefaultWindowSize], shrunk to fit with its title bar on screen
/// (a 1280×800 laptop at 200 % opened the window with its title bar above
/// the top edge), but never below [kMinimumWindowSize]. [display] null
/// (unknown) keeps the default. Pure, for tests.
Size firstRunWindowSize(Size? display) {
  if (display == null || display.isEmpty) return kDefaultWindowSize;
  return Size(
    math.max(
      kMinimumWindowSize.width,
      math.min(kDefaultWindowSize.width, display.width - _horizontalMargin),
    ),
    math.max(
      kMinimumWindowSize.height,
      math.min(kDefaultWindowSize.height, display.height - _verticalMargin),
    ),
  );
}
