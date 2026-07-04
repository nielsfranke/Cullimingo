import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:flutter/material.dart';

/// The toolbar grid-size slider.
///
/// The thumb tracks the drag live, but the new width is **committed only when
/// the drag ends** ([onCommit]). Committing on every intermediate frame made a
/// slow zoom reflow the grid, re-anchor the scroll (a `jumpTo` per frame), and
/// re-decode every visible thumbnail dozens of times — which flickered and
/// jumped the grid. Now that all happens once, on release.
class GridZoomSlider extends StatefulWidget {
  /// Creates the slider.
  const GridZoomSlider({
    required this.value,
    required this.onCommit,
    super.key,
  });

  /// The committed cell width (from the provider), shown when not dragging.
  final double value;

  /// Called once, with the final width, when the drag ends.
  final ValueChanged<double> onCommit;

  @override
  State<GridZoomSlider> createState() => _GridZoomSliderState();
}

class _GridZoomSliderState extends State<GridZoomSlider> {
  // The live thumb position while dragging; null when settled (the thumb then
  // follows [widget.value]).
  double? _dragValue;

  @override
  void didUpdateWidget(GridZoomSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Once the committed width has propagated back through the provider, drop
    // the transient drag value so the thumb tracks [widget.value] again (and a
    // programmatic width change is reflected).
    if (_dragValue != null && widget.value == _dragValue) {
      _dragValue = null;
    }
  }

  @override
  Widget build(BuildContext context) => Slider(
    value: _dragValue ?? widget.value,
    min: GridCellWidth.min,
    max: GridCellWidth.max,
    onChanged: (v) => setState(() => _dragValue = v),
    onChangeEnd: (v) {
      // Hold the thumb at the released value until the provider catches up
      // (cleared in didUpdateWidget), then commit — one reflow, not dozens.
      setState(() => _dragValue = v);
      widget.onCommit(v);
    },
  );
}
