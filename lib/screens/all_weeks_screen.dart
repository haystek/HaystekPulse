import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../demo_data.dart';
import '../models/pulse_rating.dart';
import '../models/pulse_totals.dart';
import '../services/pulse_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Inter font for everything on these screens, sheets and dialogs
/// (same as the employee screens).
Widget _withInter(BuildContext context, Widget child) {
  final t = Theme.of(context);
  return Theme(
    data: t.copyWith(textTheme: GoogleFonts.interTextTheme(t.textTheme)),
    child: child,
  );
}

/// Titles and big numbers in Inter.
TextStyle _h(
    double size, {
      FontWeight weight = FontWeight.w800,
      Color color = AppColors.ink,
      double? height,
    }) =>
    GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: size >= 22 ? -0.5 : -0.2,
    );

/// Management: every week from the first week the app was used up to
/// this week, newest first, grouped by month. Tap a week to see it on
/// the dashboard.
class AllWeeksScreen extends StatefulWidget {
  const AllWeeksScreen({
    super.key,
    required this.totalEmployees,
    this.selectedWeekId,
  });

  /// How many employees can answer. Used for the "answered" numbers.
  final Future<int> totalEmployees;

  /// The week the dashboard shows now. It gets a blue border here.
  final String? selectedWeekId;

  @override
  State<AllWeeksScreen> createState() => _AllWeeksScreenState();
}

class _AllWeeksScreenState extends State<AllWeeksScreen> {
  late final Stream<Map<String, PulseTotals>> _weeks;

  @override
  void initState() {
    super.initState();
    // One document per week in pulse_weeks. Weeks are few, so all of
    // them are read and sorted here.
    _weeks = FirebaseFirestore.instance
        .collection('pulse_weeks')
        .snapshots()
        .map(
          (snap) => {
        for (final doc in snap.docs)
          doc.id: PulseTotals.fromMap(doc.data()),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _withInter(context, Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        leadingWidth: 68,
        leading: const AppBackButton(),
        titleSpacing: 4,
        centerTitle: false,
        title: Text('All weeks', style: _h(22)),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: FutureBuilder<int>(
              future: widget.totalEmployees,
              builder: (context, totalSnap) {
                return StreamBuilder<Map<String, PulseTotals>>(
                  stream: _weeks,
                  builder: (context, snap) {
                    if (snap.hasError || totalSnap.hasError) {
                      return const _Message(
                        'Could not load the weeks. Please go back and try '
                            'again.',
                      );
                    }
                    if (!snap.hasData || !totalSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return _buildList(snap.data!, totalSnap.data!);
                  },
                );
              },
            ),
          ),
        ),
      ),
    ));
  }

  Widget _buildList(Map<String, PulseTotals> saved, int realTotal) {
    final thisWeek = PulseService.thisWeekId();
    final weeks = <String, PulseTotals>{
      if (DemoData.on) ...DemoData.weeks(thisWeek),
      ...saved,
    };
    final total = DemoData.on ? DemoData.people : realTotal;
    final selected = widget.selectedWeekId ?? thisWeek;

    // The first week the app was used: the oldest week with answers,
    // or this week when nobody has answered yet.
    var firstWeek = thisWeek;
    for (final id in weeks.keys) {
      if (id.compareTo(firstWeek) < 0) firstWeek = id;
    }

    // Every week from the first one up to this week, newest first. Weeks
    // where nobody answered still show, so no week goes missing.
    final ids = <String>[];
    for (var id = thisWeek;
    id.compareTo(firstWeek) >= 0;
    id = PulseService.shiftWeek(id, -1)) {
      ids.add(id);
    }

    // Month title above the first week of each month.
    final children = <Widget>[
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 0, 4, 6),
        child: Text(
          'Tap a week to see it on the dashboard.',
          style: TextStyle(color: AppColors.muted, fontSize: 12.5),
        ),
      ),
    ];
    String? lastMonth;
    for (final id in ids) {
      final month = _monthTitle(id);
      if (month != lastMonth) {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
            child: Text(
              month,
              style: _h(15, weight: FontWeight.w700, color: AppColors.muted),
            ),
          ),
        );
        lastMonth = month;
      }
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _WeekCard(
            weekId: id,
            totals: weeks[id] ?? const PulseTotals(),
            total: total,
            selected: id == selected,
            onTap: () => Navigator.of(context).pop(id),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: children,
    );
  }
}

// ---------------------------------------------------------------------
// One week
// ---------------------------------------------------------------------

class _WeekCard extends StatelessWidget {
  const _WeekCard({
    required this.weekId,
    required this.totals,
    required this.total,
    required this.selected,
    required this.onTap,
  });

  final String weekId;
  final PulseTotals totals;
  final int total;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isThisWeek = weekId == PulseService.thisWeekId();
    final open = isThisWeek && PulseService.isOpen();
    final notOpenYet = isThisWeek && PulseService.notOpenYet();
    final closedNow = isThisWeek && !open && !notOpenYet;
    final submitted = totals.submitted;
    final percent =
    total == 0 ? 0 : ((submitted / total) * 100).round().clamp(0, 100);

    // Small tag next to the dates.
    String tag = PulseService.weekName(weekId);
    if (open) tag = 'Open now';
    if (notOpenYet) tag = 'Starting soon';
    if (closedNow) tag = 'Closed';

    // The line under the dates.
    final String detail;
    if (notOpenYet) {
      detail = 'Opens '
          '${PulseService.dateTimeLabel(PulseService.opensAt())}';
    } else if (submitted == 0) {
      detail = isThisWeek ? 'No answers yet' : 'No answers';
    } else {
      detail = '$submitted of $total answered';
    }

    return Material(
      color: selected ? const Color(0xFFF2F6FF) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? AppColors.blue : const Color(0xFFE3E8F2),
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              _shortWeek(weekId),
                              style: _h(18, weight: FontWeight.w700),
                            ),
                            if (tag.isNotEmpty)
                              _Tag(text: tag, strong: open),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          detail,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _MiniRing(
                    totals: totals,
                    whole: total,
                    label: notOpenYet ? '–' : '$percent%',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _MoodBar(totals: totals),
              const SizedBox(height: 10),
              Wrap(
                spacing: 20,
                runSpacing: 60,
                children: [
                  for (final rating in PulseRating.all)
                    _Legend(rating: rating, count: totals.countFor(rating)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Open now", "Starting soon", "Closed", "Last week".
class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.strong});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: strong ? AppColors.blue : const Color(0xFFEEF1F6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: strong ? Colors.white : AppColors.ink,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// One line split by rating. Grey when nobody answered.
class _MoodBar extends StatelessWidget {
  const _MoodBar({required this.totals});

  final PulseTotals totals;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final r in PulseRating.all)
        if (totals.countFor(r) > 0) r,
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        height: 4,
        child: shown.isEmpty
            ? const ColoredBox(
          color: Color(0xFFEDF0F6),
          child: SizedBox.expand(),
        )
            : Row(
          children: [
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(
                flex: totals.countFor(shown[i]),
                child: ColoredBox(
                  color: _moodColor(shown[i]),
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A colour dot, the count and the rating name: "● 18 Great".
class _Legend extends StatelessWidget {
  const _Legend({required this.rating, required this.count});

  final String rating;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 2,
          height: 2,
          decoration: BoxDecoration(
            color: _moodColor(rating),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text.rich(
          TextSpan(
            style: const TextStyle(color: AppColors.muted, fontSize: 13.5),
            children: [
              TextSpan(
                text: '$count ',
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(text: PulseRating.label(rating)),
            ],
          ),
        ),
      ],
    );
  }
}

/// A small ring with the answered percent in the middle.
class _MiniRing extends StatelessWidget {
  const _MiniRing({
    required this.totals,
    required this.whole,
    required this.label,
  });

  final PulseTotals totals;
  final int whole;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      height: 58,
      child: CustomPaint(
        painter: _MiniRingPainter(
          parts: [
            for (final r in PulseRating.all) (totals.countFor(r), _moodColor(r)),
          ],
          whole: whole,
        ),
        child: Center(
          child: Text(
            label,
            style: _h(13.5, weight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _MiniRingPainter extends CustomPainter {
  _MiniRingPainter({required this.parts, required this.whole});

  final List<(int, Color)> parts;
  final int whole;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = const Color(0xFFEDF0F6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (whole == 0) return;
    const gap = 0.06;
    var start = -math.pi / 2;
    for (final (count, colour) in parts) {
      if (count == 0) continue;
      final sweep = math.pi * 2 * math.min(count, whole) / whole;
      canvas.drawArc(
        rect,
        start + gap / 2,
        math.max(0.0, sweep - gap),
        false,
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_MiniRingPainter old) =>
      old.whole != whole || old.parts.toString() != parts.toString();
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------

/// Same rating colours as the dashboard.
Color _moodColor(String rating) {
  switch (rating) {
    case PulseRating.great:
      return AppColors.blue;
    case PulseRating.good:
      return const Color(0xFF6E95F2);
    case PulseRating.okay:
      return const Color(0xFFE9A83B);
    default:
      return const Color(0xFFE2583E);
  }
}

const List<String> _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const List<String> _longMonthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

DateTime _mondayOf(String weekId) {
  final p = weekId.split('-').map(int.parse).toList();
  final d = DateTime(p[0], p[1], p[2]);
  return DateTime(d.year, d.month, d.day - (d.weekday - 1));
}

/// "5 – 9 Oct" or "28 Sep – 2 Oct".
String _shortWeek(String weekId) {
  final monday = _mondayOf(weekId);
  final friday = DateTime(monday.year, monday.month, monday.day + 4);
  if (monday.month == friday.month) {
    return '${monday.day} – ${friday.day} ${_monthNames[friday.month - 1]}';
  }
  return '${monday.day} ${_monthNames[monday.month - 1]} – '
      '${friday.day} ${_monthNames[friday.month - 1]}';
}

/// "October 2026": the month the week's Friday falls in.
String _monthTitle(String weekId) {
  final monday = _mondayOf(weekId);
  final friday = DateTime(monday.year, monday.month, monday.day + 4);
  return '${_longMonthNames[friday.month - 1]} ${friday.year}';
}
