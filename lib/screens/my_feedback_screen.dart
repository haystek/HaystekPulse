import 'package:flutter/material.dart';
import '../widgets/employee_inbox.dart';
import 'package:google_fonts/google_fonts.dart';

import '../demo_data.dart';
import '../models/employee.dart';
import '../models/feedback_item.dart';
import '../models/pulse_rating.dart';
import '../services/feedback_service.dart';
import '../services/pulse_service.dart';
import '../services/vault_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'feedback_thread_screen.dart';

/// Everything this employee has sent, in two tabs that never mix.
/// Look: a blue switch for the two tabs, blue filter chips, and each
/// item as the same row as "Your feedback" on the home screen. Tapping a
/// row opens it in a bottom sheet with the full text and the reply.
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
  return t.copyWith(
    textTheme: GoogleFonts.interTextTheme(t.textTheme),
  );
}

/// Inter for the few titles that set their own style.
TextStyle _title(double size) => GoogleFonts.inter(
  fontSize: size,
  fontWeight: FontWeight.w600,
  color: AppColors.ink,
  letterSpacing: -0.4,
);

/// The date choices.
enum _Dates { all, today, thisWeek, days30, months3, thisYear, month, week }

/// The filters that open a list to choose from.
enum _Facet { mood, status, sent }

/// "Sent" values. The words are the same as on the cards.
const String _sentNamed = 'named';
const String _sentAnon = 'anon';

/// Weekly Pulse only: a mood with nothing written.
const String _sentNone = 'none';

String _sentWords(String v) => v == _sentNamed
    ? 'With your name'
    : v == _sentAnon
    ? 'Anonymous'
    : 'No comment';

IconData _sentIcon(String v) => v == _sentNamed
    ? Icons.person_outline_rounded
    : v == _sentAnon
    ? Icons.lock_outline_rounded
    : Icons.speaker_notes_off_outlined;

/// Weekly Pulse chip for "has a reply from admin".
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
  DateTime? _boxWeek;

  /// null is All, or [_sentNamed] / [_sentAnon].
  String? _boxSent;
  bool _boxReplied = false;

  // Weekly Pulse tab.
  /// null is All, otherwise one mood.
  String? _pulseChip;

  /// null is All, otherwise one status (only answers with a comment).
  String? _pulseStatus;
  _Dates _pulseDates = _Dates.all;
  DateTime? _pulseMonth;
  DateTime? _pulseWeek;

  /// null is All, or [_sentNamed] / [_sentAnon] / [_sentNone].
  String? _pulseSent;
  bool _pulseReplied = false;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    // Live: a status change or a reply shows up without leaving the screen.
    _stream = FeedbackService.instance.watchMyFeedback(widget.employee.uid);
    _answers = _readAnswers();
    VaultService.instance.data.addListener(_onVault);
  }

  void _onVault() {
    if (mounted) setState(() => _answers = _readAnswers());
  }

  @override
  void dispose() {
    VaultService.instance.data.removeListener(_onVault);
    super.dispose();
  }

  /// Every Weekly Pulse answer of this person, also Great and Good with
  /// no comment. Null while loading.
  List<_Answer>? _answers;

  /// Every Weekly Pulse answer of this person. They are only in the
  /// person's locked history: the server never stores what someone chose.
  List<_Answer> _readAnswers() {
    final vault = VaultService.instance.data.value;
    final answers = <_Answer>[
      for (final e in (vault?.pulse ?? const <String, String>{}).entries)
        _Answer(weekId: e.key, rating: e.value),
    ];
    // Sample answers (DemoData), for weeks without a real answer.
    if (DemoData.on) {
      final have = {for (final a in answers) a.weekId};
      DemoData.myAnswers().forEach((weekId, a) {
        if (have.contains(weekId)) return;
        answers.add(_Answer(weekId: weekId, rating: a.$1, at: a.$2));
      });
    }
    return answers;
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
        _Entry(weekId: w, rating: c.rating, date: _dateOf(c), comment: c),
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
  DateTime? get _week => _tab == 0 ? _boxWeek : _pulseWeek;
  String? get _statusSel => _tab == 0 ? _status : _pulseStatus;
  String? get _sent => _tab == 0 ? _boxSent : _pulseSent;
  bool get _onlyReplied => _tab == 0 ? _boxReplied : _pulseReplied;

  /// The value chosen now for one filter.
  String? _facetValue(_Facet f) {
    switch (f) {
      case _Facet.mood:
        return _tab == 1 ? _pulseChip : null;
      case _Facet.status:
        return _statusSel;
      case _Facet.sent:
        return _sent;
    }
  }

  void _setFacet(_Facet f, String? v) {
    setState(() {
      switch (f) {
        case _Facet.mood:
          _pulseChip = v;
        case _Facet.status:
          if (_tab == 0) {
            _status = v;
          } else {
            _pulseStatus = v;
          }
        case _Facet.sent:
          if (_tab == 0) {
            _boxSent = v;
          } else {
            _pulseSent = v;
          }
      }
    });
  }

  void _toggleReplied() {
    setState(() {
      if (_tab == 0) {
        _boxReplied = !_boxReplied;
      } else {
        _pulseReplied = !_pulseReplied;
      }
    });
  }

  void _setDates(_Dates d, [DateTime? month, DateTime? week]) {
    setState(() {
      if (_tab == 0) {
        _boxDates = d;
        _boxMonth = month;
        _boxWeek = week;
      } else {
        _pulseDates = d;
        _pulseMonth = month;
        _pulseWeek = week;
      }
    });
  }

  /// Back to everything on this tab.
  void _clearAll() {
    setState(() {
      if (_tab == 0) {
        _status = null;
        _boxSent = null;
        _boxReplied = false;
        _boxDates = _Dates.all;
        _boxMonth = null;
        _boxWeek = null;
      } else {
        _pulseChip = null;
        _pulseStatus = null;
        _pulseSent = null;
        _pulseReplied = false;
        _pulseDates = _Dates.all;
        _pulseMonth = null;
        _pulseWeek = null;
      }
    });
  }

  static String _sentOf(FeedbackItem? c) =>
      c == null ? _sentNone : (c.anonymous ? _sentAnon : _sentNamed);

  static bool _sentOk(String? want, FeedbackItem? c) =>
      want == null || _sentOf(c) == want;

  static bool _boxOk(
    FeedbackItem f, {
    required String? status,
    required String? sent,
    required bool replied,
  }) =>
      (status == null || f.status == status) &&
      _sentOk(sent, f) &&
      (!replied || f.hasReply);

  static bool _pulseOk(
    _Entry e, {
    required String? mood,
    required String? status,
    required String? sent,
    required bool replied,
  }) =>
      (mood == null || e.rating == mood) &&
      (status == null || e.comment?.status == status) &&
      _sentOk(sent, e.comment) &&
      (!replied || (e.comment?.hasReply ?? false));

  /// How many show if filter [f] is set to [v] (the other filters stay).
  int _countWith(
    _Facet f,
    String? v,
    List<_Entry> entries,
    List<FeedbackItem> items,
  ) {
    final mood = f == _Facet.mood ? v : _pulseChip;
    final status = f == _Facet.status ? v : _statusSel;
    final sent = f == _Facet.sent ? v : _sent;
    if (_tab == 1) {
      return entries
          .where(
            (e) => _pulseOk(
              e,
              mood: mood,
              status: status,
              sent: sent,
              replied: _pulseReplied,
            ),
          )
          .length;
    }
    return items
        .where(
          (x) => _boxOk(x, status: status, sent: sent, replied: _boxReplied),
        )
        .length;
  }

  /// Monday 00:00 of the week [d] is in.
  static DateTime _monday(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));

  /// "Week of 23 Nov" (with the year when it is not this year).
  static String _weekTitle(DateTime mon) {
    final s = 'Week of ${mon.day} ${_shortMonths[mon.month - 1]}';
    return mon.year == DateTime.now().year ? s : '$s ${mon.year}';
  }

  /// "23 – 29 Nov" or "30 Nov – 6 Dec".
  static String _weekRange(DateTime mon) {
    final sun = DateTime(mon.year, mon.month, mon.day + 6);
    final a = mon.month == sun.month
        ? '${mon.day}'
        : '${mon.day} ${_shortMonths[mon.month - 1]}';
    return '$a – ${sun.day} ${_shortMonths[sun.month - 1]}';
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
      case _Dates.week:
        final wk = _week!;
        return _monday(d) == wk;
      case _Dates.month:
        final m = _month!;
        return d.year == m.year && d.month == m.month;
    }
  }

  /// True if [d] is in the quick choice [which] (weeks and months are
  /// counted on their own).
  static bool _inRange(DateTime d, _Dates which) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (which) {
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
      case _Dates.week:
      case _Dates.month:
        return false;
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
      case _Dates.week:
        return _weekTitle(_week!);
      case _Dates.month:
        return '${_longMonths[_month!.month - 1]} ${_month!.year}';
    }
  }

  Future<T?> _sheet<T>(Widget Function(BuildContext sheetContext) child) =>
      showModalBottomSheet<T>(
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
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.8,
              ),
              child: child(sheetContext),
            ),
          ),
        ),
      );

  /// Date sheet: Quick tiles, weeks and months, each with how many will
  /// show (the other filters are counted in). Weekly Pulse: each week
  /// shows its mood and how it was sent.
  Future<void> _openDates(
    List<DateTime> dates,
    List<_Entry>? entries,
    List<DateTime> countDates,
  ) async {
    final weeks = <DateTime>{for (final d in dates) _monday(d)}.toList()
      ..sort((a, b) => b.compareTo(a));
    final months = <DateTime>{
      for (final d in dates) DateTime(d.year, d.month, 1),
    }.toList()..sort((a, b) => b.compareTo(a));
    final byWeek = <DateTime, _Entry>{};
    for (final e in entries ?? const <_Entry>[]) {
      byWeek.putIfAbsent(_monday(e.date), () => e);
    }
    final pulse = _tab == 1;
    final thisMonday = _monday(DateTime.now());
    var showAll = false;
    int inWeek(DateTime w) => countDates.where((d) => _monday(d) == w).length;
    int inMonth(DateTime m) => countDates
        .where((d) => d.year == m.year && d.month == m.month)
        .length;
    var monthMax = 1;
    for (final m in months) {
      final n = inMonth(m);
      if (n > monthMax) monthMax = n;
    }

    void pick(BuildContext ctx, _Dates d, [DateTime? month, DateTime? week]) {
      Navigator.of(ctx).pop();
      _setDates(d, month, week);
    }

    const quick = [
      (_Dates.all, 'All dates'),
      (_Dates.today, 'Today'),
      (_Dates.thisWeek, 'This week'),
      (_Dates.days30, 'Last 30 days'),
      (_Dates.months3, 'Last 3 months'),
      (_Dates.thisYear, 'This year'),
    ];

    await _sheet<void>(
      (sheetContext) => StatefulBuilder(
        builder: (_, setSheet) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.blue, Color(0xFF4C77E0)],
                    ),
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pulse ? 'Pick a week' : 'Pick dates',
                        style: _title(18),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pulse
                            ? 'See how you answered and how you sent it.'
                            : "The number is how many suggestions you'll see.",
                        style: _t(13, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            _sheetCaps('QUICK'),
            _tileGrid([
              for (final o in quick)
                _QuickTile(
                  label: o.$2,
                  count: countDates.where((d) => _inRange(d, o.$1)).length,
                  selected: _dates == o.$1,
                  onTap: () => pick(sheetContext, o.$1),
                ),
            ]),
            if (weeks.isNotEmpty) ...[
              _sheetCaps(pulse ? 'YOUR WEEKS' : 'BY WEEK'),
              for (final w in showAll ? weeks : weeks.take(5))
                _WeekTile(
                  title: _weekTitle(w),
                  sub: [
                    _weekRange(w),
                    if (w == thisMonday) 'this week',
                  ].join(' · '),
                  pulse: pulse,
                  entry: byWeek[w],
                  count: pulse ? null : inWeek(w),
                  selected: _dates == _Dates.week && _week == w,
                  onTap: () => pick(sheetContext, _Dates.week, null, w),
                ),
              if (!showAll && weeks.length > 5)
                Center(
                  child: TextButton(
                    onPressed: () => setSheet(() => showAll = true),
                    child: Text(
                      'Show older weeks',
                      style: _t(
                        14,
                        weight: FontWeight.w600,
                        color: AppColors.blue,
                      ),
                    ),
                  ),
                ),
            ],
            if (months.isNotEmpty) ...[
              _sheetCaps('BY MONTH'),
              _tileGrid([
                for (final m in months)
                  _MonthCard(
                    name: _longMonths[m.month - 1],
                    year: m.year,
                    count: inMonth(m),
                    fraction: inMonth(m) / monthMax,
                    selected: _dates == _Dates.month && _month == m,
                    onTap: () => pick(sheetContext, _Dates.month, m),
                  ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  /// One filter's list: Mood, Status or Sent. Tap to choose; the number
  /// is how many will show.
  Future<void> _openFacet(
    _Facet f,
    List<_Entry> entries,
    List<FeedbackItem> items,
  ) async {
    final pulse = _tab == 1;
    final current = _facetValue(f);
    final String title;
    final String sub;
    // value, label, dot colour, icon
    final options = <(String?, String, Color?, IconData?)>[];
    switch (f) {
      case _Facet.mood:
        title = 'Mood';
        sub = 'How you said your week was.';
        options.add((null, 'All moods', null, null));
        for (final r in PulseRating.all.reversed) {
          options.add((r, PulseRating.label(r), _moodText(r), null));
        }
      case _Facet.status:
        title = 'Status';
        sub = pulse
            ? 'Where admin has moved your comment.'
            : 'Where admin has moved your suggestion.';
        options.add((null, 'All', null, null));
        for (final st in FeedbackStatus.all) {
          options.add(
            (st, FeedbackStatus.label(st), FeedbackStatus.color(st), null),
          );
        }
      case _Facet.sent:
        title = 'Sent';
        sub = 'With your name or anonymous.';
        options.add((null, 'All', null, null));
        for (final v in const [_sentNamed, _sentAnon]) {
          options.add((v, _sentWords(v), null, _sentIcon(v)));
        }
    }

    await _sheet<void>(
      (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        children: [
          Text(title, style: _title(18)),
          const SizedBox(height: 2),
          Text(sub, style: _t(13, color: AppColors.muted)),
          const SizedBox(height: 12),
          for (final o in options)
            _Option(
              label: o.$2,
              dot: o.$3,
              icon: o.$4,
              count: _countWith(f, o.$1, entries, items),
              selected: current == o.$1,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _setFacet(f, o.$1);
              },
            ),
        ],
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
                      text:
                          'Could not load your feedback. '
                          'Please go back and try again.',
                    );
                  }
                  if (!snap.hasData) return const _Loader();
                  final all = snap.data!;
                  final box = all.where((f) => f.isFromBox).toList();
                  final comments = all.where((f) => !f.isFromBox).toList();
                  final entries = _entries(comments);

                  final list = <Widget>[];
                  final int shownCount;
                  final int totalCount;
                  final bool nothingAtAll;
                  final List<DateTime> allDates;
                  final List<FeedbackItem> boxInDates;
                  final List<_Entry> pulseInDates;
                  String? lastMonth;
                  void monthHeader(DateTime d) {
                    final m = '${_longMonths[d.month - 1]} ${d.year}';
                    if (m != lastMonth) {
                      lastMonth = m;
                      list.add(_MonthHeader(label: m));
                    }
                  }

                  String? lastWeek;
                  void weekHeader(DateTime d) {
                    final mon = _monday(d);
                    final w = '${_weekTitle(mon)} · ${_weekRange(mon)}';
                    if (w != lastWeek) {
                      lastWeek = w;
                      list.add(_MonthHeader(label: w));
                    }
                  }

                  if (_tab == 0) {
                    boxInDates = box.where(_inDates).toList();
                    pulseInDates = const <_Entry>[];
                    final items = boxInDates
                        .where(
                          (f) => _boxOk(
                            f,
                            status: _status,
                            sent: _boxSent,
                            replied: _boxReplied,
                          ),
                        )
                        .toList();
                    for (final f in items) {
                      monthHeader(_dateOf(f));
                      list.add(_SuggestionRow(item: f));
                    }
                    shownCount = items.length;
                    totalCount = box.length;
                    nothingAtAll = box.isEmpty;
                    allDates = [for (final f in box) _dateOf(f)];
                  } else {
                    pulseInDates = entries
                        .where((e) => _inDatesAt(e.date))
                        .toList();
                    boxInDates = const <FeedbackItem>[];
                    final items = pulseInDates
                        .where(
                          (e) => _pulseOk(
                            e,
                            mood: _pulseChip,
                            status: _pulseStatus,
                            sent: _pulseSent,
                            replied: _pulseReplied,
                          ),
                        )
                        .toList();
                    for (final e in items) {
                      weekHeader(e.date);
                      list.add(_WeekRow(entry: e));
                    }
                    shownCount = items.length;
                    totalCount = entries.length;
                    nothingAtAll = entries.isEmpty;
                    allDates = [for (final e in entries) e.date];
                  }
                  final mood = _tab == 1 ? _pulseChip : null;
                  final filtersOn =
                      _dates != _Dates.all ||
                      mood != null ||
                      _statusSel != null ||
                      _sent != null ||
                      _onlyReplied;
                  final noun = _tab == 1 ? 'answer' : 'suggestion';
                  final countText = filtersOn
                      ? ' of $totalCount ${noun}s'
                      : (shownCount == 1 ? ' $noun' : ' ${noun}s');
                  // Dates of everything that matches the other filters,
                  // for the counts in the date sheet.
                  final countDates = _tab == 0
                      ? [
                          for (final f in box)
                            if (_boxOk(
                              f,
                              status: _status,
                              sent: _boxSent,
                              replied: _boxReplied,
                            ))
                              _dateOf(f),
                        ]
                      : [
                          for (final e in entries)
                            if (_pulseOk(
                              e,
                              mood: _pulseChip,
                              status: _pulseStatus,
                              sent: _pulseSent,
                              replied: _pulseReplied,
                            ))
                              e.date,
                        ];
                  // Rows under each month go in one white panel.
                  final grouped = <Widget>[];
                  var group = <Widget>[];
                  void flush() {
                    if (group.isEmpty) return;
                    grouped.add(EmployeeInboxPanel(
                      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      children: group,
                    ));
                    group = <Widget>[];
                  }
                  for (final w in list) {
                    if (w is _MonthHeader) {
                      flush();
                      grouped.add(w);
                    } else {
                      group.add(w);
                    }
                  }
                  flush();
                  list
                    ..clear()
                    ..addAll(grouped);
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
                        // Every filter, each one separate.
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _FilterPill(
                                icon: Icons.calendar_today_outlined,
                                label: _dates == _Dates.all
                                    ? 'Date'
                                    : _datesLabel(),
                                active: _dates != _Dates.all,
                                onTap: () => _openDates(
                                  allDates,
                                  _tab == 1 ? entries : null,
                                  countDates,
                                ),
                                onClear: () => _setDates(_Dates.all),
                              ),
                              if (_tab == 1)
                                _FilterPill(
                                  icon: Icons.mood_outlined,
                                  label: mood == null
                                      ? 'Mood'
                                      : PulseRating.label(mood),
                                  active: mood != null,
                                  onTap: () => _openFacet(
                                    _Facet.mood,
                                    pulseInDates,
                                    boxInDates,
                                  ),
                                  onClear: () => _setFacet(_Facet.mood, null),
                                ),
                              _FilterPill(
                                icon: Icons.flag_outlined,
                                label: _statusSel == null
                                    ? 'Status'
                                    : FeedbackStatus.label(_statusSel!),
                                active: _statusSel != null,
                                onTap: () => _openFacet(
                                  _Facet.status,
                                  pulseInDates,
                                  boxInDates,
                                ),
                                onClear: () => _setFacet(_Facet.status, null),
                              ),
                              _FilterPill(
                                icon: _sent == null
                                    ? Icons.person_outline_rounded
                                    : _sentIcon(_sent!),
                                label: _sent == null
                                    ? 'Sent'
                                    : _sentWords(_sent!),
                                active: _sent != null,
                                onTap: () => _openFacet(
                                  _Facet.sent,
                                  pulseInDates,
                                  boxInDates,
                                ),
                                onClear: () => _setFacet(_Facet.sent, null),
                              ),
                              _FilterPill(
                                icon: Icons.chat_bubble_outline,
                                label: 'Admin replied',
                                active: _onlyReplied,
                                dropdown: false,
                                onTap: _toggleReplied,
                                onClear: _toggleReplied,
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 6, 12, 0),
                          child: SizedBox(
                            height: 40,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '$shownCount',
                                          style: _t(
                                            13.5,
                                            weight: FontWeight.w700,
                                          ),
                                        ),
                                        TextSpan(
                                          text: countText,
                                          style: _t(13.5, color: _soft),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (filtersOn)
                                  TextButton(
                                    onPressed: _clearAll,
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppColors.blue,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                    ),
                                    child: Text(
                                      'Clear all',
                                      style: _t(
                                        13.5,
                                        weight: FontWeight.w600,
                                        color: AppColors.blue,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (shownCount == 0)
                          _FeedbackEmpty(
                            icon: !nothingAtAll
                                ? Icons.filter_alt_off_outlined
                                : (_tab == 0
                                      ? Icons.lightbulb_outline_rounded
                                      : Icons.monitor_heart_outlined),
                            title: !nothingAtAll
                                ? 'Nothing matches'
                                : (_tab == 0
                                      ? 'No suggestions yet'
                                      : 'No Weekly Pulse answers yet'),
                            text: !nothingAtAll
                                ? 'Try another filter, or tap Clear all.'
                                : (_tab == 0
                                      ? 'Have an idea or a problem? Tap Write on '
                                            'the home screen. Admin will reply here.'
                                      : 'Each week you get one quick question '
                                            'about your week. Your answers will '
                                            'show here.'),
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
const Color _soft = Color(0xCC0E1A3A);

/// Grey for the employee's own words in a Weekly Pulse comment.
const Color _words = Color(0xFF5B6680);

/// Thin borders around cards and chips.
const Color _line = Color(0xFFE3E8F1);

/// Light grey for the tab switch.
const Color _panel = Color(0xFFF6F8FB);

/// "Admin replied" in green.
const Color _replyFg = Color(0xFF15803D);

/// Inter with a chosen size, weight and colour.
TextStyle _t(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.ink,
  double? height,
  double? letterSpacing,
}) => GoogleFonts.inter(
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
        side: BorderSide(color: selected ? AppColors.blue : _line, width: 1.2),
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

/// One row, the same look as "Your feedback" on the home screen: a white
/// card with a thin border, an icon tile on the left, then
///   type (blue) + status chip
///   the text, one line
///   date / week, and "Admin replied" in green
/// and the arrow on the right, in the middle.
class EmployeeFeedbackCard extends StatelessWidget {
  const EmployeeFeedbackCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.kind,
    required this.title,
    required this.sub,
    this.titleColor = AppColors.ink,
    this.status,
    this.replied = false,
    this.onTap,
    this.label,
    this.anonymous, this.sentName,
    this.margin = const EdgeInsets.fromLTRB(20, 0, 20, 12),
  });

  /// Space around the card (Home uses none, it has its own).
  final EdgeInsets margin;

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String kind;
  final String title;
  final Color titleColor;
  final String sub;
  final String? status;
  final bool replied;

  /// Top label in capitals, e.g. GREAT. Defaults to [kind].
  final String? label;

  /// Ma'am: sent anonymously or with name (null: nothing was written).
  final bool? anonymous;
  final String? sentName;

  /// Opens the conversation. Null: nothing more to show (Great / Good),
  /// so the card can't be tapped and has no arrow.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // S2 pulse card: same look as the Suggestion cards.
    final top = (label ?? kind).toUpperCase();
    return Padding(
      padding: margin,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: _line, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: iconColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                top,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _t(
                                  12.5,
                                  weight: FontWeight.w600,
                                  color: iconColor,
                                ).copyWith(letterSpacing: 1.1),
                              ),
                            ),
                            if (anonymous != null) ...[
                              _sentAs(anonymous!, sentName),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _t(16, color: AppColors.ink)
                              .copyWith(height: 1.4),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                sub,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _t(13, color: _soft),
                              ),
                            ),
                            if (replied) ...[
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.chat_bubble_outline,
                                size: 16,
                                color: _replyFg,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Admin replied',
                                style: _t(
                                  13,
                                  weight: FontWeight.w600,
                                  color: _replyFg,
                                ),
                              ),
                            ],
                            if (status != null) ...[
                              const SizedBox(width: 8),
                              _StatusChip(status: status!),
                            ],
                          ],
                        ),
                      ],
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

/// One suggestion. Tap for the full text and the conversation.
class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.item});

  final FeedbackItem item;

  @override
  Widget build(BuildContext context) => EmployeeInboxRow(
    isBox: true,
    status: item.status,
    title: item.text.trim(),
    sub: EmployeeInboxRow.shortDate(item.createdAt),
    hasReply: item.hasReply,
    anonymous: item.anonymous,
    sentName: item.authorName,
    onTap: () => _showFeedbackSheet(context, item),
  );
}

/// One Weekly Pulse week: the comment, or "You said Great" when there
/// is no comment (that one can't be tapped).
class _WeekRow extends StatelessWidget {
  const _WeekRow({required this.entry});

  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    final rating = entry.rating;
    final comment = entry.comment;
    final weekId = entry.weekId;
    final said = rating == null ? '' : 'You said ${PulseRating.label(rating)}';
    final mood = rating == null ? null : PulseRating.color(rating);

    // With a comment: the comment, "You said Good · 11 Nov".
    if (comment != null) {
      return EmployeeInboxRow(
        isBox: false,
        status: comment.status,
        title: comment.text.trim(),
        sub: [said, EmployeeInboxRow.shortDate(comment.createdAt ?? entry.date)]
            .where((x) => x.isNotEmpty)
            .join(' · '),
        hasReply: comment.hasReply,
        anonymous: comment.anonymous,
        sentName: comment.authorName,
        onTap: () => _showFeedbackSheet(context, comment),
      );
    }
    // No comment: "You said Good" and the week (can't be tapped).
    return EmployeeInboxRow(
      isBox: false,
      title: said.isEmpty ? 'Weekly Pulse' : said,
      titleColor: mood,
      barColor: mood,
      sub: weekId == null ? '' : 'Week of ${PulseService.weekLabel(weekId)}',
    );
  }
}

/// Opens one suggestion or Weekly Pulse comment with its conversation.
/// Used by the Notifications screen too.
void showMyFeedbackSheet(BuildContext context, FeedbackItem f) =>
    _showFeedbackSheet(context, f);

/// Opens the conversation screen (full text, replies, reply box).
void _showFeedbackSheet(BuildContext context, FeedbackItem f) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => FeedbackThreadScreen(item: f)),
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
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const List<String> _longMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// My Feedback, nothing here yet: icon, title and a short line.
class _FeedbackEmpty extends StatelessWidget {
  const _FeedbackEmpty({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        32,
        MediaQuery.sizeOf(context).height * 0.12,
        32,
        32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              color: Color(0xFFF5F7FF),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFE6ECFF),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: const Color(0xFF1B3590)),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: t.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: t.bodyMedium?.copyWith(
              fontSize: 14,
              height: 1.5,
              color: const Color(0xCC0E1A3A),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ma'am: "Anonymous" or "With your name" on each sent message.
Widget _sentAs(bool anonymous, [String? name]) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Icon(
      anonymous ? Icons.lock_outline_rounded : Icons.person_outline_rounded,
      size: 13,
      color: _soft,
    ),
    const SizedBox(width: 3),
    Text(
      anonymous ? 'Anonymous' : ((name ?? '').trim().isEmpty ? 'With your name' : (name ?? '').trim()),
      style: _t(12, color: _soft),
    ),
  ],
);

/// "16 Nov" (this year) or "16 Nov 2025".
String _empShortDate(DateTime? d) {
  if (d == null) return '';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
      'Sep', 'Oct', 'Nov', 'Dec'];
  final s = '${d.day} ${months[d.month - 1]}';
  return d.year == DateTime.now().year ? s : '$s ${d.year}';
}

/// Small grey capitals in a sheet: "YOUR WEEKS", "OR A MONTH".
Widget _sheetCaps(String text) => Padding(
  padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
  child: Text(text, style: _caps(AppColors.muted)),
);

String _howMany(int n) => n == 1 ? '1 suggestion' : '$n suggestions';

/// A filter in the bar: icon, name, ▾. When set: blue, with ✕.
/// [dropdown] false: an on/off filter (Admin replied), no ▾.
class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    required this.onClear,
    this.dropdown = true,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClear;
  final bool dropdown;

  @override
  Widget build(BuildContext context) {
    final c = active ? AppColors.blue : AppColors.muted;
    return Semantics(
      button: true,
      selected: active,
      child: Material(
        color: active ? AppColors.blueTint : Colors.white,
        shape: StadiumBorder(
          side: BorderSide(color: active ? AppColors.blue : _line, width: 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 36,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                0,
                active ? 4 : (dropdown ? 8 : 12),
                0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: c),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: _t(
                      13,
                      weight: active ? FontWeight.w600 : FontWeight.w500,
                      color: active ? AppColors.blue : AppColors.ink,
                    ),
                  ),
                  if (active)
                    InkResponse(
                      onTap: onClear,
                      radius: 18,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.close_rounded,
                          size: 15,
                          color: AppColors.blue,
                        ),
                      ),
                    )
                  else if (dropdown)
                    Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: c),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A round choice in a sheet (dates, months).
class _Choice extends StatelessWidget {
  const _Choice({
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
      color: selected ? AppColors.blueTint : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? AppColors.blue : _line, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: _t(
              13.5,
              weight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? AppColors.blue : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// A wide option in a filter sheet, with the count on the right.
class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.icon,
    this.dot,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final c = selected ? AppColors.blue : AppColors.ink;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppColors.blueTint : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? AppColors.blue : _line, width: 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            child: Row(
              children: [
                if (dot != null) ...[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                ] else if (icon != null) ...[
                  Icon(icon, size: 18, color: c),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: _t(
                      15,
                      weight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: c,
                    ),
                  ),
                ),
                Text(
                  '$count',
                  style: _t(
                    13.5,
                    weight: FontWeight.w600,
                    color: selected ? AppColors.blue : _soft,
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

/// Three tiles in a row.
Widget _tileGrid(List<Widget> tiles) => LayoutBuilder(
  builder: (context, box) {
    final w = (box.maxWidth - 16) / 3;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final t in tiles) SizedBox(width: w, child: t)],
    );
  },
);

/// A quick date choice: the count large, the name below.
class _QuickTile extends StatelessWidget {
  const _QuickTile({
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
    final zero = count == 0 && !selected;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: Color(0x401F46D8),
                  blurRadius: 14,
                  offset: Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: Material(
        color: selected ? AppColors.blue : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? AppColors.blue : _line,
            width: 1.2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 78),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$count',
                    style: _t(
                      21,
                      weight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: selected
                          ? Colors.white
                          : (zero ? const Color(0xFFC3C9D6) : AppColors.ink),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 2,
                    style: _t(
                      12.5,
                      height: 1.25,
                      color: selected
                          ? Colors.white.withValues(alpha: 0.9)
                          : AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A month: name, year · count, and a small bar (busy months fuller).
class _MonthCard extends StatelessWidget {
  const _MonthCard({
    required this.name,
    required this.year,
    required this.count,
    required this.fraction,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final int year;
  final int count;
  final double fraction;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.blueTint : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? AppColors.blue : _line, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  name,
                  style: _t(
                    15,
                    weight: FontWeight.w600,
                    color: selected ? AppColors.blue : AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text('$year · $count', style: _t(12, color: _soft)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 5,
                  child: Stack(
                    children: [
                      const Positioned.fill(
                        child: ColoredBox(color: Color(0xFFEEF1F6)),
                      ),
                      FractionallySizedBox(
                        widthFactor: fraction.clamp(0.0, 1.0),
                        heightFactor: 1,
                        alignment: Alignment.centerLeft,
                        child: const ColoredBox(color: Color(0xFF4C77E0)),
                      ),
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

/// One week in the date sheet.
/// Weekly Pulse: the mood on the left; on the right "With your name" or
/// "Anonymous" (nothing for Good / Great: no comment is possible).
/// Suggestions: how many on the right.
class _WeekTile extends StatelessWidget {
  const _WeekTile({
    required this.title,
    required this.sub,
    required this.pulse,
    required this.entry,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String title;
  final String sub;
  final bool pulse;
  final _Entry? entry;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final rating = e?.rating;
    final known = rating != null && PulseRating.all.contains(rating);
    final color = known ? _moodText(rating!) : AppColors.blue;
    final c = e?.comment;

    final Widget lead = pulse && e != null
        ? Container(
            width: 58,
            height: 36,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                known ? PulseRating.label(rating!) : '–',
                style: _t(12, weight: FontWeight.w700, color: color),
              ),
            ),
          )
        : Container(
            width: 58,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.blueTint,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.calendar_today_outlined,
              size: 16,
              color: AppColors.blue,
            ),
          );

    // Sent on the dates line.
    Widget? sentLine;
    if (pulse && c != null) {
      final v = c.anonymous ? _sentAnon : _sentNamed;
      sentLine = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_sentIcon(v), size: 13, color: AppColors.muted),
          const SizedBox(width: 4),
          Text(_sentWords(v), style: _t(12, color: AppColors.muted)),
        ],
      );
    }
    Widget? trail;
    if (!pulse && count != null) {
      trail = Container(
        constraints: const BoxConstraints(minWidth: 26),
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.blue : const Color(0xFFF0F3F8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '$count',
          style: _t(
            12.5,
            weight: FontWeight.w700,
            color: selected ? Colors.white : const Color(0xFF3B4560),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? AppColors.blueTint : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? AppColors.blue : const Color(0xFFEEF1F6),
            width: 1.2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
            child: Row(
              children: [
                lead,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: _t(14.5, weight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _t(12, color: AppColors.muted),
                            ),
                          ),
                          if (sentLine != null) ...[
                            const SizedBox(width: 8),
                            sentLine,
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (trail != null) ...[const SizedBox(width: 8), trail],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
