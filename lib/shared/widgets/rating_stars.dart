import 'package:cullimingo/app/theme/tokens.dart';
import 'package:flutter/material.dart';

/// Compact rating overlay: shows [rating] gold stars (nothing when 0), as in
/// the Aftershoot cell (`BUILD_PLAN.md` §7).
class RatingStars extends StatelessWidget {
  /// Creates a rating overlay.
  const RatingStars({required this.rating, this.size = 12, super.key});

  /// Star rating 0–5.
  final int rating;

  /// Icon size in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    if (rating <= 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rating.clamp(0, 5); i++)
          Icon(Icons.star_rounded, size: size, color: AppColors.ratingGold),
      ],
    );
  }
}
