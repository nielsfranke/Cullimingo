import 'package:cullimingo/app/theme/tokens.dart';
import 'package:flutter/material.dart';

/// Severity of an app notification, driving its colour + default icon and
/// whether it auto-dismisses. Keep every user-facing message on one of these so
/// the whole app speaks with one visual voice.
enum NoticeKind {
  /// Neutral information (accent colour).
  info(AppColors.accent, Icons.info_outline),

  /// A completed action (green).
  success(AppColors.selection, Icons.check_circle_outline),

  /// A problem the user should notice (yellow).
  warning(AppColors.labelYellow, Icons.warning_amber_rounded);

  const NoticeKind(this.color, this.icon);

  /// The bar's accent colour.
  final Color color;

  /// The bar's default leading icon.
  final IconData icon;
}

/// A coloured bottom notice (e.g. a card was inserted, or the open folder
/// vanished) with optional inline actions.
class Notice {
  /// Creates a notice.
  const Notice({
    required this.kind,
    required this.message,
    required this.icon,
    this.actions = const [],
  });

  /// A plain notice using the kind's default icon (the common case).
  factory Notice.of(NoticeKind kind, String message) =>
      Notice(kind: kind, message: message, icon: kind.icon);

  /// The severity/kind.
  final NoticeKind kind;

  /// The message text.
  final String message;

  /// The leading icon.
  final IconData icon;

  /// Optional inline action buttons.
  final List<({String label, VoidCallback onTap})> actions;

  /// The kind's colour (single source for the bar's accent).
  Color get color => kind.color;
}

/// Renders a [Notice] as a slim coloured bar above the export bar.
class NoticeBar extends StatelessWidget {
  /// Creates the bar for [notice].
  const NoticeBar({required this.notice, required this.onDismiss, super.key});

  /// The notice to render.
  final Notice notice;

  /// Called when the user dismisses the bar.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: notice.color.withValues(alpha: 0.15),
        border: Border(top: BorderSide(color: notice.color)),
      ),
      child: Row(
        children: [
          Icon(notice.icon, size: 18, color: notice.color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              notice.message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
          for (final action in notice.actions)
            TextButton(onPressed: action.onTap, child: Text(action.label)),
          IconButton(
            onPressed: onDismiss,
            tooltip: 'Dismiss',
            iconSize: 18,
            icon: const Icon(Icons.close, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
