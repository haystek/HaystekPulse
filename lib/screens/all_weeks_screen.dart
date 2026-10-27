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
        // No title on the left: the name sits on the right in a pill.
        title: const SizedBox.shrink(),
        actions: const [
          _TitlePill('All weeks', icon: Icons.calendar_month_outlined),
        ],
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
                      return const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.blue,
                          ),
                        ),
                      );
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

    // Month name above the first week of each month.
    final children = <Widget>[];
    String? lastMonth;
    for (final id in ids) {
      final month = _monthTitle(id);
      if (month != lastMonth) {
        children.add(
          Padding(
            padding: EdgeInsets.fromLTRB(22, lastMonth == null ? 4 : 18, 22, 4),
            child: Text(
              month,
              style: const TextStyle(color: Color(0xFF8E97AB), fontSize: 13),
            ),
          ),
        );
        lastMonth = month;
      }
      children.add(
        _WeekRow(
          weekId: id,
          totals: weeks[id] ?? const PulseTotals(),
          total: total,
          selected: id == selected,
          onTap: () => Navigator.of(context).pop(id),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 28),
      children: children,
    );
  }
}

class _TitlePill extends StatelessWidget {
  const _TitlePill(this.text, {required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Container(
        height: 42,
        padding: const EdgeInsets.fromLTRB(5, 5, 16, 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(21),
          border: Border.all(color: AppColors.blue.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: AppColors.blue,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 17, color: Colors.white),
            ),
            const SizedBox(width: 9),
            Text(
              text,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: AppColors.ink,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ---------------------------------------------------------------------
// One week (design "Date chips")
// ---------------------------------------------------------------------

/// One week:
///
///   [ 19 ]  Mostly good
///   [ OCT]  19 – 23 Oct · 24 of 30 answered
///
/// The chosen week has a blue date tile. This week shows "● Open"
/// on the right while the Weekly Pulse is open.
class _WeekRow extends StatelessWidget {
  const _WeekRow({
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
    final submitted = totals.submitted;
    final monday = _mondayOf(weekId);

    final String title;
    final String detail;
    if (notOpenYet) {
      title = 'This week';
      detail = 'Opens ${PulseService.dateTimeLabel(PulseService.opensAt())}';
    } else {
      title = isThisWeek && open ? 'This week' : _result(totals, total);
      detail = '${_shortWeek(weekId)} · '
          '${submitted == 0 ? 'No answers' : '$submitted of $total answered'}';
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        child: Row(
          children: [
            // The date tile: Monday's day and the month.
            Container(
              width: 48,
              height: 52,
              decoration: BoxDecoration(
                color: selected ? AppColors.blue : const Color(0xFFF2F5FA),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${monday.day}',
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.1,
                      fontWeight: FontWeight.w500,
                      color: selected ? Colors.white : AppColors.ink,
                    ),
                  ),
                  Text(
                    _monthNames[monday.month - 1].toUpperCase(),
                    style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 0.8,
                      color: selected
                          ? const Color(0xFFC9D6FF)
                          : const Color(0xFF8E97AB),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15.5,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF8E97AB),
                    ),
                  ),
                ],
              ),
            ),
            if (open) ...[
              const SizedBox(width: 8),
              const Text(
                '● Open',
                style: TextStyle(fontSize: 12, color: Color(0xFF15803D)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// How the week went, in a few words. Same rules as the dashboard:
/// the result shows after 25% of people answered (at least 3).
String _result(PulseTotals t, int total) {
  final submitted = t.submitted;
  if (submitted == 0) return 'No answers';
  var needed = (total * 0.25).ceil();
  if (needed < 3) needed = 3;
  if (needed > total) needed = total;
  if (submitted < needed) return 'Not enough answers';
  final good = t.countFor(PulseRating.great) + t.countFor(PulseRating.good);
  final share = good / submitted;
  if (share >= 0.75) {
    return t.countFor(PulseRating.great) > t.countFor(PulseRating.good)
        ? 'A great week'
        : 'A good week';
  }
  if (share > 0.5) return 'Mostly good';
  if (share >= 0.25) return 'A mixed week';
  return t.countFor(PulseRating.okay) > t.countFor(PulseRating.difficult)
      ? 'An okay week'
      : 'A hard week';
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
  final name = _longMonthNames[friday.month - 1];
  return friday.year == DateTime.now().year ? name : '$name ${friday.year}';
}