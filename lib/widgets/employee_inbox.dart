import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/feedback_item.dart';

// EMPLOYEE screens only (Home "Your feedback" and My Feedback).
// Admin uses list_card.dart – keep the two separate.

const _ink = Color(0xFF111827);
const _soft = Color(0xCC0E1A3A);
const _green = Color(0xFF15803D);

TextStyle _t(double size, {FontWeight w = FontWeight.w400, Color c = _soft, double? h}) =>
    GoogleFonts.inter(fontSize: size, fontWeight: w, color: c, height: h, letterSpacing: 0);

/// One white panel with rounded corners; rows inside are split by thin
/// lines (design A "Inbox").
class EmployeeInboxPanel extends StatelessWidget {
  const EmployeeInboxPanel({
    super.key,
    required this.children,
    this.margin = EdgeInsets.zero,
  });

  final List<Widget> children;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFD9DFEA), width: 1.5),
        ),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                const Divider(height: 1, thickness: 1, color: Color(0xFFEEF1F6)),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// One row:
///   ┃ 💡 Suggestion                         ● Planned
///   ┃ Can we have a water dispenser on the 3rd floor…
///   ┃ 🔒 Anonymous · 14 Nov
///   ┃ ✓ Admin replied
class EmployeeInboxRow extends StatelessWidget {
  const EmployeeInboxRow({
    super.key,
    required this.isBox,
    required this.title,
    required this.sub,
    this.status,
    this.hasReply = false,
    this.anonymous,
    this.sentName,
    this.barColor,
    this.titleColor,
    this.onTap,
  });

  /// true = Suggestion, false = Weekly Pulse.
  final bool isBox;
  final String title;

  /// Date (and for Weekly Pulse "You said Good").
  final String sub;
  final String? status;
  final bool hasReply;

  /// null = don't show how it was sent.
  final bool? anonymous;
  final String? sentName;

  /// Colour of the thin line. Default: the status colour.
  final Color? barColor;
  final Color? titleColor;
  final VoidCallback? onTap;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// "16 Nov" (this year) or "16 Nov 2025".
  static String shortDate(DateTime? d) {
    if (d == null) return '';
    final s = '${d.day} ${_months[d.month - 1]}';
    return d.year == DateTime.now().year ? s : '$s ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final st = status;
    final color = barColor ??
        (st != null ? FeedbackStatus.color(st) : const Color(0xFF2F55D4));
    final a = anonymous;
    String? who;
    if (a != null) {
      final n = (sentName ?? '').trim();
      who = a ? 'Anonymous' : (n.isEmpty ? 'With your name' : n);
    }
    final meta = [if (who != null) who, if (sub.isNotEmpty) sub].join(' · ');

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isBox
                                ? Icons.lightbulb_outline
                                : Icons.show_chart_rounded,
                            size: 15,
                            color: _soft,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              isBox ? 'Suggestion' : 'Weekly Pulse',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _t(13),
                            ),
                          ),
                          if (st != null) ...[
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: FeedbackStatus.color(st),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              FeedbackStatus.label(st),
                              style: _t(13,
                                  w: FontWeight.w700,
                                  c: FeedbackStatus.color(st)),
                            ),
                          ],
                          // Arrow after the status.
                          if (onTap != null) ...[
                            const SizedBox(width: 2),
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: _soft,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _t(15.5, c: titleColor ?? _ink, h: 1.4),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (a != null) ...[
                              Icon(
                                a
                                    ? Icons.lock_outline_rounded
                                    : Icons.person_outline_rounded,
                                size: 14,
                                color: _soft,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _t(13),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (hasReply) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            const Icon(Icons.check_rounded,
                                size: 15, color: _green),
                            const SizedBox(width: 4),
                            Text('Admin replied',
                                style: _t(13, w: FontWeight.w700, c: _green)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
