import 'package:flutter/material.dart';

import '../models/feedback_item.dart';
import '../models/pulse_rating.dart';
import '../theme/app_theme.dart';

/// Small pieces shared by the management screens.

/// The status label, for example "Under Review".
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    Color background;
    Color foreground;
    switch (status) {
      case FeedbackStatus.implemented:
        background = AppColors.blueTint;
        foreground = AppColors.blueDeep;
      case FeedbackStatus.newItem:
        background = const Color(0xFFFBEBC4);
        foreground = const Color(0xFF6B4A00);
      default:
        background = const Color(0xFFE8EAEE);
        foreground = const Color(0xFF334155);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        FeedbackStatus.label(status),
        style: TextStyle(
          color: foreground,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// "Weekly Pulse" or "Suggestion Box".
class SourceTag extends StatelessWidget {
  const SourceTag({super.key, required this.item});

  final FeedbackItem item;

  @override
  Widget build(BuildContext context) {
    final box = item.isFromBox;
    return Text(
      box ? 'Suggestion Box' : 'Weekly Pulse',
      style: const TextStyle(color: AppColors.muted, fontSize: 14),
    );
  }
}

/// The face for a Weekly Pulse rating, or the box for a suggestion.
class FeedbackIcon extends StatelessWidget {
  const FeedbackIcon({super.key, required this.item, this.size = 32});

  final FeedbackItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final rating = item.rating;
    if (item.isFromBox || rating == null) {
      return Icon(Icons.inventory_2, size: size, color: AppColors.green);
    }
    return Icon(
      PulseRating.icon(rating),
      size: size,
      color: PulseRating.color(rating),
    );
  }
}

/// The employee's name, or "Anonymous" with a lock.
class AuthorLine extends StatelessWidget {
  const AuthorLine({super.key, required this.item});

  final FeedbackItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = item.authorName ?? '';
    final id = item.authorEmployeeId ?? '';
    final label = item.anonymous
        ? 'Anonymous'
        : (id.isEmpty ? name : '$name ($id)');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          item.anonymous ? Icons.lock : Icons.person,
          size: 15,
          color: AppColors.muted,
        ),
        const SizedBox(width: 5),
        Flexible(child: Text(label, style: theme.textTheme.bodySmall)),
      ],
    );
  }
}
