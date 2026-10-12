import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config.dart';
import '../demo_data.dart';
import '../models/employee.dart';
import '../models/feedback_item.dart';
import '../models/pulse_rating.dart';
import '../models/pulse_totals.dart';
import '../services/feedback_service.dart';
import '../services/pulse_service.dart';
import '../services/push_sender.dart';
import '../theme/app_theme.dart';
import '../widgets/notification_bell.dart';
import '../widgets/ui.dart';
import 'all_weeks_screen.dart';
import 'feedback_detail_screen.dart';
import 'feedback_list_screen.dart';
import 'profile_screen.dart';

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

/// Management home, in two tabs:
/// - Weekly Pulse: a week's results and that week's written comments.
///   Everything on this tab follows the week chosen with the arrows.
/// - Suggestion Box: suggestions by status. Not tied to any week.
class ManagementHomeScreen extends StatefulWidget {
  const ManagementHomeScreen({super.key, required this.employee});

  final Employee employee;

  @override
  State<ManagementHomeScreen> createState() => _ManagementHomeScreenState();
}

class _ManagementHomeScreenState extends State<ManagementHomeScreen>
    with WidgetsBindingObserver {
  /// The week the window is on now (open, or most recently open).
  late String _weekId;

  /// The week management chose with the arrows. Null means "follow the
  /// clock": last week until the window opens, then this week.
  String? _viewWeekId;
  late Future<int> _totalEmployees;
  late final Stream<List<FeedbackItem>> _feedback;

  /// The totals of every week, live. Used for the heartbeat line.
  late final Stream<Map<String, PulseTotals>> _weeks;
  bool _sending = false;

  /// True while Refresh is loading. Shows a spinner in the center.
  bool _refreshing = false;
  int _tab = 0;

  /// When back was last pressed on the home screen.
  DateTime? _lastBack;

  /// Phone back button: first go to the Weekly Pulse tab, then ask to
  /// press again before closing the app.
  void _onBack() {
    if (_tab != 0) {
      setState(() => _tab = 0);
      return;
    }
    final now = DateTime.now();
    if (_lastBack != null &&
        now.difference(_lastBack!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBack = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Press back again to close the app'),
          duration: Duration(seconds: 2),
        ),
      );
  }
  bool _windowOpen = PulseService.isOpen();
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _feedback = FeedbackService.instance.watchAll();
    _weeks = FirebaseFirestore.instance.collection('pulse_weeks').snapshots().map(
          (snap) => {
        for (final doc in snap.docs)
          doc.id: PulseTotals.fromMap(doc.data()),
      },
    );
    _load();
    WidgetsBinding.instance.addObserver(this);
    // Look at the clock every 5 seconds, so the screen changes by itself
    // when the window opens or closes and when a new week starts.
    _clock = Timer.periodic(const Duration(seconds: 5), (_) => _checkClock());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When management comes back to the app: check the clock and count
    // the employees again, in case someone was added or removed.
    if (state == AppLifecycleState.resumed && mounted) {
      setState(_load);
      _checkClock();
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Redraws only when something really changed.
  void _checkClock() {
    if (!mounted) return;
    final open = PulseService.isOpen();
    final weekId = PulseService.currentWeekId();
    if (open == _windowOpen && weekId == _weekId) return;
    setState(() {
      _windowOpen = open;
      if (weekId != _weekId) _load();
    });
  }

  void _load() {
    _weekId = PulseService.currentWeekId();
    _totalEmployees = PulseService.instance.countEmployees();
  }

  /// Loads everything again, with a spinner in the center.
  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _windowOpen = PulseService.isOpen();
      _load();
    });
    try {
      await Future.wait([
        _totalEmployees,
        Future<void>.delayed(const Duration(milliseconds: 800)),
      ]);
    } catch (_) {
      // The screen itself shows the error.
    }
    if (mounted) setState(() => _refreshing = false);
  }

  /// The week on screen: the one management picked, or else this week
  /// (Monday to Friday), even before its window opens.
  String get _shownWeekId => _viewWeekId ?? PulseService.thisWeekId();

  void _pickWeek(String weekId) {
    setState(
          () => _viewWeekId =
      weekId == PulseService.thisWeekId() ? null : weekId,
    );
  }

  Future<void> _openAllWeeks() async {
    final chosen = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => AllWeeksScreen(
          totalEmployees: _totalEmployees,
          selectedWeekId: _shownWeekId,
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(
          () => _viewWeekId =
      chosen == PulseService.thisWeekId() ? null : chosen,
    );
  }



  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  /// Asks first, then sends, then says whether it went out.
  Future<void> _confirmAndSend({
    required String title,
    required String question,
    required Future<bool> Function() send,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _withInter(dialogContext, AlertDialog(
        title: Text(title),
        content: Text(question),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Send'),
          ),
        ],
      )),
    );
    if (yes != true || !mounted) return;
    setState(() => _sending = true);
    final ok = await send();
    if (!mounted) return;
    setState(() => _sending = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Notification sent.'
              : 'Could not send the notification. Please try again.',
        ),
      ),
    );
  }

  void _remind() {
    _confirmAndSend(
      title: 'Send a reminder?',
      question:
      'Only employees who have not answered this week will '
          'receive it.',
      send: PulseService.instance.remindPending,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FeedbackItem>>(
      stream: _feedback,
      builder: (context, snap) {
        final all = snap.data ?? const <FeedbackItem>[];
        final suggestions = all.where((f) => f.isFromBox).toList();
        final newCount = suggestions
            .where((f) => f.status == FeedbackStatus.newItem)
            .length;

        // Design C keeps the top bar light on both tabs.
        const onBlue = false;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) _onBack();
          },
          child: _withInter(context, Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top bar. On the Weekly Pulse tab it is blue, and the blue
                // carries on into the week block below it.
                Container(
                  color: onBlue ? AppColors.blue : AppColors.background,
                  child: SafeArea(
                    bottom: false,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                          child: Row(
                            children: [
                              Container(
                                padding: onBlue
                                    ? const EdgeInsets.fromLTRB(10, 6, 10, 6)
                                    : EdgeInsets.zero,
                                decoration: onBlue
                                    ? BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                )
                                    : null,
                                child: Wordmark(height: onBlue ? 26 : 34),
                              ),
                              const Spacer(),
                              NotificationBell(employee: widget.employee),
                              const SizedBox(width: 8),
                              _AccountButton(
                                name: widget.employee.name,
                                onBlue: onBlue,
                                actions: [
                                  MenuAction(
                                    'Profile',
                                        () => _push(
                                      ProfileScreen(employee: widget.employee),
                                    ),
                                  ),
                                  MenuAction('Refresh', _refresh),
                                  MenuAction(
                                    'Sign out',
                                        () => confirmSignOut(context),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Stack(
                        children: [
                          IndexedStack(
                            index: _tab,
                            children: [
                              _buildPulseTab(all),
                              _SuggestionTab(
                                suggestions: suggestions,
                                loading: !snap.hasData && !snap.hasError,
                                onOpen: (item) =>
                                    _push(FeedbackDetailScreen(item: item)),
                                onSearch: () =>
                                    _push(const FeedbackListScreen(source: 'box')),
                              ),
                            ],
                          ),
                          // Refresh: a light white cover with a spinner in
                          // the center.
                          if (_refreshing)
                            const Positioned.fill(
                              child: ColoredBox(
                                color: Color(0xB3FFFFFF),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              backgroundColor: Colors.white,
              indicatorColor: AppColors.blueTint,
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.monitor_heart_outlined),
                  selectedIcon: Icon(Icons.monitor_heart, color: AppColors.blue),
                  label: 'Weekly Pulse',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: newCount > 0,
                    label: Text('$newCount'),
                    child: const Icon(Icons.edit_outlined),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: newCount > 0,
                    label: Text('$newCount'),
                    child: const Icon(Icons.edit, color: AppColors.blue),
                  ),
                  label: 'Suggestion Box',
                ),
              ],
            ),
          )),
        );
      },
    );
  }

  /// Tab 1. Week cards to pick a week, a ring with the answers, one
  /// remind button, and the week's comments.
  Widget _buildPulseTab(List<FeedbackItem> all) {
    final canNotify = PushSender.available;
    final shown = _shownWeekId;
    final thisWeek = PulseService.thisWeekId();
    // Only before this week's window opens (not after it closed).
    final notOpenYet = !_windowOpen &&
        shown == thisWeek &&
        DateTime.now().isBefore(_opensAt(thisWeek));
    final comments = all
        .where((f) => !f.isFromBox && f.weekId == shown)
        .toList();

    return FutureBuilder<int>(
      future: _totalEmployees,
      builder: (context, totalSnap) {
        return StreamBuilder<Map<String, PulseTotals>>(
          stream: _weeks,
          builder: (context, weekSnap) {
            if (totalSnap.hasError || weekSnap.hasError) {
              return const _CenterNote(
                'Could not load the Weekly Pulse. Open the menu at the top '
                    'right and choose Refresh.',
              );
            }
            if (!totalSnap.hasData || !weekSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final weeks = <String, PulseTotals>{
              if (DemoData.on) ...DemoData.weeks(thisWeek),
              ...weekSnap.data!,
            };
            final total = DemoData.on ? DemoData.people : totalSnap.data!;
            final totals = weeks[shown] ?? const PulseTotals();
            final pending =
            total > totals.submitted ? total - totals.submitted : 0;

            // The first week the app was used: the oldest week with any
            // answers, or this week when nobody has answered yet. The back
            // arrow stops there.
            var firstWeek = thisWeek;
            for (final id in weeks.keys) {
              if (id.compareTo(firstWeek) < 0) firstWeek = id;
            }

            // Every week from the first one up to this week, newest first.
            final weekIds = <String>[];
            for (var id = thisWeek;
            id.compareTo(firstWeek) >= 0 && weekIds.length < 26;
            id = PulseService.shiftWeek(id, -1)) {
              weekIds.add(id);
            }

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 28),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Weekly Pulse',
                          style: _h(24, weight: FontWeight.w800),
                        ),
                      ),
                      // Search Weekly Pulse comments only.
                      Material(
                        color: const Color(0xFFF2F6FF),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Search comments',
                          onPressed: () => _push(
                            const WeekCommentsScreen(
                              weekId: null,
                              focusSearch: true,
                            ),
                          ),
                          icon: const Icon(
                            Icons.search,
                            color: AppColors.blue,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: _openAllWeeks,
                        child: const Text('All weeks'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _WeekCards(
                  weekIds: weekIds,
                  weeks: weeks,
                  selected: shown,
                  upcoming: _windowOpen ? null : thisWeek,
                  onPick: _pickWeek,
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _WeekHeadline(
                        weekId: shown,
                        totals: totals,
                        total: total,
                        notOpenYet: notOpenYet,
                      ),
                      const SizedBox(height: 12),
                      _WindowLine(
                        weekId: shown,
                        isThisWeek: shown == thisWeek,
                        open: _windowOpen && shown == thisWeek,
                      ),
                      const SizedBox(height: 18),
                      _RingSummary(total: total, totals: totals),
                      const SizedBox(height: 16),
                      _RemindButton(
                        total: total,
                        pending: pending,
                        canNotify: canNotify,
                        windowOpen: _windowOpen && shown == _weekId,
                        notOpenYet: notOpenYet,
                        sending: _sending,
                        onRemind: _remind,
                      ),
                      const SizedBox(height: 22),
                      _WhatPeopleSaid(
                        comments: comments,
                        onOpen: (item) =>
                            _push(FeedbackDetailScreen(item: item)),
                        onSeeAll: () =>
                            _push(WeekCommentsScreen(weekId: shown)),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------
// Week cards + ring design: colours and helpers.
// ---------------------------------------------------------------------

/// The look of every card on this screen: white, a soft border and a
/// light shadow, so cards stand out on the white page.
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

/// A dark version of a rating colour, for text on its tint.
Color _moodInk(String rating) {
  switch (rating) {
    case PulseRating.great:
      return AppColors.blueDeep;
    case PulseRating.good:
      return const Color(0xFF2F57C8);
    case PulseRating.okay:
      return const Color(0xFF8A5A00);
    default:
      return const Color(0xFFA2321C);
  }
}

/// One colour per rating, used everywhere on this screen.
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

/// When a week's window opens: its open day at the open time.
DateTime _opensAt(String weekId) {
  final p = weekId.split('-').map(int.parse).toList();
  return DateTime(
    p[0],
    p[1],
    p[2],
    AppConfig.pulseOpenHour,
    AppConfig.pulseOpenMinute,
  );
}

/// One clear line about the window, for example:
///   ● Open now · since Mon 10:00 AM · closes Fri night
///   ● Opens Mon 10:00 AM · closes Fri night
///   ● Closed · was open Mon 10:00 AM – Fri night
class _WindowLine extends StatelessWidget {
  const _WindowLine({
    required this.weekId,
    required this.isThisWeek,
    required this.open,
  });

  final String weekId;
  final bool isThisWeek;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final openDay = PulseService.openDayLabel();
    final short = openDay.length > 3 ? openDay.substring(0, 3) : openDay;
    final openTime = PulseService.openTimeLabel();
    final closeDay = PulseService.closeDayLabel();
    final closeShort = closeDay.length > 3 ? closeDay.substring(0, 3) : closeDay;

    final Color dot;
    final String label;
    final String detail;
    if (AppConfig.pulseOpenEveryDay && isThisWeek) {
      dot = const Color(0xFF16A34A);
      label = 'Open';
      detail = 'test mode: open every day';
    } else if (open) {
      dot = const Color(0xFF16A34A);
      label = 'Open now';
      detail = 'since $short $openTime · closes $closeShort night';
    } else if (isThisWeek && DateTime.now().isBefore(_opensAt(weekId))) {
      dot = const Color(0xFFE9A83B);
      label = 'Not open yet';
      detail = 'opens $short $openTime · closes $closeShort night';
    } else {
      dot = const Color(0xFF8A94AA);
      label = 'Closed';
      detail = 'was open $short $openTime – $closeShort night';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: dot.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: Color.lerp(dot, Colors.black, 0.35),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '· $detail',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterNote extends StatelessWidget {
  const _CenterNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, fontSize: 15),
        ),
      ),
    );
  }
}

const List<String> _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// A work week in one short line: "5–9 Oct" or "28 Sep–2 Oct".
String _shortWeek(String weekId) {
  final p = weekId.split('-').map(int.parse).toList();
  final d = DateTime(p[0], p[1], p[2]);
  final monday = DateTime(d.year, d.month, d.day - (d.weekday - 1));
  final friday = DateTime(monday.year, monday.month, monday.day + 4);
  if (monday.month == friday.month) {
    return '${monday.day}–${friday.day} ${_monthNames[friday.month - 1]}';
  }
  return '${monday.day} ${_monthNames[monday.month - 1]}–'
      '${friday.day} ${_monthNames[friday.month - 1]}';
}

/// A row of week cards you can swipe sideways, newest on the right.
/// Each card shows the dates, a small colour bar and how many answered.
class _WeekCards extends StatelessWidget {
  const _WeekCards({
    required this.weekIds,
    required this.weeks,
    required this.selected,
    required this.upcoming,
    required this.onPick,
  });

  /// Newest first.
  final List<String> weekIds;
  final Map<String, PulseTotals> weeks;
  final String selected;
  final String? upcoming;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        // Reversed, so it opens at the newest week on the right.
        reverse: true,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: weekIds.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final id = weekIds[i];
          final t = weeks[id] ?? const PulseTotals();
          final isSelected = id == selected;
          final isUpcoming = id == upcoming;
          final name = PulseService.weekName(id);
          final String sub;
          if (isUpcoming) {
            sub = 'Opens ${PulseService.openDayLabel().substring(0, 3)}';
          } else if (isSelected && name.isNotEmpty) {
            sub = name;
          } else {
            sub = '${t.submitted} answered';
          }
          final parts = [
            for (final r in PulseRating.all)
              if (t.countFor(r) > 0) r,
          ];

          return Material(
            color: isSelected ? const Color(0xFFF2F6FF) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isSelected ? AppColors.blue : const Color(0xFFE3E8F2),
                width: 1.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onPick(id),
              child: Container(
                width: 116,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _shortWeek(id),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: SizedBox(
                        height: 5,
                        child: parts.isEmpty
                            ? const ColoredBox(
                          color: Color(0xFFE6EBF4),
                          child: SizedBox.expand(),
                        )
                            : Row(
                          children: [
                            for (var j = 0; j < parts.length; j++) ...[
                              if (j > 0) const SizedBox(width: 2),
                              Expanded(
                                flex: t.countFor(parts[j]),
                                child: ColoredBox(
                                  color: _moodColor(parts[j]),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Text(
                      sub,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A ring with "46/56 answered" in the middle, and the four ratings plus
/// "Waiting" listed beside it.
class _RingSummary extends StatelessWidget {
  const _RingSummary({required this.total, required this.totals});

  final int total;
  final PulseTotals totals;

  @override
  Widget build(BuildContext context) {
    final submitted = totals.submitted;
    final waiting = total > submitted ? total - submitted : 0;
    final whole = math.max(total, submitted);

    Widget row(Widget dot, String label, int count) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          dot,
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.muted, fontSize: 14),
            ),
          ),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );

    return Row(
      children: [
        SizedBox(
          width: 170,
          height: 170,
          child: CustomPaint(
            painter: _RingPainter(
              parts: [
                for (final r in PulseRating.all)
                  (totals.countFor(r), _moodColor(r)),
              ],
              whole: whole,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$submitted',
                          style: _h(32, weight: FontWeight.w800),
                        ),
                        TextSpan(
                          text: '/$total',
                          style: _h(
                            17,
                            color: const Color(0xFF8A94AA),
                            weight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Text(
                    'answered',
                    style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            children: [
              for (final r in PulseRating.all)
                row(
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _moodColor(r),
                      shape: BoxShape.circle,
                    ),
                  ),
                  PulseRating.label(r),
                  totals.countFor(r),
                ),
              row(
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFC9D0DC), width: 2),
                  ),
                ),
                'Waiting',
                waiting,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.parts, required this.whole});

  /// (count, colour) for each rating, in order.
  final List<(int, Color)> parts;

  /// Everyone: the ring is split by this number, so the grey part left
  /// over is the people still waiting.
  final int whole;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 18.0;
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
    const gap = 0.035;
    var start = -math.pi / 2;
    for (final (count, colour) in parts) {
      if (count == 0) continue;
      final sweep = math.pi * 2 * count / whole;
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
  bool shouldRepaint(_RingPainter old) =>
      old.whole != whole || old.parts.toString() != parts.toString();
}

/// One big button to remind the people still to answer, or a quiet line
/// when there is nothing to send.
class _RemindButton extends StatelessWidget {
  const _RemindButton({
    required this.total,
    required this.pending,
    required this.canNotify,
    required this.windowOpen,
    required this.notOpenYet,
    required this.sending,
    required this.onRemind,
  });

  /// How many employees can answer. 0 means none added yet.
  final int total;
  final int pending;
  final bool canNotify;
  final bool windowOpen;
  final bool notOpenYet;
  final bool sending;
  final VoidCallback onRemind;

  @override
  Widget build(BuildContext context) {
    final canRemind = canNotify && windowOpen && !notOpenYet && pending > 0;
    if (canRemind) {
      return FilledButton(
        onPressed: sending ? null : onRemind,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        child: Text(
          sending
              ? 'Sending…'
              : pending == 1
              ? 'Remind the 1 who has not answered'
              : 'Remind the $pending who have not answered',
        ),
      );
    }

    // Before it opens, the window line already says when. Show nothing.
    if (notOpenYet && total > 0) return const SizedBox.shrink();

    final String message;
    if (total == 0) {
      message = 'No employees added yet';
    } else if (pending == 0) {
      message = 'Everyone has answered';
    } else if (windowOpen) {
      message = '$pending have not answered';
    } else {
      message = '$pending did not answer. This week is closed.';
    }
    return Container(
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6FC),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// "What people said": the week's written comments as quote cards, the
/// ones that still need a reply first. "All N" opens every comment.
class _WhatPeopleSaid extends StatelessWidget {
  const _WhatPeopleSaid({
    required this.comments,
    required this.onOpen,
    required this.onSeeAll,
  });

  final List<FeedbackItem> comments;
  final void Function(FeedbackItem item) onOpen;
  final VoidCallback onSeeAll;

  static const int _preview = 3;

  @override
  Widget build(BuildContext context) {
    final fresh =
    comments.where((f) => f.status == FeedbackStatus.newItem).toList();
    final others =
    comments.where((f) => f.status != FeedbackStatus.newItem).toList();
    final shown = [...fresh, ...others].take(_preview).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'What people said',
                style: _h(19, weight: FontWeight.w800),
              ),
            ),
            if (comments.isNotEmpty)
              TextButton(
                onPressed: onSeeAll,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: Text('All ${comments.length}'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (comments.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: const Text(
              'No written comments for this week. People who choose Okay '
                  'or Difficult write a few words, and they show here.',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 14.5,
                height: 1.4,
              ),
            ),
          ),
        for (final item in shown) ...[
          _Quote(item: item, onTap: () => onOpen(item)),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// One comment as a card with a coloured line on the left (red for
/// Difficult, yellow for Okay). The rating on top, the words in quotes,
/// then who wrote it, the date, and whether it needs a reply.
class _Quote extends StatelessWidget {
  const _Quote({required this.item, required this.onTap});

  final FeedbackItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rating = item.rating ?? PulseRating.okay;
    final who = item.anonymous ? 'Anonymous' : (item.authorName ?? '');
    final date = _FeedbackCard._date(item.createdAt);
    final needsReply = item.status == FeedbackStatus.newItem;

    return DecoratedBox(
      decoration: _cardDecoration(),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The coloured line on the left.
                Container(width: 5, color: _moodColor(rating)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The rating, small and in its colour.
                        Row(
                          children: [
                            Icon(
                              PulseRating.icon(rating),
                              size: 16,
                              color: _moodColor(rating),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              PulseRating.label(rating),
                              style: TextStyle(
                                color: _moodInk(rating),
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // The words.
                        Text(
                          '“${item.text}”',
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.45,
                            color: AppColors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Who, when, and the status.
                        Row(
                          children: [
                            if (item.anonymous) ...[
                              const Icon(
                                Icons.lock_outline,
                                size: 14,
                                color: AppColors.muted,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                date.isEmpty ? who : '$who, $date',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              needsReply
                                  ? 'Needs reply'
                                  : FeedbackStatus.label(item.status),
                              style: TextStyle(
                                color: needsReply
                                    ? const Color(0xFFD9541E)
                                    : AppColors.muted,
                                fontSize: 13.5,
                                fontWeight: needsReply
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                              ),
                            ),
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

/// The top of the week: "Week of 5 Oct – 9 Oct" small, and one big line
/// that says how the week went, for example "A good week".
class _WeekHeadline extends StatelessWidget {
  const _WeekHeadline({
    required this.weekId,
    required this.totals,
    required this.total,
    required this.notOpenYet,
  });

  final String weekId;
  final PulseTotals totals;
  final int total;
  final bool notOpenYet;

  @override
  Widget build(BuildContext context) {

    final submitted = totals.submitted;
// Show the summary after 25% of employees answer (at least 3).
    final needed = (total * 0.25).ceil() < 3 ? 3 : (total * 0.25).ceil();
    final String title;
    final String line;
    if (total == 0) {
      title = 'No employees yet';
      line = 'Add employee accounts to start the Weekly Pulse.';
    } else if (notOpenYet) {
      // The window line below already says when it opens and closes.
      title = 'Starting soon';
      line = '';
    } else if (submitted == 0) {
      title = 'No answers yet';
      line = 'Answers show here as soon as people send them.';
    } else if (submitted < needed) {
      title = 'Waiting for more answers';
      line = '$submitted of $total answered. '
          'The summary shows after $needed answers.';
    } else {
      final good = totals.countFor(PulseRating.great) +
          totals.countFor(PulseRating.good);
      final attention = totals.countFor(PulseRating.okay) +
          totals.countFor(PulseRating.difficult);
      final share = good / submitted;

      final great = totals.countFor(PulseRating.great);
      final goodOnly = totals.countFor(PulseRating.good);
      final okay = totals.countFor(PulseRating.okay);
      final difficult = totals.countFor(PulseRating.difficult);

      if (share >= 0.75) {
        // Most feel good: say Great if Great is the bigger group.
        title = great > goodOnly ? 'A great week' : 'A good week';
      } else if (share >= 0.5) {
        title = 'Mostly good';
      } else if (share >= 0.25) {
        title = 'A mixed week';
      } else {
        // Most need attention: say Okay if Okay is the bigger group.
        title = okay > difficult ? 'An okay week' : 'A hard week';
      }

      line = attention == 0
          ? 'Everyone feels good this week.'
          : '$good of $submitted feel good · $attention need attention.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Week of ${PulseService.weekLabel(weekId)}',
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(title, style: _h(32, weight: FontWeight.w800, height: 1.15)),
        if (line.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            line,
            style: const TextStyle(color: AppColors.muted, fontSize: 14.5),
          ),
        ],
      ],
    );
  }
}

/// Weekly Pulse comments, one screen for everything:
/// - the week bar on top: ‹ 5 Oct – 9 Oct ›. Tap it to pick any week,
///   or "All weeks" to see and search every comment.
/// - a search box: words, name or employee ID.
/// - one row of chips: All, Needs reply, Difficult, Okay.
class WeekCommentsScreen extends StatefulWidget {
  const WeekCommentsScreen({
    super.key,
    required this.weekId,
    this.focusSearch = false,
  });

  /// The week to open on. Null opens "All weeks".
  final String? weekId;

  /// Opens with the keyboard on the search box.
  final bool focusSearch;

  @override
  State<WeekCommentsScreen> createState() => _WeekCommentsScreenState();
}

/// The chips. Needs reply is a status, the rest are ratings.
/// Great and Good have no written comment, so they have no chip.
enum _CommentChip { all, needsReply, difficult, okay }

class _WeekCommentsScreenState extends State<WeekCommentsScreen> {
  late final Stream<List<FeedbackItem>> _stream;
  final TextEditingController _search = TextEditingController();

  /// The week shown. Null is All weeks.
  String? _weekId;
  _CommentChip _chip = _CommentChip.all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _weekId = widget.weekId;
    _stream = FeedbackService.instance
        .watchAll()
        .map((all) => all.where((f) => !f.isFromBox).toList());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static String _chipLabel(_CommentChip c) {
    switch (c) {
      case _CommentChip.all:
        return 'All';
      case _CommentChip.needsReply:
        return 'Needs reply';
      case _CommentChip.difficult:
        return PulseRating.label(PulseRating.difficult);
      case _CommentChip.okay:
        return PulseRating.label(PulseRating.okay);
    }
  }

  static Color? _chipDot(_CommentChip c) {
    switch (c) {
      case _CommentChip.all:
        return null;
      case _CommentChip.needsReply:
        return const Color(0xFFE2583E);
      case _CommentChip.difficult:
        return _moodColor(PulseRating.difficult);
      case _CommentChip.okay:
        return _moodColor(PulseRating.okay);
    }
  }

  static bool _chipMatches(FeedbackItem f, _CommentChip c) {
    switch (c) {
      case _CommentChip.all:
        return true;
      case _CommentChip.needsReply:
        return f.status == FeedbackStatus.newItem;
      case _CommentChip.difficult:
        return f.rating == PulseRating.difficult;
      case _CommentChip.okay:
        return f.rating == PulseRating.okay;
    }
  }

  /// Words, name or employee ID. Anonymous ones only by their words.
  bool _matchesQuery(FeedbackItem f) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (f.text.toLowerCase().contains(q)) return true;
    if (f.anonymous) return false;
    return (f.authorName ?? '').toLowerCase().contains(q) ||
        (f.authorEmployeeId ?? '').toLowerCase().contains(q);
  }

  /// "Pick a week": All weeks, then every week from this week back to
  /// the first week with comments.
  Future<void> _pickWeek(List<FeedbackItem> all, List<String> weeks) async {
    Widget row({
      required String title,
      required String subtitle,
      required int count,
      required bool selected,
      required VoidCallback onTap,
    }) =>
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$count',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? AppColors.blue : const Color(0xFFC9D0DC),
              ),
            ],
          ),
          onTap: onTap,
        );

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => _withInter(sheetContext, SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            children: [
              Text('Pick a week', style: _h(19, weight: FontWeight.w800)),
              const SizedBox(height: 4),
              row(
                title: 'All weeks',
                subtitle: 'Every comment, newest first',
                count: all.length,
                selected: _weekId == null,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  setState(() => _weekId = null);
                },
              ),
              for (final id in weeks)
                row(
                  title: PulseService.weekLabel(id),
                  subtitle: PulseService.weekName(id).isNotEmpty
                      ? PulseService.weekName(id)
                      : _monthOfWeek(id),
                  count: all.where((f) => f.weekId == id).length,
                  selected: _weekId == id,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    setState(() => _weekId = id);
                  },
                ),
            ],
          ),
        ),
      )),
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
        title: Text('Comments', style: _h(22)),
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
                  return const _CenterNote(
                    'Could not load the comments. Please go back and try '
                        'again.',
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snap.data!;
                final thisWeek = PulseService.thisWeekId();

                // Weeks from this week back to the first week with
                // comments (or the week that was opened).
                var first = _weekId ?? thisWeek;
                for (final f in all) {
                  final w = f.weekId;
                  if (w != null && w.compareTo(first) < 0) first = w;
                }
                final weeks = <String>[];
                for (var id = thisWeek;
                id.compareTo(first) >= 0 && weeks.length < 104;
                id = PulseService.shiftWeek(id, -1)) {
                  weeks.add(id);
                }

                final inWeek = _weekId == null
                    ? all
                    : all.where((f) => f.weekId == _weekId).toList();
                final searched = inWeek.where(_matchesQuery).toList();
                final items =
                searched.where((f) => _chipMatches(f, _chip)).toList();

                final canBack =
                    _weekId != null && _weekId!.compareTo(first) > 0;
                final canNext =
                    _weekId != null && _weekId!.compareTo(thisWeek) < 0;

                // Week headers, only in All weeks.
                final list = <Widget>[];
                String? lastWeek;
                for (final item in items) {
                  if (_weekId == null && item.weekId != lastWeek) {
                    lastWeek = item.weekId;
                    final id = item.weekId;
                    list.add(
                      _GroupHeader(
                        label: id == null
                            ? 'Other'
                            : PulseService.weekLabel(id),
                        count: items.where((f) => f.weekId == id).length,
                      ),
                    );
                  }
                  list.add(
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: _Quote(
                        item: item,
                        onTap: () {
                          FocusScope.of(context).unfocus();
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => FeedbackDetailScreen(item: item),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                }

                final q = _query.trim();
                return ListView(
                  keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
                  children: [
                    // The week bar.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        height: 64,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F6FF),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            _WeekArrow(
                              icon: Icons.chevron_left,
                              tooltip: 'Week before',
                              visible: _weekId != null,
                              onTap: canBack
                                  ? () => setState(
                                    () => _weekId =
                                    PulseService.shiftWeek(_weekId!, -1),
                              )
                                  : null,
                            ),
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _pickWeek(all, weeks),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _weekId == null
                                          ? 'All weeks'
                                          : PulseService.weekLabel(_weekId!),
                                      style: _h(
                                        17,
                                        weight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          [
                                            if (_weekId != null &&
                                                PulseService.weekName(
                                                  _weekId!,
                                                ).isNotEmpty)
                                              PulseService.weekName(_weekId!),
                                            '${inWeek.length} '
                                                '${inWeek.length == 1 ? 'comment' : 'comments'}',
                                          ].join(' · '),
                                          style: const TextStyle(
                                            color: AppColors.blue,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const Icon(
                                          Icons.arrow_drop_down,
                                          color: AppColors.blue,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            _WeekArrow(
                              icon: Icons.chevron_right,
                              tooltip: 'Week after',
                              visible: _weekId != null,
                              onTap: canNext
                                  ? () => setState(
                                    () => _weekId =
                                    PulseService.shiftWeek(_weekId!, 1),
                              )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Search box.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        controller: _search,
                        autofocus: widget.focusSearch,
                        onChanged: (v) => setState(() => _query = v),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search words, name or ID',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF5F7FB),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                            borderSide: const BorderSide(
                              color: AppColors.blue,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // One row of chips.
                    SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: _CommentChip.values.length,
                        separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final c = _CommentChip.values[i];
                          return _StatusChip(
                            label: _chipLabel(c),
                            dot: _chipDot(c),
                            count: searched
                                .where((f) => _chipMatches(f, c))
                                .length,
                            selected: c == _chip,
                            onTap: () => setState(() => _chip = c),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                      child: Text(
                        '${items.length} '
                            '${items.length == 1 ? 'comment' : 'comments'}'
                            '${q.isEmpty ? ' · newest first' : ' for “$q”'}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: _cardDecoration(),
                          child: Text(
                            inWeek.isEmpty
                                ? 'No written comments for this week.'
                                : 'Nothing matches. Try another word or '
                                'chip.',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 15,
                            ),
                          ),
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
    ));
  }
}

/// A round white arrow in the week bar. Grey when it cannot move.
class _WeekArrow extends StatelessWidget {
  const _WeekArrow({
    required this.icon,
    required this.tooltip,
    required this.visible,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool visible;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox(width: 46);
    final on = onTap != null;
    return Material(
      color: on ? Colors.white : Colors.transparent,
      shape: const CircleBorder(),
      elevation: on ? 1 : 0,
      shadowColor: const Color(0x330E1A3A),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(
          icon,
          size: 26,
          color: on ? AppColors.blue : const Color(0xFFC9D0DC),
        ),
      ),
    );
  }
}

/// "September": the month a week's Friday is in.
String _monthOfWeek(String weekId) {
  final p = weekId.split('-').map(int.parse).toList();
  final d = DateTime(p[0], p[1], p[2]);
  final friday = DateTime(d.year, d.month, d.day - (d.weekday - 1) + 4);
  return _longMonths[friday.month - 1];
}

/// The round blue button with the person's initial. Opens a small menu.
class _AccountButton extends StatelessWidget {
  const _AccountButton({
    required this.name,
    required this.actions,
    this.onBlue = false,
  });

  final String name;
  final List<MenuAction> actions;

  /// On a blue background the button turns white with a blue letter.
  final bool onBlue;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return PopupMenuButton<int>(
      tooltip: 'Your account',
      position: PopupMenuPosition.under,
      onSelected: (i) => actions[i].onTap(),
      itemBuilder: (context) => [
        for (var i = 0; i < actions.length; i++)
          PopupMenuItem<int>(value: i, child: Text(actions[i].label)),
      ],
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onBlue ? Colors.white : AppColors.blue,
          shape: BoxShape.circle,
        ),
        child: Text(
          initial,
          style: _h(16, color: onBlue ? AppColors.blue : Colors.white),
        ),
      ),
    );
  }
}

/// Tab 2. Suggestions, with a chip for every status and a date filter.
/// Grouped by date: Today, Yesterday, Earlier this week, Last week, and
/// then by month. Tap a card to open it, reply and change the status.
class _SuggestionTab extends StatefulWidget {
  const _SuggestionTab({
    required this.suggestions,
    required this.loading,
    required this.onOpen,
    required this.onSearch,
  });

  final List<FeedbackItem> suggestions;
  final bool loading;
  final void Function(FeedbackItem item) onOpen;
  final VoidCallback onSearch;

  @override
  State<_SuggestionTab> createState() => _SuggestionTabState();
}

/// The choices in the date sheet.
enum _Range { days30, months3, thisYear, all, month }

class _SuggestionTabState extends State<_SuggestionTab> {
  /// The chosen chip: null is All, otherwise one status.
  String? _status;

  _Range _range = _Range.days30;

  /// The month chosen with "Pick a month…" (first day of that month).
  DateTime? _month;

  /// How many extra months "Show older" has added.
  int _older = 0;

  static DateTime _dateOf(FeedbackItem f) => f.createdAt ?? DateTime.now();

  /// The first day shown, or null for no limit.
  DateTime? _from(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (_range) {
      case _Range.days30:
        return DateTime(today.year, today.month - _older, today.day - 30);
      case _Range.months3:
        return DateTime(today.year, today.month - 3 - _older, today.day);
      case _Range.thisYear:
        return DateTime(now.year, 1, 1);
      case _Range.all:
        return null;
      case _Range.month:
        return _month;
    }
  }

  /// The day after the last day shown, or null for up to today.
  DateTime? _until() => _range == _Range.month && _month != null
      ? DateTime(_month!.year, _month!.month + 1, 1)
      : null;

  String _rangeLabel() {
    // After "Show older": "Since 8 Aug".
    if (_older > 0 &&
        (_range == _Range.days30 || _range == _Range.months3)) {
      final from = _from(DateTime.now())!;
      return 'Since ${from.day} ${_monthNames[from.month - 1]}';
    }
    switch (_range) {
      case _Range.days30:
        return 'Last 30 days';
      case _Range.months3:
        return 'Last 3 months';
      case _Range.thisYear:
        return 'This year';
      case _Range.all:
        return 'All time';
      case _Range.month:
        return '${_longMonths[_month!.month - 1]} ${_month!.year}';
    }
  }

  bool _inRange(FeedbackItem f, DateTime now) {
    final d = _dateOf(f);
    final from = _from(now);
    final until = _until();
    if (from != null && d.isBefore(from)) return false;
    if (until != null && !d.isBefore(until)) return false;
    return true;
  }

  void _setRange(_Range r, {DateTime? month}) {
    setState(() {
      _range = r;
      _month = month;
      _older = 0;
    });
  }

  /// The sheet that opens from the "Last 30 days" button.
  Future<void> _openRangeSheet() async {
    Widget option(String label, _Range r) => ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      trailing: Icon(
        _range == r
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
        color: _range == r ? AppColors.blue : const Color(0xFFC9D0DC),
      ),
      onTap: () {
        Navigator.of(context).pop();
        _setRange(r);
      },
    );

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => _withInter(sheetContext, SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Show suggestions from',
                style: _h(19, weight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              option('Last 30 days', _Range.days30),
              option('Last 3 months', _Range.months3),
              option('This year', _Range.thisYear),
              option('All time', _Range.all),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.calendar_month_outlined,
                  color: AppColors.blue,
                ),
                title: Text(
                  _range == _Range.month ? _rangeLabel() : 'Pick a month…',
                  style: const TextStyle(
                    color: AppColors.blue,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: AppColors.blue,
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openMonthSheet();
                },
              ),
            ],
          ),
        ),
      )),
    );
  }

  /// A list of the months that have suggestions, newest first.
  Future<void> _openMonthSheet() async {
    final months = <DateTime>{
      for (final f in widget.suggestions)
        DateTime(_dateOf(f).year, _dateOf(f).month, 1),
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
      builder: (sheetContext) => _withInter(sheetContext, SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.6,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            children: [
              Text('Pick a month', style: _h(19, weight: FontWeight.w800)),
              const SizedBox(height: 6),
              if (months.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No suggestions yet.',
                    style: TextStyle(color: AppColors.muted, fontSize: 15),
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
                  trailing: Text(
                    '${widget.suggestions.where((f) => _dateOf(f).year == m.year && _dateOf(f).month == m.month).length}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _setRange(_Range.month, month: m);
                  },
                ),
            ],
          ),
        ),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final inRange =
    widget.suggestions.where((f) => _inRange(f, now)).toList();

    // New counts every waiting suggestion, even old ones, so nothing is
    // forgotten. The other chips count the chosen dates only.
    int countOf(String? s) {
      if (s == FeedbackStatus.newItem) {
        return widget.suggestions
            .where((f) => f.status == FeedbackStatus.newItem)
            .length;
      }
      return s == null
          ? inRange.length
          : inRange.where((f) => f.status == s).length;
    }

    final List<FeedbackItem> items;
    if (_status == FeedbackStatus.newItem) {
      items = widget.suggestions
          .where((f) => f.status == FeedbackStatus.newItem)
          .toList();
    } else if (_status == null) {
      items = inRange;
    } else {
      items = inRange.where((f) => f.status == _status).toList();
    }
    final filters = <String?>[null, ...FeedbackStatus.all];

    // "Show older": only for the moving ranges, and only when there are
    // older suggestions to show.
    final from = _from(now);
    final canShowOlder =
        (_range == _Range.days30 || _range == _Range.months3) &&
            _status != FeedbackStatus.newItem &&
            from != null &&
            widget.suggestions.any((f) => _dateOf(f).isBefore(from));
    final olderMonth = from == null
        ? ''
        : _longMonths[DateTime(from.year, from.month - 1, 1).month - 1];

    // Count per date group, for the headers.
    final groupCounts = <String, int>{};
    for (final f in items) {
      final g = _groupLabel(_dateOf(f), now);
      groupCounts[g] = (groupCounts[g] ?? 0) + 1;
    }

    final list = <Widget>[];
    String? lastGroup;
    for (final item in items) {
      final g = _groupLabel(_dateOf(item), now);
      if (g != lastGroup) {
        list.add(_GroupHeader(label: g, count: groupCounts[g]!));
        lastGroup = g;
      }
      list.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: _FeedbackCard(item: item, onTap: () => widget.onOpen(item)),
        ),
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Suggestion Box',
                  style: _h(24, weight: FontWeight.w800),
                ),
              ),
              Material(
                color: const Color(0xFFF2F6FF),
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Search',
                  onPressed: widget.onSearch,
                  icon: const Icon(Icons.search, color: AppColors.blue),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Chips: swipe sideways to see them all.
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: filters.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final s = filters[i];
              return _StatusChip(
                label: s == null ? 'All' : FeedbackStatus.label(s),
                dot: s == null ? null : _statusDot(s),
                count: countOf(s),
                selected: s == _status,
                onTap: () => setState(() => _status = s),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        // Date button and how many show.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              if (_status == FeedbackStatus.newItem)
                const Expanded(
                  child: Text(
                    'Every suggestion still waiting for a reply, any date.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13.5),
                  ),
                )
              else ...[
                Material(
                  color: const Color(0xFFF2F6FF),
                  shape: const StadiumBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _openRangeSheet,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.calendar_month_outlined,
                            size: 18,
                            color: AppColors.blue,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _rangeLabel(),
                            style: const TextStyle(
                              color: AppColors.blue,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Icon(
                            Icons.arrow_drop_down,
                            color: AppColors.blue,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${items.length} '
                        '${items.length == 1 ? 'suggestion' : 'suggestions'}'
                        ' · newest first',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        if (widget.loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: _cardDecoration(),
              child: Text(
                _status == null
                    ? 'No suggestions in these dates.'
                    : 'No ${FeedbackStatus.label(_status!)} suggestions '
                    'in these dates.',
                style: const TextStyle(color: AppColors.muted, fontSize: 15),
              ),
            ),
          ),
        ...list,
        if (canShowOlder)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: OutlinedButton(
              onPressed: () => setState(() => _older++),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: const StadiumBorder(),
                side: const BorderSide(color: Color(0xFFD5DCE8), width: 1.5),
                textStyle: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: Text('Show older ($olderMonth)'),
            ),
          ),
      ],
    );
  }
}

/// "TODAY  2 ————" above a group of cards.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label, required this.count});

  final String label;
  final int count;

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
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF1F6),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
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

const List<String> _longMonths = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Which date group a suggestion goes in.
String _groupLabel(DateTime d, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final thisWeek = DateTime(today.year, today.month, today.day - (today.weekday - 1));
  final lastWeek = DateTime(thisWeek.year, thisWeek.month, thisWeek.day - 7);
  if (day == today) return 'Today';
  if (day == DateTime(today.year, today.month, today.day - 1)) {
    return 'Yesterday';
  }
  if (!day.isBefore(thisWeek)) return 'Earlier this week';
  if (!day.isBefore(lastWeek)) return 'Last week';
  if (d.year == now.year && d.month == now.month) {
    return 'Earlier in ${_longMonths[d.month - 1]}';
  }
  return '${_longMonths[d.month - 1]} ${d.year}';
}

/// For a card: "3:40 PM" for today, "7 Oct" this year, "7 Oct 2025" before.
String _cardWhen(DateTime? d) {
  if (d == null) return 'Just now';
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
  }
  final short = '${d.day} ${_monthNames[d.month - 1]}';
  return d.year == now.year ? short : '$short ${d.year}';
}

/// A round chip: an optional colour dot, the name and the number.
/// The chosen one is blue.
class _StatusChip extends StatelessWidget {
  const _StatusChip({
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
          padding: const EdgeInsets.symmetric(horizontal: 14),
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
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 7),
              Container(
                constraints: const BoxConstraints(minWidth: 22),
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.22)
                      : const Color(0xFFEEF1F6),
                  borderRadius: BorderRadius.circular(11),
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

/// Colours for each status: the dot, the light tag background and the
/// dark tag text.
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

Color _statusTint(String status) {
  switch (status) {
    case FeedbackStatus.newItem:
      return const Color(0xFFFDF3DF);
    case FeedbackStatus.underReview:
      return const Color(0xFFF1EBFE);
    case FeedbackStatus.planned:
      return const Color(0xFFE0F5F4);
    case FeedbackStatus.inProgress:
      return const Color(0xFFE6EDFF);
    default:
      return const Color(0xFFE3F6EA);
  }
}

Color _statusInk(String status) {
  switch (status) {
    case FeedbackStatus.newItem:
      return const Color(0xFF8A5A00);
    case FeedbackStatus.underReview:
      return const Color(0xFF5B34C7);
    case FeedbackStatus.planned:
      return const Color(0xFF0B6B6A);
    case FeedbackStatus.inProgress:
      return AppColors.blueDeep;
    default:
      return const Color(0xFF166534);
  }
}

/// One card you can tap: the status tag and date on top, the text, who
/// wrote it, and a round arrow on the right that shows it opens.
class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.item, required this.onTap});

  final FeedbackItem item;
  final VoidCallback onTap;

  static String _date(DateTime? d) {
    if (d == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final status = item.status;
    final isNew = status == FeedbackStatus.newItem;
    final rating = item.rating;
    // Weekly Pulse comments also show the rating next to the date.
    final when = [
      if (!item.isFromBox && rating != null) PulseRating.label(rating),
      _cardWhen(item.createdAt),
    ].where((t) => t.isNotEmpty).join(' · ');
    // A New suggestion waiting 7 days or more gets a red tag.
    final waitingDays = item.createdAt == null
        ? 0
        : DateTime.now().difference(item.createdAt!).inDays;
    final late = isNew && waitingDays >= 7;
    final name = item.authorName ?? '';
    final id = item.authorEmployeeId ?? '';
    final who = item.anonymous
        ? 'Anonymous'
        : (id.isEmpty ? name : '$name ($id)');
    final initial =
    name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    return DecoratedBox(
      decoration: _cardDecoration(),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Status tag and date.
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
                            decoration: BoxDecoration(
                              color: _statusTint(status),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: _statusDot(status),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isNew && !late
                                      ? 'New · Needs reply'
                                      : FeedbackStatus.label(status),
                                  style: TextStyle(
                                    color: _statusInk(status),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (late) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFCE8E4),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$waitingDays days waiting',
                                style: const TextStyle(
                                  color: Color(0xFFA2321C),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                          const Spacer(),
                          const SizedBox(width: 8),
                          Text(
                            when,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      // The text.
                      Text(
                        item.text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15.5,
                          height: 1.4,
                          color: AppColors.ink,
                          fontWeight: isNew ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Who wrote it.
                      Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: item.anonymous
                                  ? const Color(0xFFEEF1F6)
                                  : AppColors.blueTint,
                              shape: BoxShape.circle,
                            ),
                            child: item.anonymous
                                ? const Icon(
                              Icons.lock_outline,
                              size: 13,
                              color: AppColors.muted,
                            )
                                : Text(
                              initial,
                              style: const TextStyle(
                                color: AppColors.blueDeep,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              who,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // The arrow: shows the card opens.
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF2F6FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.chevron_right,
                    color: AppColors.blue,
                    size: 22,
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