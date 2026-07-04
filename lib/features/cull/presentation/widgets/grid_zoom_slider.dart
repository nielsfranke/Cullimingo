import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:flutter/material.dart';

/// The toolbar grid-size slider.
///
/// The grid resizes **live** as you drag ([onChanged] fires every frame). The
/// thumbnail re-decode is deferred to the drag boundaries — [onZoomStart]
/// freezes the decode resolution so cells just scale while dragging, and
/// [onZoomEnd] re-decodes once at the settled size — while the scroll is
/// re-anchored around the photo under the eye synchronously on each change. The
/// old flicker/jump came from re-decoding every frame and re-anchoring a frame
/// late; both are addressed here.
class GridZoomSlider extends StatelessWidget {
  /// Creates the slider.
  const GridZoomSlider({
    required this.value,
    required this.onChanged,
    required this.onZoomStart,
    required this.onZoomEnd,
    super.key,
  });

  /// The current cell width (from the provider).
  final double value;

  /// Called with the new width on every drag frame — resizes the grid live.
  final ValueChanged<double> onChanged;

  /// Called once when the drag begins.
  final VoidCallback onZoomStart;

  /// Called once when the drag ends.
  final VoidCallback onZoomEnd;

  @override
  Widget build(BuildContext context) => Slider(
    value: value.clamp(GridCellWidth.min, GridCellWidth.max),
    min: GridCellWidth.min,
    max: GridCellWidth.max,
    onChangeStart: (_) => onZoomStart(),
    onChanged: onChanged,
    onChangeEnd: (v) {
      onChanged(v);
      onZoomEnd();
    },
  );
}
