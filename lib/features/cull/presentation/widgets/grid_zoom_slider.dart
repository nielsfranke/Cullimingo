import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:flutter/material.dart';

/// The toolbar grid-size slider.
///
/// The grid resizes **live** as you drag ([onChanged] fires every frame), but
/// the two expensive reactions are deferred to the drag boundaries:
/// [onZoomStart] freezes the thumbnail decode resolution and captures a scroll
/// anchor; [onZoomEnd] re-decodes once and restores the anchor. Doing those per
/// drag-frame (as it once did) re-decoded every visible thumbnail and issued a
/// scroll `jumpTo` on every frame — which flickered and jumped the grid.
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
