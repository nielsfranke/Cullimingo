import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter/material.dart';

/// Pick/reject badge shown top-left on a cell (nothing for [PickFlag.none]).
class FlagBadge extends StatelessWidget {
  /// Creates a flag badge.
  const FlagBadge({required this.flag, this.size = 18, super.key});

  /// The pick/reject flag to show.
  final PickFlag flag;

  /// Badge diameter in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    return switch (flag) {
      PickFlag.none => const SizedBox.shrink(),
      PickFlag.pick => _badge(Icons.check_rounded, AppColors.selection),
      PickFlag.reject => _badge(Icons.close_rounded, AppColors.labelRed),
    };
  }

  Widget _badge(IconData icon, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, size: size * 0.72, color: Colors.white),
    );
  }
}
