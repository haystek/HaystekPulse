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
/// Look ("cards" design): a blue switch for the two tabs, blue filter
/// chips, and each item as a white card with a thin border: an icon, the
/// status chip and the date on top, the words (2 lines), and "Management
/// replied" on its own line when there is a reply. Tapping a card opens
/// it in a bottom sheet with the full text and the reply.
/// Light font weights, nothing heavy.
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
  fontWeight: FontWeight.w600,
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
          // No title on the left: the name sits on the right in a rounded pill.
          title: const SizedBox.shrink(),
          actions: const [
            _TitlePill('My Feedback', icon: Icons.chat_bubble_outline),
          ],
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
                      // The two tabs: a light grey switch, the chosen one
                      // blue.
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: _panel,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _Tab(
                                  label: 'Suggestions',
                                  count: box.length,
                                  selected: _tab == 0,
                                  onTap: () => setState(() => _tab = 0),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: _Tab(
                                  label: 'Weekly Pulse',
                                  count: entries.length,
                                  selected: _tab == 1,
                                  onTap: () => setState(() => _tab = 1),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Still loading the weeks: only the loader, in the
                      // middle of the space under the tabs.
                      if (loadingWeeks)
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.55,
                          child: const _Loader(),
                        )
                      else ...[
                        // Chips for this tab.
                        SizedBox(
                          height: 34,
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
                        const SizedBox(height: 4),
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
const Color _soft = Color(0xFF8E97AB);

/// Grey for the employee's own words in a Weekly Pulse comment.
const Color _words = Color(0xFF5B6680);

/// Thin borders around cards and chips.
const Color _line = Color(0xFFE3E8F1);

/// The thin line above "Management replied".
const Color _divider = Color(0xFFEDF0F5);

/// Light grey for the tab switch.
const Color _panel = Color(0xFFF6F8FB);

/// Management's reply: light green box, green label.
const Color _replyBg = Color(0xFFE8F7EE);
const Color _replyFg = Color(0xFF15803D);

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
    _t(11, weight: FontWeight.w500, color: color, letterSpacing: 1.1);

// ---------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------

/// A small blue loader in the middle of the space it is given.
class _Loader extends StatelessWidget {
  const _Loader();

  @override
  Widget build(BuildContext context) {
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

/// One tab in the switch: name and a small count. The chosen one is
/// blue with white text.
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
      child: Material(
        color: selected ? AppColors.blue : Colors.transparent,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 38,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _t(
                      14,
                      weight: FontWeight.w500,
                      color: selected ? Colors.white : AppColors.muted,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.22)
                        : _line,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: _t(
                      11.5,
                      weight: FontWeight.w500,
                      color: selected ? Colors.white : AppColors.muted,
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

/// A filter chip: white with a thin border. The chosen one is blue.
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
      color: selected ? AppColors.blue : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? AppColors.blue : _line,
          width: 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: _t(
                13,
                weight: FontWeight.w500,
                color: selected ? Colors.white : AppColors.muted,
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
        backgroundColor: active ? AppColors.blueTint : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        minimumSize: const Size(0, 34),
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_today_outlined, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: _t(13, weight: FontWeight.w500, color: AppColors.blue),
          ),
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
      padding: const EdgeInsets.fromLTRB(22, 16, 20, 8),
      child: Text(label.toUpperCase(), style: _caps(_soft)),
    );
  }
}

/// The base of every item ("text first" design): a white card with a
/// thin border. Top line: chips on the left, the date on the right. Then
/// up to 2 lines of text. When management has replied, a thin line and
/// "Management replied" on its own line. The arrow sits in the middle on
/// the right.
class _Card extends StatelessWidget {
  const _Card({
    required this.chips,
    required this.date,
    required this.body,
    this.replied = false,
    this.onTap,
  });

  final List<Widget> chips;
  final String date;
  final Widget body;
  final bool replied;

  /// Opens the bottom sheet. Null: nothing more to show (Great / Good),
  /// so the card can't be tapped and has no arrow.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: _line, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 14, onTap == null ? 16 : 8, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Chips on the left, date on the right.
                      Row(
                        children: [
                          for (var i = 0; i < chips.length; i++) ...[
                            if (i > 0) const SizedBox(width: 6),
                            chips[i],
                          ],
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              date,
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _t(12, color: _soft),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      body,
                      if (replied) ...[
                        const SizedBox(height: 10),
                        const Divider(height: 1, thickness: 1, color: _divider),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(
                              Icons.chat_bubble_outline,
                              size: 14,
                              color: _replyFg,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Management replied',
                              style: _t(
                                12.5,
                                weight: FontWeight.w500,
                                color: _replyFg,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right, color: _soft),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Up to 2 lines of the person's own words.
Widget _twoLines(String text, {Color color = AppColors.ink}) => Text(
  text,
  maxLines: 2,
  overflow: TextOverflow.ellipsis,
  style: _t(14.5, color: color, height: 1.45),
);

/// One suggestion: status and date, the words, and whether management
/// replied. Tap for the full text and the reply.
class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.item});

  final FeedbackItem item;

  @override
  Widget build(BuildContext context) {
    final date = item.createdAt ?? DateTime.now();
    return _Card(
      chips: [_StatusChip(status: item.status)],
      date: '${date.day} ${_shortMonths[date.month - 1]} · '
          '${item.anonymous ? 'Name hidden' : 'With your name'}',
      body: _twoLines(item.text),
      replied: item.hasReply,
      onTap: () => _showFeedbackSheet(context, item),
    );
  }
}

/// One Weekly Pulse week: the answer (and the status when there is a
/// comment) with the week, then the comment, or "You said Great".
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
        : (name.isNotEmpty ? name : 'Week of ${PulseService.weekLabel(weekId)}');

    return _Card(
      chips: [
        if (rating != null) _RatingChip(rating: rating),
        if (comment != null) _StatusChip(status: comment.status),
      ],
      date: week,
      body: comment != null
          ? _twoLines(comment.text)
          : Text(
        rating == null
            ? 'Weekly Pulse'
            : 'You said ${PulseRating.label(rating)}',
        style: _t(
          14.5,
          weight: FontWeight.w500,
          color: rating == null ? AppColors.blue : _moodText(rating),
        ),
      ),
      replied: comment?.hasReply ?? false,
      // Only a written comment opens. Great / Good have nothing more.
      onTap: comment == null ? null : () => _showFeedbackSheet(context, comment),
    );
  }
}

/// The answer as a small chip in its own colour: "Difficult", "Great".
class _RatingChip extends StatelessWidget {
  const _RatingChip({required this.rating});

  final String rating;

  @override
  Widget build(BuildContext context) {
    final color = PulseRating.color(rating);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PulseRating.icon(rating), size: 13, color: _moodText(rating)),
          const SizedBox(width: 4),
          Text(
            PulseRating.label(rating),
            style: _t(11.5, weight: FontWeight.w500, color: _moodText(rating)),
          ),
        ],
      ),
    );
  }
}

/// "21 Oct 2026, 7:45 PM".
String _fullDate(DateTime? d) {
  if (d == null) return '';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${_shortMonths[d.month - 1]} ${d.year}, '
      '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// One suggestion or Weekly Pulse comment in a sheet from the bottom:
/// type and status, the full text, when it was sent and whether the name
/// was hidden, and management's reply. Swipe down or tap Close.
/// Same as the one on the home screen.
void _showFeedbackSheet(BuildContext context, FeedbackItem f) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      final maxH = MediaQuery.of(context).size.height * 0.85;
      final rating = f.rating;
      final weekId = f.weekId;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Type and status.
                      Row(
                        children: [
                          Icon(
                            f.isFromBox
                                ? Icons.lightbulb_outline
                                : (rating != null
                                ? PulseRating.icon(rating)
                                : Icons.favorite_border),
                            size: 18,
                            color: f.isFromBox || rating == null
                                ? AppColors.blue
                                : PulseRating.color(rating),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            f.isFromBox ? 'Suggestion' : 'Weekly Pulse',
                            style: _t(
                              13.5,
                              weight: FontWeight.w500,
                              color: AppColors.blue,
                            ),
                          ),
                          const Spacer(),
                          _StatusChip(status: f.status),
                        ],
                      ),
                      if (!f.isFromBox && rating != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'You said ${PulseRating.label(rating)}'
                              '${weekId != null ? ' · Week of ${PulseService.weekLabel(weekId)}' : ''}',
                          style: _t(13, color: AppColors.muted),
                        ),
                      ],
                      const SizedBox(height: 14),

                      // The full text.
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _panel,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: SelectableText(
                          f.text,
                          style: _t(15.5, height: 1.5),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // When, and whether the name was hidden.
                      Row(
                        children: [
                          Icon(
                            f.anonymous
                                ? Icons.lock_outline
                                : Icons.person_outline,
                            size: 15,
                            color: _soft,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              [
                                _fullDate(f.createdAt),
                                f.anonymous
                                    ? 'Name hidden'
                                    : 'Sent with your name',
                              ].where((x) => x.isNotEmpty).join(' · '),
                              style: _t(12.5, color: _soft),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Management's reply.
                      Text('MANAGEMENT REPLY', style: _caps(AppColors.muted)),
                      const SizedBox(height: 8),
                      if (f.hasReply)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _replyBg,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                f.managementMessage,
                                style: _t(15, height: 1.5),
                              ),
                              if (f.updatedAt != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  _fullDate(f.updatedAt),
                                  style: _t(12, color: _replyFg),
                                ),
                              ],
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: _line, width: 1.5),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.schedule,
                                size: 18,
                                color: _soft,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'No reply yet. You’ll get a notification '
                                      'when management replies.',
                                  style: _t(
                                    13.5,
                                    color: AppColors.muted,
                                    height: 1.4,
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    minimumSize: const Size.fromHeight(52),
                    shape: const StadiumBorder(),
                    textStyle: _t(15.5, weight: FontWeight.w500),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// A small coloured chip with the status, same colours as the home
/// screen: New amber, Under Review and In Progress blue, Planned teal,
/// Noted grey, Implemented green.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = _statusColors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        FeedbackStatus.label(status),
        style: _t(11.5, weight: FontWeight.w500, color: fg),
      ),
    );
  }
}

/// Screen name on the right of the AppBar: pill with an icon.
/// Same as the Suggestion Box and Weekly Pulse.
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
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.normal,
                color: AppColors.ink,
                letterSpacing: -0.4,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
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

/// Text colour and light background of each status chip.
(Color, Color) _statusColors(String status) {
  switch (status) {
    case FeedbackStatus.newItem:
      return (const Color(0xFFB7791F), const Color(0xFFFFF6E5));
    case FeedbackStatus.underReview:
    case FeedbackStatus.inProgress:
      return (AppColors.blue, AppColors.blueTint);
    case FeedbackStatus.planned:
      return (const Color(0xFF0F766E), const Color(0xFFE6F6F5));
    case FeedbackStatus.noted:
      return (const Color(0xFF5B6478), const Color(0xFFEEF0F4));
    default:
      return (const Color(0xFF15803D), const Color(0xFFE8F7EE));
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
