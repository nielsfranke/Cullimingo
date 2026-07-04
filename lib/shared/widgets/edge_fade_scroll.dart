import 'package:flutter/material.dart';

/// Wraps a horizontally scrollable child (built via [builder] with the
/// supplied controller) and softly fades whichever edge still has off-screen
/// content, so a half-visible item reads as "scroll for more" instead of being
/// bluntly clipped. The fade appears only on the overflowing side(s): none when
/// everything fits, right-only at the start, both when scrolled to the middle.
class EdgeFadeScroll extends StatefulWidget {
  /// Creates a fading scroll wrapper. [builder] must return a scroll view that
  /// uses the passed [ScrollController].
  const EdgeFadeScroll({
    required this.builder,
    this.fadeExtent = 24,
    super.key,
  });

  /// Builds the scrollable child with the controller it must attach to.
  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  /// How many logical pixels each overflowing edge fades over.
  final double fadeExtent;

  @override
  State<EdgeFadeScroll> createState() => _EdgeFadeScrollState();
}

class _EdgeFadeScrollState extends State<EdgeFadeScroll> {
  final ScrollController _controller = ScrollController();

  // How far (0..fadeExtent) to fade the leading (left) and trailing (right)
  // edges, derived from the current scroll position and content overflow.
  double _startFade = 0;
  double _endFade = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_update);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_update)
      ..dispose();
    super.dispose();
  }

  void _update() {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final start = (pos.pixels - pos.minScrollExtent).clamp(
      0.0,
      widget.fadeExtent,
    );
    final end = (pos.maxScrollExtent - pos.pixels).clamp(
      0.0,
      widget.fadeExtent,
    );
    if (start != _startFade || end != _endFade) {
      setState(() {
        _startFade = start;
        _endFade = end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Re-evaluate after layout so a window resize (which changes the content's
    // maxScrollExtent without a scroll event) updates the edge fades too.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _update();
    });

    final child = widget.builder(context, _controller);
    if (_startFade == 0 && _endFade == 0) return child;

    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final width = rect.width;
        final startFrac = (_startFade / width).clamp(0.0, 1.0);
        // Keep the gradient stops monotonic even when the viewport is narrower
        // than both fades combined (they'd otherwise cross and assert).
        final endFrac = (1 - _endFade / width).clamp(startFrac, 1.0);
        return LinearGradient(
          colors: const [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0, startFrac, endFrac, 1],
        ).createShader(rect);
      },
      child: child,
    );
  }
}
