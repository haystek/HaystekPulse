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
import '../widgets/pulse_line.dart';
import '../widgets/ui.dart' hide PulseLine;
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
  late Stream<Map<String, PulseTotals>> _weeks;

  /// Counts automatic retries after a loading error.
  int _retries = 0;
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
    _weeks = _watchWeeks();
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

  /// Opens one suggestion or comment. Afterwards the screen is drawn again,
  /// so a changed status shows at once (also for sample items).
  Future<void> _openItem(FeedbackItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => FeedbackDetailScreen(item: item)),
    );
    if (mounted) setState(() {});
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
                                onOpen: _openItem,
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
            bottomNavigationBar: _BottomTabs(
              index: _tab,
              newCount: newCount,
              onTap: (i) => setState(() => _tab = i),
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
    final beforeOpen = PulseService.notOpenYet();
    final notOpenYet = !_windowOpen && shown == thisWeek && beforeOpen;
    // This week's window has closed (or it is a past week).
    final closed = !(shown == thisWeek && (_windowOpen || beforeOpen));
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
              // Tries again by itself every 3 seconds until it loads.
              return _AutoRetry(key: ValueKey(_retries), onRetry: _retry);
            }
            if (!totalSnap.hasData || !weekSnap.hasData) {
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
                            const WeekCommentsScreen(weekId: null),
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
                  upcoming: beforeOpen ? thisWeek : null,
                  closedThisWeek:
                  PulseService.closedForThisWeek() ? thisWeek : null,
                  onPick: _pickWeek,
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _WeekHero(
                        weekId: shown,
                        totals: totals,
                        total: total,
                        isThisWeek: shown == thisWeek,
                        open: _windowOpen && shown == thisWeek,
                        notOpenYet: notOpenYet,
                        closed: closed,
                        lastWeek: weeks[PulseService.shiftWeek(shown, -1)],
                      ),
                      const SizedBox(height: 14),
                      // Before it opens: no numbers yet, just who can answer.
                      if (notOpenYet)
                        _SoonNote(total: total)
                      else
                      // The numbers and the reminder, in one white card.
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: const Color(0xFFEDF0F6),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _RingSummary(total: total, totals: totals),
                              ...[
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  child: Divider(
                                    height: 1,
                                    color: Color(0xFFEDF0F6),
                                  ),
                                ),
                                _RemindButton(
                                  weekId: shown,
                                  total: total,
                                  pending: pending,
                                  canNotify: canNotify,
                                  windowOpen: _windowOpen && shown == _weekId,
                                  sending: _sending,
                                  onRemind: _remind,
                                ),
                              ],
                            ],
                          ),
                        ),
                      const SizedBox(height: 22),
                      _WhatPeopleSaid(
                        comments: comments,
                        onOpen: _openItem,
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

  /// The totals of every week, live.
  ///
  /// The first time, it waits for fresh numbers from the server instead of
  /// showing the older copy saved on the phone, so the card does not jump
  /// from an old result to the real one. Offline: after 4 seconds it shows
  /// the saved copy anyway. After that, every change shows at once.
  Stream<Map<String, PulseTotals>> _watchWeeks() {
    late final StreamController<Map<String, PulseTotals>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? sub;
    Timer? fallback;
    QuerySnapshot<Map<String, dynamic>>? saved;
    var live = false;

    Map<String, PulseTotals> toMap(QuerySnapshot<Map<String, dynamic>> snap) => {
      for (final doc in snap.docs) doc.id: PulseTotals.fromMap(doc.data()),
    };

    controller = StreamController<Map<String, PulseTotals>>(
      onListen: () {
        // Offline: show the saved copy after 4 seconds.
        fallback = Timer(const Duration(seconds: 4), () {
          final s = saved;
          if (!live && s != null && !controller.isClosed) {
            live = true;
            controller.add(toMap(s));
          }
        });
        sub = FirebaseFirestore.instance
            .collection('pulse_weeks')
            .snapshots(includeMetadataChanges: true)
            .listen(
              (snap) {
            // First time: skip the saved copy, wait for the server.
            if (!live && snap.metadata.isFromCache) {
              saved = snap;
              return;
            }
            live = true;
            fallback?.cancel();
            if (!controller.isClosed) controller.add(toMap(snap));
          },
          onError: (Object e) {
            if (!controller.isClosed) controller.addError(e);
          },
        );
      },
      onCancel: () async {
        fallback?.cancel();
        await sub?.cancel();
      },
    );
    return controller.stream;
  }

  /// Loading failed: try again by itself.
  void _retry() {
    if (!mounted) return;
    setState(() {
      _retries++;
      _weeks = _watchWeeks();
      _load();
    });
  }
}

/// Shown while the screen could not load: a spinner and
/// "Reconnecting…". Tries again by itself after 3 seconds.
class _AutoRetry extends StatefulWidget {
  const _AutoRetry({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  State<_AutoRetry> createState() => _AutoRetryState();
}

class _AutoRetryState extends State<_AutoRetry> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 3), widget.onRetry);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(height: 12),
          Text(
            'Reconnecting…',
            style: TextStyle(color: AppColors.muted, fontSize: 14.5),
          ),
        ],
      ),
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

/// The headline for a week: one big line that says how it went, and a
/// small line under it. The summary waits for 25% of answers (at least 3).
(String, String) _headline({
  required PulseTotals totals,
  required int total,
  required bool notOpenYet,
  required bool closed,
}) {
  final submitted = totals.submitted;
  // 25% of people, at least 3, but never more than everyone.
  // Example: 1 person → 1, 5 people → 3, 30 people → 8.
  var needed = (total * 0.25).ceil();
  if (needed < 3) needed = 3;
  if (needed > total) needed = total;
  if (total == 0) {
    return ('No employees yet', 'Add employee accounts to start.');
  }
  if (notOpenYet) {
    return (
    'Starting soon',
    'Opens ${PulseService.dateTimeLabel(PulseService.opensAt())}',
    );
  }
  if (submitted == 0) {
    return closed
        ? ('No answers', 'Nobody answered this week.')
        : ('No answers yet', 'Answers show here as soon as people send them.');
  }
  if (submitted < needed) {
    return (
    'Waiting for more answers',
    '$submitted of $total answered. The summary shows after $needed.',
    );
  }
  final share = _goodShare(totals);
  final String title;
  if (share >= 0.75) {
    title = totals.countFor(PulseRating.great) >
        totals.countFor(PulseRating.good)
        ? 'A great week'
        : 'A good week';
  } else if (share > 0.5) {
    title = 'Mostly good';
  } else if (share >= 0.25) {
    title = 'A mixed week';
  } else {
    title = totals.countFor(PulseRating.okay) >
        totals.countFor(PulseRating.difficult)
        ? 'An okay week'
        : 'A hard week';
  }
  // No small line here: the card shows "Better than last week" instead,
  // and the ring below shows the numbers.
  return (title, '');
}

/// Great + Good, out of everyone who answered: 0.0 to 1.0.
double _goodShare(PulseTotals t) {
  if (t.submitted == 0) return 0;
  return (t.countFor(PulseRating.great) + t.countFor(PulseRating.good)) /
      t.submitted;
}

/// The dark "night sky" card at the top of the week. Same style as the
/// employee home. It has 3 looks:
///
/// 1. Starting soon (like the employee "about to open" card):
///    big live timer, and a moving heartbeat line from Monday to the heart.
///    The moving part runs up to "now" again and again.
/// 2. Open now: the headline ("Mostly good"), and the heartbeat line
///    follows the answers: 18 of 30 answered = the line is 60% bright.
///    The moving part runs up to there. When everyone has answered, the
///    line reaches the heart and the heart turns pink.
/// 3. Closed: the same line, faint, with how many answered.
class _WeekHero extends StatefulWidget {
  const _WeekHero({
    required this.weekId,
    required this.totals,
    required this.total,
    required this.isThisWeek,
    required this.open,
    required this.notOpenYet,
    required this.closed,
    this.lastWeek,
  });

  final String weekId;
  final PulseTotals totals;

  /// The week before, to say "Better than last week". Null if none.
  final PulseTotals? lastWeek;
  final int total;
  final bool isThisWeek;
  final bool open;
  final bool notOpenYet;
  final bool closed;

  @override
  State<_WeekHero> createState() => _WeekHeroState();
}

class _WeekHeroState extends State<_WeekHero> {
  static const Color _soft = Color(0xFF9FB4F0);
  static const Color _light = Color(0xFFC9D6FF);
  static const Color _glow = Color(0xFF7FA2FF);
  static const Color _pink = Color(0xFFFF6B8A);

  // Ticks every second, only while the big "opens in" timer is shown.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _startOrStop();
  }

  @override
  void didUpdateWidget(_WeekHero old) {
    super.didUpdateWidget(old);
    _startOrStop();
  }

  void _startOrStop() {
    if (widget.notOpenYet) {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Monday 00:00 of the week that opens next.
  DateTime get _weekStart {
    final o = PulseService.opensAt();
    return DateTime(o.year, o.month, o.day - (o.weekday - DateTime.monday));
  }

  /// How far we are from Monday to the opening: 0.0 to 1.0.
  double _weekProgress() {
    final all = PulseService.opensAt().difference(_weekStart).inSeconds;
    if (all <= 0) return 1;
    final gone = DateTime.now().difference(_weekStart).inSeconds;
    return (gone / all).clamp(0.0, 1.0);
  }

  /// How many answered: 0.0 to 1.0.
  double get _answered {
    if (widget.total <= 0) return 0;
    return (widget.totals.submitted / widget.total).clamp(0.0, 1.0);
  }

  static TextStyle _t(
      double size, {
        FontWeight weight = FontWeight.w400,
        Color color = Colors.white,
        double? letterSpacing,
        double? height,
      }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  /// A small label with a value under it, like "Answered / 18 of 30".
  Widget _when(String label, String value, {bool right = false}) => Column(
    crossAxisAlignment:
    right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    children: [
      Text(label, style: _t(13, color: _soft)),
      const SizedBox(height: 2),
      Text(value, style: _t(13, weight: FontWeight.w600)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (widget.notOpenYet) {
      body = _soon();
    } else if (widget.open) {
      body = _openNow();
    } else {
      body = _closed();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B1B4D), Color(0xFF14328F), AppColors.blue],
          stops: [0, 0.55, 1],
        ),
      ),
      child: body,
    );
  }

  /// The small tag under the title, compared with the week before:
  ///   ↑ Better than last week   (green)
  ///   ↓ Harder than last week   (red)
  ///   = About the same as last week
  /// Only when the week before has answers. A change of more than 10%
  /// of people feeling good counts as better or harder.
  Widget? _trend() {
    final before = widget.lastWeek;
    if (before == null || before.submitted == 0) return null;
    if (widget.totals.submitted == 0) return null;
    final diff = _goodShare(widget.totals) - _goodShare(before);
    final than = widget.isThisWeek ? 'last week' : 'the week before';
    final IconData icon;
    final String text;
    final Color bg;
    final Color fg;
    if (diff > 0.10) {
      icon = Icons.arrow_upward_rounded;
      text = 'Better than $than';
      bg = const Color(0x294ADE80);
      fg = const Color(0xFF86EFAC);
    } else if (diff < -0.10) {
      icon = Icons.arrow_downward_rounded;
      text = 'Harder than $than';
      bg = const Color(0x2EF87171);
      fg = const Color(0xFFFCA5A5);
    } else {
      icon = Icons.drag_handle_rounded;
      text = 'About the same as $than';
      bg = Colors.white.withValues(alpha: 0.12);
      fg = _light;
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(9, 5, 11, 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 5),
            Text(text, style: _t(13, weight: FontWeight.w500, color: fg)),
          ],
        ),
      ),
    );
  }

  /// The small line under the title, or the "Better than last week" tag.
  List<Widget> _underTitle(String line) {
    if (line.isNotEmpty) {
      return [
        const SizedBox(height: 2),
        Text(line, style: _t(14, color: _light)),
      ];
    }
    final trend = _trend();
    return [if (trend != null) trend];
  }

  /// The day the week is named after (its open day).
  DateTime get _weekDate {
    final p = widget.weekId.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  /// "Mon 12 – Fri 16 Oct" (or "Mon 28 Sep – Fri 2 Oct").
  String _weekDates() {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final d = _weekDate;
    final mon = DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));
    final fri = DateTime(mon.year, mon.month, mon.day + 4);
    final start = mon.month == fri.month
        ? 'Mon ${mon.day}'
        : 'Mon ${mon.day} ${months[mon.month - 1]}';
    return '$start – Fri ${fri.day} ${months[fri.month - 1]}';
  }

  /// The top: "This week" with "Mon 12 – Fri 16 Oct" under it, and the
  /// chip on the right. Older weeks show only the dates.
  Widget _top(Widget chip) {
    final name = PulseService.weekName(widget.weekId);
    final dates = _weekDates();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? dates : name,
                style: _t(15, weight: FontWeight.w600),
              ),
              if (name.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(dates, style: _t(12.5, color: _soft)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        chip,
      ],
    );
  }

  // ---------------------------------------------------------------------
  // 1. Starting soon
  // ---------------------------------------------------------------------
  Widget _soon() {
    var d = PulseService.opensAt().difference(DateTime.now());
    if (d.isNegative) d = Duration.zero;
    String two(int n) => n.toString().padLeft(2, '0');
    final opensText = _TimelineState._dayTime(PulseService.opensAt());
    final closesText = _TimelineState._dayTime(
      PulseService.closesAt().subtract(const Duration(minutes: 1)),
    );

    // One part of the timer: a big number and a small unit.
    List<Widget> part(String number, String unit, {Color color = Colors.white}) =>
        [
          Text(
            number,
            style: _t(
              46,
              weight: FontWeight.w700,
              color: color,
              letterSpacing: -1.5,
              height: 1,
            ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 2, right: 10, bottom: 5),
            child: Text(unit, style: _t(15, color: _soft)),
          ),
        ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _top(
          const _HeroChip(
            'Starting soon',
            bg: Colors.transparent,
            fg: _light,
            outline: true,
          ),
        ),
        const SizedBox(height: 18),
        Text('Weekly Pulse opens in', style: _t(15, color: _light)),
        const SizedBox(height: 6),
        // The big timer. It shrinks a little on small phones.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (d.inDays > 0) ...part('${d.inDays}', 'd'),
              ...part(two(d.inHours % 24), 'h'),
              ...part(two(d.inMinutes % 60), 'm'),
              ...part(two(d.inSeconds % 60), 's', color: _glow),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // From Monday (left) to the heart (the moment it opens).
        // One beating dot: now.
        PulseLine(progress: _weekProgress()),
        const SizedBox(height: 10),
        // When it starts and when it ends.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _when('Starts', opensText)),
            _when('Ends', closesText, right: true),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // 2. Open now
  // ---------------------------------------------------------------------
  Widget _openNow() {
    final (title, line) = _headline(
      totals: widget.totals,
      total: widget.total,
      notOpenYet: false,
      closed: false,
    );
    final submitted = widget.totals.submitted;
    final waiting = (widget.total - submitted).clamp(0, widget.total);
    final everyone = widget.total > 0 && submitted >= widget.total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _top(
          const _HeroChip(
            'Open now',
            bg: Colors.white,
            fg: Color(0xFF15803D),
            dot: Color(0xFF16A34A),
          ),
        ),
        const SizedBox(height: 16),
        Text('Weekly Pulse is open', style: _t(15, color: _light)),
        const SizedBox(height: 2),
        Text(
          title,
          style: _t(28, weight: FontWeight.w700, letterSpacing: -0.6),
        ),
        ..._underTitle(line),
        const SizedBox(height: 10),
        // The line follows the answers. Everyone answered = the heart.
        PulseLine(
          progress: _answered,
          moving: !everyone && submitted > 0,
          showDot: !everyone,
          heartColor: everyone ? _pink : Colors.white,
        ),
        if (widget.total > 0) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _when('Answered', '$submitted of ${widget.total}'),
              ),
              _when(
                'Waiting',
                everyone ? 'Nobody' : '$waiting people',
                right: true,
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        if (AppConfig.pulseOpenEveryDay)
          Text('Test mode: open every day', style: _t(13, color: _soft))
        else
        // Opened → Now (time left) → Closes.
          _Timeline(
            opensAt: PulseService.opensAt(_weekDate),
            closesAt: PulseService.closesAt(_weekDate),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // 3. Closed
  // ---------------------------------------------------------------------
  Widget _closed() {
    final (title, line) = _headline(
      totals: widget.totals,
      total: widget.total,
      notOpenYet: false,
      closed: true,
    );
    final submitted = widget.totals.submitted;
    final missed = (widget.total - submitted).clamp(0, widget.total);

    final Widget bottom;
    if (widget.isThisWeek) {
      final nextWeek = PulseService.shortWeekLabel(PulseService.nextWeekId());
      final next = PulseService.dateTimeLabel(PulseService.nextOpensAt());
      bottom = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'NEXT WEEKLY PULSE',
            style: _t(11, weight: FontWeight.w600, color: _soft)
                .copyWith(letterSpacing: 1.1),
          ),
          const SizedBox(height: 4),
          Text(
            nextWeek,
            style: _t(15, weight: FontWeight.w600, color: Colors.white),
          ),
          const SizedBox(height: 2),
          Text(
            'Opens $next',
            style: _t(13, color: _soft),
          ),
        ],
      );
    } else {
      bottom = Text('This week is closed.', style: _t(13, color: _soft));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _top(
          _HeroChip(
            'Closed',
            bg: Colors.white.withValues(alpha: 0.14),
            fg: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        Text('Weekly Pulse closed', style: _t(15, color: _light)),
        const SizedBox(height: 2),
        Text(
          title,
          style: _t(28, weight: FontWeight.w700, letterSpacing: -0.6),
        ),
        ..._underTitle(line),
        const SizedBox(height: 10),
        // Faint: shows how far the answers got.
        PulseLine(
          progress: _answered,
          showDot: false,
          heartColor: Colors.white.withValues(alpha: 0.35),
          lineColor: Colors.white.withValues(alpha: 0.45),
        ),
        if (widget.total > 0) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _when('Answered', '$submitted of ${widget.total}'),
              ),
              _when("Didn't answer", '$missed', right: true),
            ],
          ),
        ],
        if (!AppConfig.pulseOpenEveryDay) ...[
          const SizedBox(height: 16),
          // Opened → Closed, all done.
          _Timeline(
            opensAt: PulseService.opensAt(_weekDate),
            closesAt: PulseService.closesAt(_weekDate),
            closed: true,
          ),
        ],
        const SizedBox(height: 14),
        bottom,
      ],
    );
  }
}

/// The time line at the bottom of the night-sky card:
///
///                  ( 2d 3h left )
///   ●──────────────────●─────────────────────●
///   Started at                          Ends at
///   Wed, 8:20 PM                   Fri, 11:59 PM
///
/// The bright part of the line is the time LEFT (dot → end), so just
/// after opening it is almost full, and it gets shorter until it ends.
/// The blue dot is now. It moves along the line as time passes, and the
/// time left moves with it. Once closed, the line is
/// full and faint, there is no time left, and the end says "Ended at".
class _Timeline extends StatefulWidget {
  const _Timeline({
    required this.opensAt,
    required this.closesAt,
    this.closed = false,
    this.onClosed,
  });

  final DateTime opensAt;

  /// Midnight after the last day. Shown as 11:59 PM.
  final DateTime closesAt;
  final bool closed;

  /// Called when the time runs out, so the card can change.
  final VoidCallback? onClosed;

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
  static const Color _soft = Color(0xFF9FB4F0);
  static const Color _glow = Color(0xFF7FA2FF);
  static const Color _light = Color(0xFFC9D6FF);

  // Moves the dot every 30 seconds.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    if (!widget.closed) {
      _tick = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// "Fri, 5:00 PM".
  static String _dayTime(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '${days[d.weekday - 1]}, $h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  static TextStyle _t(
      double size, {
        FontWeight weight = FontWeight.w400,
        Color color = Colors.white,
      }) =>
      GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color);

  @override
  Widget build(BuildContext context) {
    final closed = widget.closed;
    final all = widget.closesAt.difference(widget.opensAt).inSeconds;
    final gone = DateTime.now().difference(widget.opensAt).inSeconds;
    final progress = closed || all <= 0 ? 1.0 : (gone / all).clamp(0.0, 1.0);
    const lineColor = _glow;
    final endText = _dayTime(
      widget.closesAt.subtract(const Duration(minutes: 1)),
    );

    Widget dot(Color c, double size, {bool glow = false}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        boxShadow: glow
            ? [BoxShadow(color: c.withValues(alpha: 0.25), spreadRadius: 4)]
            : null,
      ),
    );

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        // Where the "now" dot is (its left edge), 12 px wide.
        final x = (w - 12) * progress;
        final centre = x + 6;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The time left, just above the dot, in a small glass pill.
            if (!closed) ...[
              SizedBox(
                height: 22,
                child: Align(
                  // Follows the dot, but never goes off the card.
                  alignment: Alignment(w <= 0 ? 0 : centre / w * 2 - 1, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: LiveCountdown(
                      to: widget.closesAt,
                      onDone: widget.onClosed ?? () {},
                      suffix: ' left',
                      color: _light,
                      size: 11.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
            // The thin line with its dots.
            SizedBox(
              height: 12,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // The whole time, faint.
                  Positioned(
                    left: 5,
                    right: 5,
                    top: 5,
                    child: Container(
                      height: 2,
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  // The time that is LEFT: bright, from the dot to the end.
                  // It gets shorter as time passes. Once closed, nothing
                  // is left, so the whole line is faint.
                  if (!closed)
                    Positioned(
                      left: centre,
                      right: 5,
                      top: 5,
                      child: Container(height: 2, color: lineColor),
                    ),
                  // Start: already passed, so faint.
                  Positioned(
                    left: 0,
                    top: 1,
                    child: dot(Colors.white.withValues(alpha: 0.45), 10),
                  ),
                  // End: still to come (white), faint once closed.
                  Positioned(
                    right: 0,
                    top: 1,
                    child: dot(
                      closed
                          ? Colors.white.withValues(alpha: 0.45)
                          : Colors.white,
                      10,
                    ),
                  ),
                  // Now: a blue dot with a soft glow.
                  if (!closed)
                    Positioned(left: x, top: 0, child: dot(_glow, 12, glow: true)),
                ],
              ),
            ),
            const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Started at', style: _t(12, color: _soft)),
                      const SizedBox(height: 2),
                      Text(
                        _dayTime(widget.opensAt),
                        style: _t(13, weight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        closed ? 'Ended at' : 'Ends at',
                        style: _t(12, color: _soft),
                      ),
                      const SizedBox(height: 2),
                      Text(endText, style: _t(13, weight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// The small chip at the top right of the night-sky card.
/// [outline]: for something that has not started yet ("Opens Friday"):
/// no fill, a thin border, a clock icon and normal weight.
class _HeroChip extends StatelessWidget {
  const _HeroChip(
      this.text, {
        required this.bg,
        required this.fg,
        this.dot,
        this.outline = false,
      });

  final String text;
  final Color bg;
  final Color fg;
  final Color? dot;
  final bool outline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: outline ? Colors.transparent : bg,
        borderRadius: BorderRadius.circular(10),
        border: outline
            ? Border.all(color: Colors.white.withValues(alpha: 0.30))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (outline) ...[
            Icon(Icons.schedule_rounded, size: 13, color: fg),
            const SizedBox(width: 5),
          ],
          if (dot != null) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: outline ? FontWeight.w400 : FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Before the Weekly Pulse opens, in place of the ring:
///   👥 30 people can answer
///      Answers and the summary show here once it opens.
class _SoonNote extends StatelessWidget {
  const _SoonNote({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEDF0F6), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF2F6FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.groups_outlined,
              color: AppColors.blue,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  total == 0
                      ? 'No employees added yet'
                      : total == 1
                      ? '1 person can answer'
                      : '$total people can answer',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Answers and the summary show here once it opens.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    height: 1.4,
                    color: const Color(0xFF69728A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The reminder row under the ring, for example:
///   ⏳ 12 still waiting · Only they get the reminder      [🔔 Remind]
///   ✓ Reminder sent · Today, 4:12 PM                      [✓ Sent]
///   🎉 Everyone has answered · 30 of 30
///   🔕 12 didn't answer · This week is closed
/// "Sent" shows for one hour after the last reminder for this week.
class _RemindButton extends StatelessWidget {
  const _RemindButton({
    required this.weekId,
    required this.total,
    required this.pending,
    required this.canNotify,
    required this.windowOpen,
    required this.sending,
    required this.onRemind,
  });

  final String weekId;

  /// How many employees can answer. 0 means none added yet.
  final int total;
  final int pending;
  final bool canNotify;
  final bool windowOpen;
  final bool sending;
  final VoidCallback onRemind;

  static const Color _green = Color(0xFF15803D);
  static const Color _greenTint = Color(0xFFE7F6EC);
  static const Color _grey = Color(0xFFF2F4F8);

  /// When the last "Notify all" or "Remind" for this week was sent.
  Stream<DateTime?> _lastSent() => FirebaseFirestore.instance
      .collection('broadcasts')
      .where('weekId', isEqualTo: weekId)
      .snapshots()
      .map((snap) {
    DateTime? last;
    for (final d in snap.docs) {
      final t = d.data()['createdAt'];
      if (t is Timestamp) {
        final at = t.toDate();
        if (last == null || at.isAfter(last)) last = at;
      }
    }
    return last;
  });

  static String _when(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final time =
        '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
    if (day == today) return 'Today, $time';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday, $time';
    return '${PulseService.dateTimeLabel(d).split(',').first}, $time';
  }

  @override
  Widget build(BuildContext context) {
    if (total == 0) {
      return const _RemindRow(
        icon: Icons.group_add_outlined,
        iconBg: _grey,
        iconColor: AppColors.muted,
        title: 'No employees added yet',
        sub: 'Add accounts to start the Weekly Pulse',
      );
    }
    if (pending == 0) {
      return _RemindRow(
        icon: Icons.celebration_outlined,
        iconBg: _greenTint,
        iconColor: _green,
        title: 'Everyone has answered',
        sub: '$total of $total',
      );
    }
    final who = pending == 1 ? '1 person' : '$pending';
    if (!windowOpen) {
      return _RemindRow(
        icon: Icons.notifications_off_outlined,
        iconBg: _grey,
        iconColor: AppColors.muted,
        title: pending == 1 ? '1 person didn\'t answer' : '$pending didn\'t answer',
        sub: 'This week is closed',
      );
    }

    return StreamBuilder<DateTime?>(
      stream: _lastSent(),
      builder: (context, snap) {
        final last = snap.data;
        final justSent = last != null &&
            DateTime.now().difference(last) < const Duration(hours: 1);

        if (sending) {
          return _RemindRow(
            icon: Icons.hourglass_top,
            iconBg: _grey,
            iconColor: AppColors.muted,
            title: '$who still waiting',
            sub: 'Sending the reminder…',
            action: const _RemindPill(
              label: 'Sending…',
              bg: _grey,
              fg: Color(0xFF8E97AB),
            ),
          );
        }
        if (justSent) {
          return _RemindRow(
            icon: Icons.check,
            iconBg: _greenTint,
            iconColor: _green,
            title: 'Reminder sent',
            sub: '${_when(last!)} · $who still waiting',
            action: const _RemindPill(
              label: 'Sent',
              icon: Icons.check,
              bg: _greenTint,
              fg: _green,
            ),
          );
        }
        return _RemindRow(
          icon: Icons.hourglass_top,
          iconBg: _grey,
          iconColor: AppColors.muted,
          title: '$who still waiting',
          sub: last == null
              ? 'Only they get the reminder'
              : 'Last reminder: ${_when(last)}',
          action: canNotify
              ? _RemindPill(
            label: 'Remind',
            icon: Icons.notifications_none,
            bg: const Color(0xFFEEF3FF),
            fg: AppColors.blue,
            onTap: onRemind,
          )
              : null,
        );
      },
    );
  }
}

/// One reminder row: a small icon, a title and a line, and maybe a pill.
class _RemindRow extends StatelessWidget {
  const _RemindRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.sub,
    this.action,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String sub;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 19, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                sub,
                maxLines: 2,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: const Color(0xFF8E97AB),
                ),
              ),
            ],
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: 10),
          action!,
        ],
      ],
    );
  }
}

/// The small soft button on the right of the reminder row.
class _RemindPill extends StatelessWidget {
  const _RemindPill({
    required this.label,
    required this.bg,
    required this.fg,
    this.icon,
    this.onTap,
  });

  final String label;
  final Color bg;
  final Color fg;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
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
    this.closedThisWeek,
    required this.onPick,
  });

  /// Newest first.
  final List<String> weekIds;
  final Map<String, PulseTotals> weeks;
  final String selected;
  final String? upcoming;

  /// This week, when its window has already closed.
  final String? closedThisWeek;
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
          } else if (id == closedThisWeek) {
            sub = 'Closed · ${t.submitted} answered';
          } else if (isSelected && name.isNotEmpty) {
            sub = name;
          } else {
            sub = '${t.submitted} answered';
          }
          // Not open yet: an empty grey bar, never colours.
          final parts = [
            if (!isUpcoming)
              for (final r in PulseRating.all)
                if (t.countFor(r) > 0) r,
          ];

          return Material(
            // Not open yet: a light grey card, so it looks like it is waiting.
            color: isUpcoming
                ? const Color(0xFFF6F8FB)
                : isSelected
                ? const Color(0xFFF2F6FF)
                : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isSelected
                    ? (isUpcoming ? const Color(0xFFB9C7EE) : AppColors.blue)
                    : const Color(0xFFE3E8F2),
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
                      style: TextStyle(
                        fontSize: 13,
                        // Normal weight and grey until the week opens.
                        fontWeight:
                        isUpcoming ? FontWeight.w500 : FontWeight.w600,
                        color: isUpcoming
                            ? const Color(0xFF8E97AB)
                            : AppColors.ink,
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
                      style: TextStyle(
                        // "Opens Fri" in soft orange, like the Starting soon chip.
                        color: isUpcoming
                            ? const Color(0xFFB7791F)
                            : AppColors.muted,
                        fontSize: 12,
                        fontWeight:
                        isUpcoming ? FontWeight.w500 : FontWeight.w400,
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

/// A ring with "46/56 answered" in the middle, and the four ratings
/// listed beside it. (Who is still waiting shows in the reminder row.)
class _RingSummary extends StatelessWidget {
  const _RingSummary({required this.total, required this.totals});

  final int total;
  final PulseTotals totals;

  @override
  Widget build(BuildContext context) {
    final submitted = totals.submitted;
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
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return Row(
      children: [
        SizedBox(
          width: 140,
          height: 140,
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
                style: _h(19, weight: FontWeight.bold),
              ),
            ),
            if (comments.isNotEmpty)
              TextButton(
                onPressed: onSeeAll,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  backgroundColor: const Color(0xFFF3F4F6),
                  foregroundColor: const Color(0xFF374151),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('All ${comments.length}'),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 12,
                    ),
                  ],
                ),
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
  const _Quote({
    required this.item,
    required this.onTap,
  });

  final FeedbackItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rating = item.rating ?? PulseRating.okay;
    final who = item.anonymous
        ? 'Anonymous'
        : ((item.authorName?.trim().isNotEmpty ?? false)
        ? item.authorName!.trim()
        : 'Employee');

    final date = _FeedbackCard._date(item.createdAt);
    final needsReply = item.status == FeedbackStatus.newItem;
    final moodColor = _moodColor(rating);
    final moodInk = _moodInk(rating);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFEAECEF),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Mood badge and navigation indicator.
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: moodColor.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            PulseRating.icon(rating),
                            size: 15,
                            color: moodInk,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            PulseRating.label(rating),
                            style: TextStyle(
                              color: moodInk,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.arrow_outward_rounded,
                      size: 18,
                      color: AppColors.muted.withOpacity(0.7),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Feedback content.
                Text(
                  item.text.trim(),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    height: 1.55,
                    color: AppColors.ink,
                    fontWeight: FontWeight.w400,
                  ),
                ),

                const SizedBox(height: 16),
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFF0F1F3),
                ),
                const SizedBox(height: 13),

                // Author and date.
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        item.anonymous
                            ? Icons.lock_outline_rounded
                            : Icons.person_outline_rounded,
                        size: 18,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            who,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          if (date.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              date,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Status pill.
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: needsReply
                            ? const Color(0xFFFFF2E9)
                            : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (needsReply) ...[
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFFD9541E),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            needsReply
                                ? 'Needs reply'
                                : FeedbackStatus.label(item.status),
                            style: TextStyle(
                              color: needsReply
                                  ? const Color(0xFFD9541E)
                                  : AppColors.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
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
    FocusScope.of(context).unfocus();    Widget row({
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
    FocusManager.instance.primaryFocus?.unfocus();
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


/// A filter chip: colour dot, name and count.
/// Chosen: light blue with a blue border and a blue count.
/// Not chosen: white with a thin grey border. Chips with 0 are dimmed.
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
    const blue = AppColors.blue;
    final empty = count == 0 && !selected;
    final text = selected
        ? blue
        : empty
        ? const Color(0xFFA0A8B8)
        : const Color(0xFF344054);

    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $count',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: 36,
        decoration: ShapeDecoration(
          color: selected ? const Color(0xFFEEF3FF) : Colors.white,
          shape: StadiumBorder(
            side: BorderSide(
              color: selected ? blue : const Color(0xFFE3E8F1),
              width: selected ? 1.4 : 1,
            ),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dot != null) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: empty ? dot!.withValues(alpha: 0.4) : dot,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      color: text,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 7),
                  // The count, in a small round badge.
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 22,
                    constraints: const BoxConstraints(minWidth: 22),
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    alignment: Alignment.center,
                    decoration: ShapeDecoration(
                      color: selected ? blue : const Color(0xFFF2F4F8),
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : empty
                            ? const Color(0xFFA0A8B8)
                            : const Color(0xFF475467),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
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

/// The bottom bar with the two tabs ("clean classic" design):
/// icon and name, the chosen tab in blue with a short blue line on top,
/// and a red badge with the number of new suggestions.
class _BottomTabs extends StatelessWidget {
  const _BottomTabs({
    required this.index,
    required this.newCount,
    required this.onTap,
  });

  final int index;
  final int newCount;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEDF0F6))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              _tab(
                i: 0,
                icon: Icons.monitor_heart_outlined,
                activeIcon: Icons.monitor_heart,
                label: 'Weekly Pulse',
              ),
              _tab(
                i: 1,
                icon: Icons.lightbulb_outline,
                activeIcon: Icons.lightbulb,
                label: 'Suggestion Box',
                badge: newCount,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab({
    required int i,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    int badge = 0,
  }) {
    final selected = i == index;
    final color = selected ? AppColors.blue : const Color(0xFF8E97AB);

    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: badge > 0 ? '$label, $badge new' : label,
        child: InkWell(
          onTap: () => onTap(i),
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              // The short blue line on top of the chosen tab.
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                width: selected ? 44 : 0,
                height: 3,
                decoration: const BoxDecoration(
                  color: AppColors.blue,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(3),
                  ),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(selected ? activeIcon : icon, size: 23, color: color),
                        if (badge > 0)
                          Positioned(
                            top: -5,
                            right: -11,
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 18),
                              height: 18,
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE2583E),
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: Text(
                                badge > 99 ? '99+' : '$badge',
                                style: GoogleFonts.inter(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  height: 1,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: color,
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
}