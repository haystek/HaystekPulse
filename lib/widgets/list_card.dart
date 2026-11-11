import 'package:flutter/material.dart';

import '../models/feedback_item.dart';
import '../models/pulse_rating.dart';

/// One suggestion or Weekly Pulse comment in a list (design S2):
/// a thin bar in the status colour, the status in small capitals and the
/// time, the message as the main text, then who sent it (admin) or what it
/// is (employee), and "Replied" when admin answered.
class FeedbackListCard extends StatelessWidget {
  const FeedbackListCard({
    super.key,
    required this.item,
    this.onTap,
    this.employeeView = false,
  });

  final FeedbackItem item;
  final VoidCallback? onTap;

  /// Employee's own list: no name line, shows Suggestion / Weekly Pulse.
  final bool employeeView;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _when(DateTime? d) {
    if (d == null) return '';
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      final m = d.minute.toString().padLeft(2, '0');
      return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
    }
    return '${d.day} ${_months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final color = FeedbackStatus.color(item.status);
    const soft = Color(0xFF9CA3AF);
    const green = Color(0xFF15803D);
    final rating = item.rating;
    final ratingText =
        !item.isFromBox && rating != null ? PulseRating.label(rating) : null;

    final Widget? who;
    if (employeeView) {
      who = ratingText == null
          ? null
          : Row(
              children: [
                const Icon(Icons.monitor_heart_outlined, size: 13, color: soft),
                const SizedBox(width: 4),
                Text(
                  ratingText,
                  style: t.bodySmall?.copyWith(fontSize: 12, color: soft),
                ),
              ],
            );
    } else {
      final name = (item.authorName ?? '').trim();
      final id = (item.authorEmployeeId ?? '').trim();
      final hidden = item.anonymous || name.isEmpty;
      who = Row(
        children: [
          if (hidden) ...[
            const Icon(Icons.lock_outline_rounded, size: 12, color: soft),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (hidden)
                    const TextSpan(text: 'Name hidden')
                  else ...[
                    TextSpan(
                      text: name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF374151),
                      ),
                    ),
                    if (id.isNotEmpty) TextSpan(text: ' · $id'),
                  ],
                  if (ratingText != null) TextSpan(text: ' · $ratingText'),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodySmall?.copyWith(fontSize: 12, color: soft),
            ),
          ),
        ],
      );
    }

    final card = Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFEEF0F4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            FeedbackStatus.label(item.status).toUpperCase(),
                            style: t.labelSmall?.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                              color: color,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _when(item.createdAt),
                            style: t.bodySmall?.copyWith(
                              fontSize: 12,
                              color: soft,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.text.trim().isNotEmpty
                            ? item.text.trim()
                            : (ratingText == null
                                ? ''
                                : employeeView
                                    ? 'You said $ratingText'
                                    : 'Rated $ratingText'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyLarge?.copyWith(
                          fontSize: 15.5,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF1F2937),
                        ),
                      ),
                      if (who != null || item.hasReply) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: who ?? const SizedBox.shrink()),
                          if (item.hasReply) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 12,
                              color: green,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              employeeView ? 'Admin replied' : 'Replied',
                              style: t.bodySmall?.copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: green,
                              ),
                            ),
                          ],
                        ],
                      ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!employeeView) return card;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: card,
    );
  }
}
