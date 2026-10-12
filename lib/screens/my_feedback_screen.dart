import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/employee.dart';
import '../models/feedback_item.dart';
import '../models/pulse_rating.dart';
import '../services/feedback_service.dart';
import '../services/pulse_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Everything this employee has sent, in two tabs that never mix:
/// - Suggestions: filter by status, the same five steps the status box
///   shows (New, Under review, Planned, In progress, Implemented).
/// - Weekly Pulse: every week you answered (also Great and Good), with
///   your comment when you wrote one. Filter by rating or "Replied".
/// Both tabs have a date button (Today, This week, …) and are grouped
/// by month.
class MyFeedbackScreen extends StatefulWidget {
  const MyFeedbackScreen({
    super.key,
    required this.employee,
    this.initialTab = 0,
  });

  final Employee employee;

  /// 0 opens on Suggestions, 1 opens on Weekly Pulse.
  final int initialTab;

  @override
  State<MyFeedbackScreen> createState() => _MyFeedbackScreenState();
}

/// Inter font for everything on this screen (same as the home screen).
/// Every text style here that does not name a font takes Inter from this.
ThemeData _interTheme(BuildContext context) {
  final t = Theme.of(context);
  return t.copyWith(textTheme: GoogleFonts.interTextTheme(t.textTheme));
}

/// Inter for the few titles that set their own style.
TextStyle _title(double size) => GoogleFonts.inter(
  fontSize: size,
  fontWeight: FontWeight.w800,
  color: AppColors.ink,
  letterSpacing: -0.3,
);

/// The date choices.
enum _Dates { all, today, thisWeek, days30, months3, thisYear, month }

/// Weekly Pulse chip for "has a reply from management".
const String _replied = '_replied';

class _MyFeedbackScreenState extends State<MyFeedbackScreen> {
  late final Stream<List<FeedbackItem>> _stream;

  /// 0 = Suggestions, 1 = Weekly Pulse.
  int _tab = 0;

  // Suggestions tab.
  /// null is All, otherwise one status.
  String? _status;
  _Dates _boxDates = _Dates.all;
  DateTime? _boxMonth;

  // Weekly Pulse tab.
  /// null is All, a rating, or [_replied].
  String? _pulseChip;
  _Dates _pulseDates = _Dates.all;
  DateTime? _pulseMonth;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    // Live: a status change or a reply shows up without leaving the screen.
    _stream = FeedbackService.instance.watchMyFeedback(widget.employee.uid);
    _loadAnswers();
  }

  /// Every Weekly Pulse answer of this person, also Great and Good with
  /// no comment. Null while loading.
  List<_Answer>? _answers;

  /// How many weeks back to look.
  static const int _weeksBack = 52;

  /// Reads this person's answer for each week. Each answer has a fixed
  /// name (week_person), and a person may read only their own.
  Future<void> _loadAnswers() async {
    final db = FirebaseFirestore.instance.collection('pulse_responses');
    final uid = widget.employee.uid;
    final thisWeek = PulseService.currentWeekId();
    final weekIds = [
      for (var i = 0; i < _weeksBack; i++) PulseService.shiftWeek(thisWeek, -i),
    ];
    final found = await Future.wait(
      weekIds.map((w) async {
        try {
          final doc = await db.doc('${w}_$uid').get();
          final data = doc.data();
          final rating = data?['rating'] as String?;
          if (rating == null) return null;
          return _Answer(
            weekId: w,
            rating: rating,
            at: (data?['createdAt'] as Timestamp?)?.toDate(),
          );
        } catch (_) {
          return null;
        }
      }),
    );
    if (!mounted) return;
    setState(() => _answers = found.whereType<_Answer>().toList());
  }

  /// One row per week: the answer, and the comment if one was written.
  List<_Entry> _entries(List<FeedbackItem> comments) {
    final byWeek = <String, FeedbackItem>{
      for (final c in comments)
        if (c.weekId != null) c.weekId!: c,
    };
    final out = <_Entry>[];
    final seen = <String>{};
    for (final a in _answers ?? const <_Answer>[]) {
      seen.add(a.weekId);
      // Use the comment only if it belongs to this same answer.
      final found = byWeek[a.weekId];
      final c = found != null && found.rating == a.rating ? found : null;
      out.add(
        _Entry(
          weekId: a.weekId,
          rating: a.rating,
          date: a.at ?? c?.createdAt ?? _weekDate(a.weekId),
          comment: c,
        ),
      );
    }
    // Comments from weeks not loaded above (older ones).
    for (final c in comments) {
      final w = c.weekId;
      if (w != null && seen.contains(w)) continue;
      out.add(
        _Entry(
          weekId: w,
          rating: c.rating,
          date: _dateOf(c),
          comment: c,
        ),
      );
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  static DateTime _weekDate(String weekId) {
    final p = weekId.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  _Dates get _dates => _tab == 0 ? _boxDates : _pulseDates;
  DateTime? get _month => _tab == 0 ? _boxMonth : _pulseMonth;

  void _setDates(_Dates d, [DateTime? month]) {
    setState(() {
      if (_tab == 0) {
        _boxDates = d;
        _boxMonth = month;
      } else {
        _pulseDates = d;
        _pulseMonth = month;
      }
    });
  }

  static DateTime _dateOf(FeedbackItem f) => f.createdAt ?? DateTime.now();

  bool _inDates(FeedbackItem f) => _inDatesAt(_dateOf(f));

  bool _inDatesAt(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_dates) {
      case _Dates.all:
        return true;
      case _Dates.today:
        return !d.isBefore(today);
      case _Dates.thisWeek:
        return !d.isBefore(
          DateTime(today.year, today.month, today.day - (today.weekday - 1)),
        );
      case _Dates.days30:
        return !d.isBefore(DateTime(today.year, today.month, today.day - 30));
      case _Dates.months3:
        return !d.isBefore(DateTime(today.year, today.month - 3, today.day));
      case _Dates.thisYear:
        return d.year == now.year;
      case _Dates.month:
        final m = _month!;
        return d.year == m.year && d.month == m.month;
    }
  }

  String _datesLabel() {
    switch (_dates) {
      case _Dates.all:
        return 'All dates';
      case _Dates.today:
        return 'Today';
      case _Dates.thisWeek:
        return 'This week';
      case _Dates.days30:
        return 'Last 30 days';
      case _Dates.months3:
        return 'Last 3 months';
      case _Dates.thisYear:
        return 'This year';
      case _Dates.month:
        return '${_longMonths[_month!.month - 1]} ${_month!.year}';
    }
  }

  Future<void> _openDates(List<DateTime> dates) async {
    Widget option(String label, _Dates value) => ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      trailing: Icon(
        _dates == value
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
        color: _dates == value ? AppColors.blue : const Color(0xFFC9D0DC),
      ),
      onTap: () {
        Navigator.of(context).pop();
        _setDates(value);
      },
    );

    final months = <DateTime>{
      for (final d in dates) DateTime(d.year, d.month, 1),
    }.toList()
      ..sort((a, b) => b.compareTo(a));

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => Theme(
        data: _interTheme(sheetContext),
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              children: [
                Text('Show from', style: _title(19)),
                const SizedBox(height: 6),
                option('All dates', _Dates.all),
                option('Today', _Dates.today),
                option('This week', _Dates.thisWeek),
                option('Last 30 days', _Dates.days30),
                option('Last 3 months', _Dates.months3),
                option('This year', _Dates.thisYear),
                if (months.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(0, 14, 0, 4),
                    child: Text(
                      'OR PICK A MONTH',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  for (final m in months)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${_longMonths[m.month - 1]} ${m.year}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      trailing: Icon(
                        _dates == _Dates.month && _month == m
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: _dates == _Dates.month && _month == m
                            ? AppColors.blue
                            : const Color(0xFFC9D0DC),
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _setDates(_Dates.month, m);
                      },
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _interTheme(context),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          leadingWidth: 68,
          leading: const AppBackButton(),
          titleSpacing: 4,
          centerTitle: false,
          title: Text('My Feedback', style: _title(22)),
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: StreamBuilder<List<FeedbackItem>>(
                stream: _stream,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return const _Message(
                      text: 'Could not load your feedback. '
                          'Please go back and try again.',
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final all = snap.data!;
                  final box = all.where((f) => f.isFromBox).toList();
                  final comments = all.where((f) => !f.isFromBox).toList();
                  final entries = _entries(comments);

                  final List<Widget> chips;
                  final list = <Widget>[];
                  final int shownCount;
                  final bool nothingAtAll;
                  final List<DateTime> allDates;
                  String? lastMonth;
                  void monthHeader(DateTime d) {
                    final m = '${_longMonths[d.month - 1]} ${d.year}';
                    if (m != lastMonth) {
                      lastMonth = m;
                      list.add(_MonthHeader(label: m));
                    }
                  }

                  if (_tab == 0) {
                    final inDates = box.where(_inDates).toList();
                    // The same five steps as the status box on each card.
                    chips = [
                      _CountChip(
                        label: 'All',
                        dot: null,
                        count: inDates.length,
                        selected: _status == null,
                        onTap: () => setState(() => _status = null),
                      ),
                      for (final st in FeedbackStatus.all)
                        _CountChip(
                          label: FeedbackStatus.label(st),
                          dot: _statusDot(st),
                          count: inDates.where((f) => f.status == st).length,
                          selected: _status == st,
                          onTap: () => setState(() => _status = st),
                        ),
                    ];
                    final items = _status == null
                        ? inDates
                        : inDates.where((f) => f.status == _status).toList();
                    for (final item in items) {
                      monthHeader(_dateOf(item));
                      list.add(
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                          child: _FeedbackCard(
                            item: item,
                            employee: widget.employee,
                          ),
                        ),
                      );
                    }
                    shownCount = items.length;
                    nothingAtAll = box.isEmpty;
                    allDates = [for (final f in box) _dateOf(f)];
                  } else {
                    final inDates =
                    entries.where((e) => _inDatesAt(e.date)).toList();
                    chips = [
                      _CountChip(
                        label: 'All',
                        dot: null,
                        count: inDates.length,
                        selected: _pulseChip == null,
                        onTap: () => setState(() => _pulseChip = null),
                      ),
                      for (final r in PulseRating.all.reversed)
                        _CountChip(
                          label: PulseRating.label(r),
                          dot: _moodColor(r),
                          count: inDates.where((e) => e.rating == r).length,
                          selected: _pulseChip == r,
                          onTap: () => setState(() => _pulseChip = r),
                        ),
                      _CountChip(
                        label: 'Replied',
                        dot: const Color(0xFF16A34A),
                        count: inDates
                            .where((e) => e.comment?.hasReply ?? false)
                            .length,
                        selected: _pulseChip == _replied,
                        onTap: () => setState(() => _pulseChip = _replied),
                      ),
                    ];
                    final chip = _pulseChip;
                    final List<_Entry> items;
                    if (chip == null) {
                      items = inDates;
                    } else if (chip == _replied) {
                      items = inDates
                          .where((e) => e.comment?.hasReply ?? false)
                          .toList();
                    } else {
                      items = inDates.where((e) => e.rating == chip).toList();
                    }
                    for (final e in items) {
                      monthHeader(e.date);
                      list.add(
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                          child: _WeekCard(entry: e, employee: widget.employee),
                        ),
                      );
                    }
                    shownCount = items.length;
                    nothingAtAll = entries.isEmpty;
                    allDates = [for (final e in entries) e.date];
                  }
                  final loadingWeeks = _tab == 1 && _answers == null;

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
                        child: Text(
                          'Everything you have sent, and what happened to it.',
                          style: TextStyle(color: AppColors.muted, fontSize: 14),
                        ),
                      ),
                      // The two tabs.
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F4F9),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              _Tab(
                                icon: Icons.lightbulb_outline,
                                label: 'Suggestions',
                                count: box.length,
                                selected: _tab == 0,
                                onTap: () => setState(() => _tab = 0),
                              ),
                              _Tab(
                                icon: Icons.monitor_heart_outlined,
                                label: 'Weekly Pulse',
                                count: entries.length,
                                selected: _tab == 1,
                                onTap: () => setState(() => _tab = 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Chips for this tab.
                      SizedBox(
                        height: 38,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: chips.length,
                          separatorBuilder: (context, index) =>
                          const SizedBox(width: 8),
                          itemBuilder: (context, i) => chips[i],
                        ),
                      ),
                      // Date button and how many show.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                        child: Row(
                          children: [
                            _DateButton(
                              label: _datesLabel(),
                              active: _dates != _Dates.all,
                              onTap: () => _openDates(allDates),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '$shownCount · newest first',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (loadingWeeks)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (shownCount == 0)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                          child: _EmptyCard(
                            text: nothingAtAll
                                ? (_tab == 0
                                ? 'You have not sent a suggestion yet.'
                                : 'You have not answered the Weekly '
                                'Pulse yet.')
                                : 'Nothing here for these filters.',
                          ),
                        ),
                      ...list,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------

class _Message extends StatelessWidget {
  const _Message({required this.text});

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

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Text(
        text,
        style: const TextStyle(color: AppColors.muted, fontSize: 15),
      ),
    );
  }
}

/// One half of the tab switch: icon, name and count.
class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        elevation: selected ? 1.5 : 0,
        shadowColor: const Color(0x330E1A3A),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? AppColors.blue : AppColors.muted,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? AppColors.ink : AppColors.muted,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF1F6),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
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

/// A round chip: optional colour dot, name and count. Chosen is blue.
class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.dot,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color? dot;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.blue : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? AppColors.blue : const Color(0xFFD5DCE8),
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: selected ? Colors.white : dot,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.ink,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 7),
              Container(
                constraints: const BoxConstraints(minWidth: 20),
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.22)
                      : const Color(0xFFEEF1F6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "📅 Last 30 days ▾". Blue when a date is chosen.
class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? Colors.white : AppColors.blue;
    return Material(
      color: active ? AppColors.blue : const Color(0xFFF2F6FF),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_month_outlined, size: 18, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Icon(Icons.arrow_drop_down, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

/// "OCTOBER 2026 ————".
class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 10),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Divider(height: 1, color: Color(0xFFEEF1F6)),
          ),
        ],
      ),
    );
  }
}

/// One thing the employee sent. Purple line and tag for a suggestion,
/// blue for a Weekly Pulse comment (with its rating).
class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.item, required this.employee});

  final FeedbackItem item;
  final Employee employee;

  static const Color _purple = Color(0xFF8B5CF6);

  @override
  Widget build(BuildContext context) {
    final isBox = item.isFromBox;
    final rating = item.rating;
    final d = item.createdAt;
    final date = d == null ? '' : '${d.day} ${_shortMonths[d.month - 1]}';
    final who = item.anonymous
        ? 'Sent anonymously'
        : '${employee.name} (${employee.employeeId})';

    return DecoratedBox(
      decoration: _cardDecoration(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: isBox ? _purple : AppColors.blue),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
                            decoration: BoxDecoration(
                              color: isBox
                                  ? const Color(0xFFF1EBFE)
                                  : const Color(0xFFE6EDFF),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isBox
                                      ? Icons.lightbulb_outline
                                      : Icons.monitor_heart_outlined,
                                  size: 14,
                                  color: isBox
                                      ? const Color(0xFF5B34C7)
                                      : AppColors.blueDeep,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  isBox
                                      ? 'Suggestion'
                                      : rating == null
                                      ? 'Weekly Pulse'
                                      : 'Weekly Pulse · '
                                      '${PulseRating.label(rating)}',
                                  style: TextStyle(
                                    color: isBox
                                        ? const Color(0xFF5B34C7)
                                        : AppColors.blueDeep,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            date,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Text(
                        item.text,
                        style: const TextStyle(
                          fontSize: 15.5,
                          height: 1.4,
                          color: AppColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            item.anonymous
                                ? Icons.lock_outline
                                : Icons.person_outline,
                            size: 15,
                            color: AppColors.muted,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              who,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _Progress(key: ValueKey(item.id), status: item.status),
                      if (item.hasReply) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE3F6EA),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Reply from management',
                                style: TextStyle(
                                  color: Color(0xFF166534),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                item.managementMessage,
                                style: const TextStyle(
                                  color: Color(0xFF14532D),
                                  fontSize: 14.5,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
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
  }
}

BoxDecoration _cardDecoration() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: const Color(0xFFE6EBF4)),
  boxShadow: const [
    BoxShadow(
      color: Color(0x0F0E1A3A),
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ],
);

/// One Weekly Pulse answer: the week and the rating.
class _Answer {
  const _Answer({required this.weekId, required this.rating, this.at});

  final String weekId;
  final String rating;
  final DateTime? at;
}

/// One row on the Weekly Pulse tab: a week's answer, plus the written
/// comment when there is one.
class _Entry {
  const _Entry({
    required this.weekId,
    required this.rating,
    required this.date,
    required this.comment,
  });

  final String? weekId;
  final String? rating;
  final DateTime date;
  final FeedbackItem? comment;
}

/// A week on the Weekly Pulse tab: the dates, "You said Good", and the
/// comment with its status and reply when one was written.
class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.entry, required this.employee});

  final _Entry entry;
  final Employee employee;

  @override
  Widget build(BuildContext context) {
    final rating = entry.rating;
    final comment = entry.comment;
    final weekId = entry.weekId;
    final name = weekId == null ? '' : PulseService.weekName(weekId);
    final week = weekId == null
        ? ''
        : [PulseService.weekLabel(weekId), if (name.isNotEmpty) name]
        .join(' · ');
    final color = rating == null ? AppColors.blue : _moodColor(rating);

    return DecoratedBox(
      decoration: _cardDecoration(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 14,
                            color: AppColors.muted,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              week.isEmpty ? 'Weekly Pulse' : week,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // "You said Good".
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Icon(
                              rating == null
                                  ? Icons.monitor_heart_outlined
                                  : PulseRating.icon(rating),
                              color: color,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(
                                  text: 'You said  ',
                                  style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 14,
                                  ),
                                ),
                                TextSpan(
                                  text: rating == null
                                      ? '—'
                                      : PulseRating.label(rating),
                                  style: const TextStyle(
                                    color: AppColors.ink,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (comment != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          '${comment.text}',
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.4,
                            color: AppColors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              comment.anonymous
                                  ? Icons.lock_outline
                                  : Icons.person_outline,
                              size: 15,
                              color: AppColors.muted,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                comment.anonymous
                                    ? 'Sent anonymously'
                                    : '${employee.name} '
                                    '(${employee.employeeId})',
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _Progress(
                          key: ValueKey(comment.id),
                          status: comment.status,
                        ),
                        if (comment.hasReply) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding:
                            const EdgeInsets.fromLTRB(14, 11, 14, 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE3F6EA),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Reply from management',
                                  style: TextStyle(
                                    color: Color(0xFF166534),
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  comment.managementMessage,
                                  style: const TextStyle(
                                    color: Color(0xFF14532D),
                                    fontSize: 14.5,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
  }
}

/// Same rating colours as management.
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

/// Same status colours as management.
Color _statusDot(String status) {
  switch (status) {
    case FeedbackStatus.newItem:
      return const Color(0xFFE9A83B);
    case FeedbackStatus.underReview:
      return const Color(0xFF8B5CF6);
    case FeedbackStatus.planned:
      return const Color(0xFF0EA5A4);
    case FeedbackStatus.inProgress:
      return AppColors.blue;
    default:
      return const Color(0xFF16A34A);
  }
}

const List<String> _shortMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const List<String> _longMonths = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// The status as a box that opens and closes. Closed: one line with
/// the current status. Open: all five steps, so the employee can see
/// what is finished and what comes next. Only for looking; the
/// employee cannot change the status.
class _Progress extends StatefulWidget {
  const _Progress({super.key, required this.status});

  final String status;

  @override
  State<_Progress> createState() => _ProgressState();
}

class _ProgressState extends State<_Progress> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    const all = FeedbackStatus.all;
    final found = all.indexOf(widget.status);
    final current = found < 0 ? 0 : found;

    return Material(
      color: const Color(0xFFF5F7FB),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: _statusDot(all[current]),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      FeedbackStatus.label(all[current]),
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    _open
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 22,
                    color: AppColors.ink,
                    semanticLabel: _open ? 'Hide steps' : 'Show all steps',
                  ),
                ],
              ),
            ),
          ),
          if (_open) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Column(
                children: [
                  for (var i = 0; i < all.length; i++)
                    SizedBox(
                      height: 32,
                      child: Row(
                        children: [
                          _StepDot(done: i < current, now: i == current),
                          const SizedBox(width: 10),
                          Text(
                            FeedbackStatus.label(all[i]),
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: i == current
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: i == current
                                  ? AppColors.ink
                                  : AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The circle before a step name: a tick when finished, a blue ring
/// for the current step, an empty circle for the steps still to come.
class _StepDot extends StatelessWidget {
  const _StepDot({required this.done, required this.now});

  final bool done;
  final bool now;

  @override
  Widget build(BuildContext context) {
    if (done) {
      return Container(
        width: 18,
        height: 18,
        decoration: const BoxDecoration(
          color: AppColors.blue,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, color: Colors.white, size: 12),
      );
    }
    return Container(

      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: now ? AppColors.blue : AppColors.inputBorder,
          width: now ? 5 : 2,
        ),
      ),
    );
  }
}