import 'package:flutter/material.dart';

import '../models/feedback_item.dart';
import '../models/pulse_rating.dart';

/// One suggestion or Weekly Pulse comment in a list.
///
/// ADMIN: design 3a "Ticket" – grey top strip with who sent it (👤 name ·
/// ID, or 🔒 Anonymous), time and arrow; the message; then status and the
/// mood chip at the bottom. Employee screens use employee_inbox.dart.
///
/// Older employee layout (design I "Inbox"), kept for employeeView:
///
///   ┃ shiva                                   1:20 PM
///   ┃ test                                          ›
///   ┃ ● New · ✓ Replied                          OKAY
///
/// A thin line on the left in the mood colour (or the status colour for a
/// suggestion), the name in bold, the message, then the mood (or status)
/// word underlined in its colour. Time and arrow on the right. No rounded box:
/// rows are split by a thin line, like an email inbox.
class FeedbackListCard extends StatelessWidget {
  const FeedbackListCard({
    super.key,
    required this.item,
    this.onTap,
    this.employeeView = false,
  });

  final FeedbackItem item;
  final VoidCallback? onTap;

  /// Employee's own list: shows how it was sent (Anonymous / their name).
  final bool employeeView;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const _ink = Color(0xFF111827);
  static const _body = Color(0xFF1F2937);
  static const _soft = Color(0xCC0E1A3A);
  static const _green = Color(0xFF15803D);

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
  Widget build(BuildContext context) =>
      employeeView ? _inbox(context) : _ticket(context);

  /// Admin: design 3a "Ticket".
  Widget _ticket(BuildContext context) {
    final statusColor = FeedbackStatus.color(item.status);
    final statusText = FeedbackStatus.label(item.status);
    final rating = !item.isFromBox ? item.rating : null;
    final ratingText = rating != null ? PulseRating.label(rating) : null;
    final moodColor = rating != null ? PulseRating.color(rating) : null;

    final name = (item.authorName ?? '').trim();
    final hidden = item.anonymous || name.isEmpty;
    const grey = Color(0xFF5B6478);

    final text = item.text.trim().isNotEmpty
        ? item.text.trim()
        : (ratingText == null ? '' : 'Rated $ratingText');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFDDE2EB), width: 1.2),
        ),
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top strip: who sent it, time, arrow.
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                decoration: const BoxDecoration(
                  color: Color(0xFFF6F7FB),
                  border: Border(bottom: BorderSide(color: Color(0xFFEEF1F6))),
                ),
                child: Row(
                  children: [
                    Icon(
                      hidden ? Icons.lock_outline_rounded : Icons.person_rounded,
                      size: 17,
                      color: hidden ? grey : _ink,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: hidden ? 'Anonymous' : name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                                color: hidden ? grey : _ink,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _when(item.createdAt),
                      style: const TextStyle(
                        fontSize: 13,
                        letterSpacing: 0,
                        color: _soft,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: _soft,
                    ),
                  ],
                ),
              ),
              // The message.
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 14, 0),
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.42,
                    letterSpacing: 0,
                    color: _body,
                  ),
                ),
              ),
              // Status (+ Replied) on the left, mood chip on the right.
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: 4,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0,
                              color: statusColor,
                            ),
                          ),
                          if (item.hasReply) ...[
                            const Text(
                              '  ·  ',
                              style: TextStyle(fontSize: 13, color: _soft),
                            ),
                            const Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: _green,
                            ),
                            const SizedBox(width: 3),
                            const Text(
                              'Replied',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                                color: _green,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (ratingText != null && moodColor != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: moodColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          ratingText.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: moodColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Older inbox layout (employeeView only).
  Widget _inbox(BuildContext context) {
    final statusColor = FeedbackStatus.color(item.status);
    final statusText = FeedbackStatus.label(item.status);
    final rating = !item.isFromBox ? item.rating : null;
    final ratingText = rating != null ? PulseRating.label(rating) : null;

    // Weekly Pulse: the mood. Suggestion: the status.
    final tagColor = rating != null ? PulseRating.color(rating) : statusColor;
    final tagText = (ratingText ?? statusText).toUpperCase();

    // Who sent it.
    final String who;
    final bool hidden;
    if (employeeView) {
      final n = (item.authorName ?? '').trim();
      hidden = item.anonymous;
      who = item.anonymous ? 'Anonymous' : (n.isEmpty ? 'With your name' : n);
    } else {
      final name = (item.authorName ?? '').trim();
      final id = (item.authorEmployeeId ?? '').trim();
      hidden = item.anonymous || name.isEmpty;
      who = hidden ? 'Anonymous' : (id.isEmpty ? name : '$name · $id');
    }

    final text = item.text.trim().isNotEmpty
        ? item.text.trim()
        : (ratingText == null
              ? ''
              : employeeView
              ? 'You said $ratingText'
              : 'Rated $ratingText');

    final row = Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFEEF1F6))),
          ),
          padding: const EdgeInsets.fromLTRB(2, 12, 2, 13),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Thin colour line.
                Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: tagColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                // Name, message, status.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (hidden) ...[
                            const Icon(
                              Icons.lock_outline_rounded,
                              size: 14,
                              color: _ink,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              who,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                                color: _ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.42,
                          letterSpacing: 0,
                          color: _body,
                        ),
                      ),
                      // Status in its colour, and Replied.
                      const SizedBox(height: 6),
                      // Wrap: goes to a second line on small phones,
                      // never cut.
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: 4,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0,
                              color: statusColor,
                            ),
                          ),
                          if (item.hasReply) ...[
                            const Text(
                              '  ·  ',
                              style: TextStyle(fontSize: 12.5, color: _soft),
                            ),
                            const Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: _green,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              employeeView ? 'Admin replied' : 'Replied',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                                color: _green,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Right side: time on top, arrow in the middle, and the
                // mood word (Weekly Pulse) in its colour at the bottom.
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _when(item.createdAt),
                      style: const TextStyle(
                        fontSize: 12.5,
                        letterSpacing: 0,
                        color: _soft,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: _soft,
                    ),
                    if (ratingText != null)
                      Text(
                        tagText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: tagColor,
                        ),
                      )
                    else
                      const SizedBox(height: 14),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!employeeView) return row;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: row,
    );
  }
}
