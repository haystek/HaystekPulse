import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../demo_data.dart';
import '../models/employee.dart';
import '../models/feedback_item.dart';
import '../models/pulse_rating.dart';
import '../services/feedback_service.dart';
import '../services/pulse_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Everything this employee has sent, in two tabs that never mix.
/// Look: a quiet list. Each row has the date on the left, the answer in
/// its colour, the employee's words in soft grey, management's reply
/// with a thin green line, and the status in one small line.
///
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
  fontWeight: FontWeight.w700,
  color: AppColors.ink,
  letterSpacing: -0.4,
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
    final answers = found.whereType<_Answer>().toList();
    // Sample answers (DemoData), for weeks without a real answer.
    if (DemoData.on) {
      final have = {for (final a in answers) a.weekId};
      DemoData.myAnswers().forEach((weekId, a) {
        if (have.contains(weekId)) return;
        answers.add(_Answer(weekId: weekId, rating: a.$1, at: a.$2));
      });
    }
    setState(() => _answers = answers);
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
        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w400),
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
                Text('Show from', style: _title(18)),
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
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  for (final m in months)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${_longMonths[m.month - 1]} ${m.year}',
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w400,
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
                  if (!snap.hasData) return const _Loader();
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
                    chips = [
                      _Chip(
                        label: 'All',
                        selected: _status == null,
                        onTap: () => setState(() => _status = null),
                      ),
                      for (final st in FeedbackStatus.all)
                        _Chip(
                          label: FeedbackStatus.label(st),
                          selected: _status == st,
                          onTap: () => setState(() => _status = st),
                        ),
                    ];
                    final items = _status == null
                        ? inDates
                        : inDates.where((f) => f.status == _status).toList();
                    for (var i = 0; i < items.length; i++) {
                      monthHeader(_dateOf(items[i]));
                      list.add(_SuggestionRow(item: items[i]));
                    }
                    shownCount = items.length;
                    nothingAtAll = box.isEmpty;
                    allDates = [for (final f in box) _dateOf(f)];
                  } else {
                    final inDates =
                    entries.where((e) => _inDatesAt(e.date)).toList();
                    chips = [
                      _Chip(
                        label: 'All',
                        selected: _pulseChip == null,
                        onTap: () => setState(() => _pulseChip = null),
                      ),
                      for (final r in PulseRating.all.reversed)
                        _Chip(
                          label: PulseRating.label(r),
                          selected: _pulseChip == r,
                          onTap: () => setState(() => _pulseChip = r),
                        ),
                      _Chip(
                        label: 'Replied',
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
                      list.add(_WeekRow(entry: e));
                    }
                    shownCount = items.length;
                    nothingAtAll = entries.isEmpty;
                    allDates = [for (final e in entries) e.date];
                  }
                  final loadingWeeks = _tab == 1 && _answers == null;

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(0, 4, 0, 28),
                    children: [
                      // The two tabs: text with a blue line under the
                      // chosen one.
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: _line),
                            ),
                          ),
                          child: Row(
                            children: [
                              _Tab(
                                label: 'Suggestions',
                                count: box.length,
                                selected: _tab == 0,
                                onTap: () => setState(() => _tab = 0),
                              ),
                              const SizedBox(width: 24),
                              _Tab(
                                label: 'Weekly Pulse',
                                count: entries.length,
                                selected: _tab == 1,
                                onTap: () => setState(() => _tab = 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Still loading the weeks: only the loader, at the
                      // top in the middle.
                      if (loadingWeeks)
                        const _Loader()
                      else ...[
                        // Chips for this tab.
                        SizedBox(
                          height: 32,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: chips.length,
                            separatorBuilder: (context, index) =>
                            const SizedBox(width: 6),
                            itemBuilder: (context, i) => chips[i],
                          ),
                        ),
                        // How many show, and the date filter.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  shownCount == 1
                                      ? '1 item'
                                      : '$shownCount items',
                                  style: _t(12.5, color: _soft),
                                ),
                              ),
                              _DateButton(
                                label: _datesLabel(),
                                active: _dates != _Dates.all,
                                onTap: () => _openDates(allDates),
                              ),
                            ],
                          ),
                        ),
                        if (shownCount == 0)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 40, 20, 0),
                            child: Text(
                              nothingAtAll
                                  ? (_tab == 0
                                  ? 'You have not sent a suggestion yet.'
                                  : 'You have not answered the Weekly '
                                  'Pulse yet.')
                                  : 'Nothing here for these filters.',
                              textAlign: TextAlign.center,
                              style: _t(14.5, color: _soft, height: 1.4),
                            ),
                          ),
                        ...list,
                      ],
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
// Look
// ---------------------------------------------------------------------

/// Soft grey for small, less important text.
const Color _soft = Color(0xFF98A1B6);

/// Grey for the employee's own words.
const Color _words = Color(0xFF5B6680);

/// Thin lines between rows.
const Color _line = Color(0xFFEDF0F5);

/// Inter with a chosen size, weight and colour.
TextStyle _t(
    double size, {
      FontWeight weight = FontWeight.w400,
      Color color = AppColors.ink,
      double? height,
      double? letterSpacing,
    }) =>
    GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );

/// Small capitals: "OCTOBER 2026", "MANAGEMENT REPLIED".
TextStyle _caps(Color color) =>
    _t(10.5, weight: FontWeight.w600, color: color, letterSpacing: 1.2);

// ---------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------

/// A small loader at the top, in the middle.
class _Loader extends StatelessWidget {
  const _Loader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 40),
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: _t(14.5, color: _words),
        ),
      ),
    );
  }
}

/// One tab: name and a small count. The chosen one is dark with a blue
/// line under it.
class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? AppColors.blue : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                label,
                style: _t(
                  15,
                  weight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? AppColors.ink : _soft,
                ),
              ),
              const SizedBox(width: 5),
              Text('$count', style: _t(12.5, color: _soft)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small soft chip. The chosen one is dark.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.ink : const Color(0xFFF3F5F9),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: _t(
                13,
                weight: selected ? FontWeight.w500 : FontWeight.w400,
                color: selected ? Colors.white : _words,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "All dates ▾" as small blue text. Shows the chosen dates when set.
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
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.blue,
        backgroundColor:
        active ? const Color(0xFFEEF3FF) : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        minimumSize: const Size(0, 34),
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_today_outlined, size: 14),
          const SizedBox(width: 6),
          Text(label, style: _t(13, weight: FontWeight.w500, color: AppColors.blue)),
          const Icon(Icons.arrow_drop_down, size: 20),
        ],
      ),
    );
  }
}

/// "OCTOBER 2026" in small grey capitals.
class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 2),
      child: Text(label.toUpperCase(), style: _caps(_soft)),
    );
  }
}

/// The base of every row: the date on the left (big day, small month),
/// the content on the right, and a thin line under it.
class _Row extends StatelessWidget {
  const _Row({required this.date, required this.child});

  final DateTime date;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 36,
              child: Column(
                children: [
                  Text(
                    '${date.day}',
                    style: _t(
                      20,
                      weight: FontWeight.w600,
                      height: 1.1,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _shortMonths[date.month - 1].toUpperCase(),
                    style: _t(
                      10,
                      weight: FontWeight.w600,
                      color: _soft,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// One suggestion: how it was sent, the words, the reply and status.
class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.item});

  final FeedbackItem item;

  @override
  Widget build(BuildContext context) {
    return _Row(
      date: item.createdAt ?? DateTime.now(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.anonymous ? 'Sent anonymously' : 'Sent with your name',
            style: _t(12, color: _soft),
          ),
          const SizedBox(height: 3),
          Text(item.text, style: _t(15, height: 1.5)),
          if (item.hasReply) _Reply(text: item.managementMessage),
          const SizedBox(height: 10),
          _StatusLine(status: item.status),
        ],
      ),
    );
  }
}

/// One Weekly Pulse week: the answer in its colour, the week, the
/// comment (soft grey), the reply and status.
class _WeekRow extends StatelessWidget {
  const _WeekRow({required this.entry});

  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    final rating = entry.rating;
    final comment = entry.comment;
    final weekId = entry.weekId;
    final name = weekId == null ? '' : PulseService.weekName(weekId);
    final week = weekId == null
        ? ''
        : (name.isNotEmpty ? name : PulseService.weekLabel(weekId));
    final color = rating == null ? AppColors.blue : _moodText(rating);

    return _Row(
      date: entry.date,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  rating == null ? 'Weekly Pulse' : PulseRating.label(rating),
                  style: _t(15.5, weight: FontWeight.w600, color: color),
                ),
              ),
              if (week.isNotEmpty) Text(week, style: _t(12, color: _soft)),
            ],
          ),
          if (comment == null) ...[
            const SizedBox(height: 4),
            Text('No comment', style: _t(13.5, color: _soft)),
          ] else ...[
            const SizedBox(height: 6),
            Text(
              comment.text,
              style: _t(14.5, color: _words, height: 1.5),
            ),
            if (comment.hasReply) _Reply(text: comment.managementMessage),
            const SizedBox(height: 10),
            _StatusLine(status: comment.status),
          ],
        ],
      ),
    );
  }
}

/// Management's reply: a thin green line on the left, a small label,
/// and the reply in dark text.
class _Reply extends StatelessWidget {
  const _Reply({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 2, 0, 2),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: Color(0xFFBFE3CB), width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Management replied',
            style: _t(
              11.5,
              weight: FontWeight.w600,
              color: const Color(0xFF3F7C55),
            ),
          ),
          const SizedBox(height: 2),
          Text(text, style: _t(14, height: 1.45)),
        ],
      ),
    );
  }
}

/// The status in one small line: "● Under Review   Step 2 of 5",
/// "✓ Implemented", or "Noted by management".
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    if (status == FeedbackStatus.noted) {
      return Row(
        children: [
          const Icon(
            Icons.bookmark_added_outlined,
            size: 14,
            color: Color(0xFF5B6478),
          ),
          const SizedBox(width: 6),
          Text(
            'Noted by management',
            style: _t(
              12.5,
              weight: FontWeight.w500,
              color: const Color(0xFF5B6478),
            ),
          ),
        ],
      );
    }
    const steps = FeedbackStatus.steps;
    final found = steps.indexOf(status);
    final at = found < 0 ? 0 : found;
    final done = status == FeedbackStatus.implemented;
    final color = Color.lerp(_statusDot(steps[at]), AppColors.ink, 0.2)!;

    return Row(
      children: [
        if (done)
          Icon(Icons.check, size: 15, color: color)
        else
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _statusDot(steps[at]),
              shape: BoxShape.circle,
            ),
          ),
        const SizedBox(width: 6),
        Text(
          FeedbackStatus.label(steps[at]),
          style: _t(12.5, weight: FontWeight.w500, color: color),
        ),
        if (!done) ...[
          const SizedBox(width: 8),
          Text(
            'Step ${at + 1} of ${steps.length}',
            style: _t(12, color: _soft),
          ),
        ],
      ],
    );
  }
}

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

/// Rating colours for text (a little darker than the dots, so they
/// are easy to read on white).
Color _moodText(String rating) {
  switch (rating) {
    case PulseRating.great:
      return AppColors.blue;
    case PulseRating.good:
      return const Color(0xFF4C77E0);
    case PulseRating.okay:
      return const Color(0xFFC98A12);
    default:
      return const Color(0xFFD9472C);
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
    case FeedbackStatus.noted:
      return const Color(0xFF8E97AB);
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