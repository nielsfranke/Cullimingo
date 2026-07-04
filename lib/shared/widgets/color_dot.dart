import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter/material.dart';

/// A small filled circle for a [ColorLabel] (nothing for [ColorLabel.none]).
class ColorDot extends StatelessWidget {
  /// Creates a colour-label dot.
  const ColorDot({required this.label, this.size = 11, super.key});

  /// The colour label to show.
  final ColorLabel label;

  /// Diameter in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = label.color;
    if (color == null) return const SizedBox.shrink();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black.withValues(alpha: 0.35)),
      ),
    );
  }
}
