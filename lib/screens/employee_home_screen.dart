import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config.dart';
import '../demo_data.dart';
import '../models/employee.dart';
import '../models/feedback_item.dart';
import '../models/pulse_rating.dart';
import '../services/broadcast_service.dart';
import '../services/feedback_service.dart';
import '../services/notification_service.dart';
import '../services/pulse_service.dart';
import '../services/schedule_service.dart';
import '../services/vault_service.dart';
import '../theme/app_theme.dart';
import '../widgets/notification_bell.dart';
import '../widgets/pulse_line.dart';
import '../widgets/ui.dart' hide PulseLine;
import 'broadcast_screens.dart';
import 'feedback_thread_screen.dart';
import 'my_feedback_screen.dart';
import 'profile_screen.dart';
import 'suggestion_box_screen.dart';
import 'weekly_pulse_screen.dart';

/// Thin borders around the feedback rows.
const Color _line = Color(0xFFE3E8F1);

/// Soft grey for small, less important text.
const Color _soft = Color(0xFF8E97AB);

/// One font for this whole screen: Inter.
TextStyle _inter(
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

/// Employee home ("Blue card" design):
/// - a white top with the logo, the bell and the account button,
/// - a greeting with the person's name,
/// - the Weekly Pulse as one blue card: when it closes, time left, button,
/// - the Suggestion Box as a light blue card with a blue Write button,
/// - your feedback (latest 3, with See all): white rows with a status chip.
class EmployeeHomeScreen extends StatelessWidget {
  const EmployeeHomeScreen({super.key, required this.employee});

  final Employee employee;

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning,';
    if (h < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  @override
  Widget build(BuildContext context) {
    void openFeedback(int tab) => _push(
      context,
      MyFeedbackScreen(employee: employee, initialTab: tab),
    );
    final name = employee.name.trim().isEmpty ? 'there' : employee.name.trim();
    final pad = MediaQuery.of(context).padding;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Dark clock and battery icons on the white top.
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, pad.top + 10, 16, 28 + pad.bottom),
              children: [
                // Top: logo, bell, account.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/haystek_pulse_logo.png',
                        height: 26,
                        fit: BoxFit.contain,
                      ),
                      const Spacer(),
                      NotificationBell(employee: employee),
                      const SizedBox(width: 10),
                      _AccountButton(
                        name: employee.name,
                        actions: [
                          MenuAction(
                            'Profile',
                                () => _push(
                              context,
                              ProfileScreen(employee: employee),
                            ),
                          ),
                          MenuAction('My Feedback', () => openFeedback(0)),
                          MenuAction(
                            'Sign out',
                                () => confirmSignOut(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                // Greeting.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _greeting(),
                        style: _inter(15, color: AppColors.muted),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        name[0].toUpperCase() + name.substring(1),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _inter(
                          28,
                          weight: FontWeight.w700,
                          height: 1.15,
                          letterSpacing: -0.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _PulseCard(
                  employee: employee,
                  onAnswer: () => _push(
                    context,
                    WeeklyPulseScreen(employee: employee),
                  ),
                  onSeeMine: () => openFeedback(1),
                ),
                const SizedBox(height: 12),
                _SuggestCard(
                  onTap: () => _push(
                    context,
                    SuggestionBoxScreen(employee: employee),
                  ),
                ),
                const SizedBox(height: 12),
                _BroadcastCard(
                  uid: employee.uid,
                  onTap: () => _push(
                    context,
                    BroadcastListScreen(employee: employee),
                  ),
                ),
                const SizedBox(height: 22),
                _RecentActivity(employee: employee, onOpen: openFeedback),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Blue round button with a white letter. Opens a small menu.
class _AccountButton extends StatelessWidget {
  const _AccountButton({required this.name, required this.actions});

  final String name;
  final List<MenuAction> actions;

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
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.blue,
          shape: BoxShape.circle,
        ),
        child: Text(
          initial,
          style: _inter(16, weight: FontWeight.w700, color: Colors.white),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Weekly Pulse: one blue card
// ---------------------------------------------------------------------

class _PulseCard extends StatefulWidget {
  const _PulseCard({
    required this.employee,
    required this.onAnswer,
    required this.onSeeMine,
  });

  final Employee employee;
  final VoidCallback onAnswer;
  final VoidCallback onSeeMine;

  @override
  State<_PulseCard> createState() => _PulseCardState();
}

class _PulseCardState extends State<_PulseCard> with WidgetsBindingObserver {
  Timer? _timer;
  late String _weekId;

  /// This week's answer, and whether it came from the copy saved on the
  /// phone (it can be old) or from the server.
  late Stream<({String? rating, bool cached})> _myRating;

  /// After 4 seconds, stop waiting for the server (offline) and use the
  /// copy saved on the phone.
  bool _stopWaiting = false;
  Timer? _waitTimer;

  void _watch() {
    _weekId = PulseService.currentWeekId();
    _myRating = FirebaseFirestore.instance
        .collection('pulse_responses')
        .doc('${_weekId}_${widget.employee.uid}')
        .snapshots(includeMetadataChanges: true)
        .map(
          (doc) => (
      // The server only knows "answered" (''). What was chosen is in
      // the locked history, looked up in build().
      rating: doc.exists ? '' : null,
      cached: doc.metadata.isFromCache,
      ),
    );
    _stopWaiting = false;
    _waitTimer?.cancel();
    _waitTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _stopWaiting = true);
    });
  }

  /// settings/pulse changed in Firebase: redraw at once. A new open
  /// day means a new week id, so watch again.
  void _onSchedule() {
    if (!mounted) return;
    setState(_watch);
  }

  @override
  void initState() {
    super.initState();
    _watch();
    ScheduleService.changed.addListener(_onSchedule);
    WidgetsBinding.instance.addObserver(this);
    // Make sure this phone is in this week's reminder group.
    NotificationService.instance.refreshPending();
    // Look at the clock every 30 seconds: the card changes by itself
    // when the window opens or closes, or a new week starts.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() {
        if (PulseService.currentWeekId() != _weekId) _watch();
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
      NotificationService.instance.refreshPending();
    }
  }

  @override
  void dispose() {
    ScheduleService.changed.removeListener(_onSchedule);
    _timer?.cancel();
    _waitTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild also when the locked history changes (the rating is saved
    // there just after sending).
    return ValueListenableBuilder<VaultData?>(
      valueListenable: VaultService.instance.data,
      builder: (context, vault, _) => StreamBuilder<({String? rating, bool cached})>(
      stream: _myRating,
      builder: (context, snap) {
        final answer = snap.data;
        final rating = answer?.rating == null
            ? null
            : (vault?.pulse[_weekId] ?? '');
        final now = DateTime.now();
        // Test mode: open every day, so no dates are shown.
        const everyDay = AppConfig.pulseOpenEveryDay;
        final open = PulseService.isOpen(now);
        final notOpenYet = PulseService.notOpenYet(now);

        final opensAt = PulseService.opensAt(now);
        // The window ends at midnight; show it as 11:59 PM of the last day.
        final closesAt = PulseService.closesAt(now);
        final closesText = PulseService.dateTimeLabel(
          closesAt.subtract(const Duration(minutes: 1)),
        );
        final next = PulseService.dateTimeLabel(PulseService.nextOpensAt(now));
        final week = _weekDates(_weekId);

        // Not open yet: always show the timer first, even if an old
        // answer exists (for example after the open time was changed).
        if (notOpenYet) {
          return _SoonCard(
            week: week,
            opensAt: opensAt,
            opensText: PulseService.dateTimeLabel(opensAt),
            closesText: closesText,
            onOpened: _refresh,
          );
        }

        // Not sure yet whether this week is answered: the phone's saved
        // copy says "not answered", but it can be old. Wait for the server
        // (at most 4 seconds), so the card does not show "Rate your week"
        // first and then jump to "Done".
        final unsure = answer == null ||
            (answer.cached && answer.rating == null && !_stopWaiting);
        if (unsure) return const _LoadingCard();

        if (rating != null) {
          return _DoneCard(
            week: week,
            rating: rating,
            // Always show the next one (also while this week is open).
            nextAt: everyDay ? null : PulseService.nextOpensAt(now),
            onSeeMine: widget.onSeeMine,
          );
        }
        if (open) {
          return _OpenCard(
            week: week,
            everyDay: everyDay,
            opensAt: opensAt,
            closesAt: closesAt,
            closesText: closesText,
            onAnswer: widget.onAnswer,
            onClosed: _refresh,
          );
        }

        return _MissedCard(week: week, closesText: closesText, next: next);
      },
      ),
    );
  }
}

/// Shown for a moment while this week's answer loads: a light grey card
/// with a small spinner, about the size of the real card, so nothing
/// jumps around.
class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 232,
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FB),
        borderRadius: BorderRadius.circular(26),
      ),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: AppColors.blue,
        ),
      ),
    );
  }
}

/// "Mon 12 – Fri 16 Oct" (or "Mon 28 Sep – Fri 2 Oct").
String _weekDates(String weekId) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final p = weekId.split('-').map(int.parse).toList();
  final d = DateTime(p[0], p[1], p[2]);
  final mon = DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));
  final fri = DateTime(mon.year, mon.month, mon.day + 4);
  final start = mon.month == fri.month
      ? 'Mon ${mon.day}'
      : 'Mon ${mon.day} ${months[mon.month - 1]}';
  return '$start – Fri ${fri.day} ${months[fri.month - 1]}';
}

/// The small chip at the top right of each card.
/// [outline]: only a thin border and a clock, for "not open yet".
class _Chip extends StatelessWidget {
  const _Chip(
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
        border: outline ? Border.all(color: bg, width: 1.2) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (outline) ...[
            Icon(Icons.schedule, size: 13, color: fg),
            const SizedBox(width: 5),
          ] else if (dot != null) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: _inter(
              12.5,
              // Not open yet: normal weight. Open, Done, Closed: semi-bold.
              weight: outline ? FontWeight.w400 : FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// The top of each card:
///   Feedback for this week              [chip]
///   Mon 12 – Fri 16 Oct
/// [dark]: white dates, for the night-sky cards.
Widget _cardTop(
    String week,
    Widget chip, {
      Color color = _soft,
      bool dark = false,
    }) =>
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Feedback for this week',
                style: _inter(12.5, color: color),
              ),
              const SizedBox(height: 2),
              Text(
                week,
                style: _inter(
                  15,
                  weight: FontWeight.w600,
                  color: dark ? Colors.white : AppColors.ink,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        chip,
      ],
    );

/// 1. About to open: a dark blue "night sky" card with a big live timer.
class _SoonCard extends StatefulWidget {
  const _SoonCard({
    required this.week,
    required this.opensAt,
    required this.opensText,
    required this.closesText,
    required this.onOpened,
  });

  final String week;
  final DateTime opensAt;
  final String opensText;
  final String closesText;
  final VoidCallback onOpened;

  @override
  State<_SoonCard> createState() => _SoonCardState();
}

class _SoonCardState extends State<_SoonCard> {
  Timer? _tick;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!_done && !DateTime.now().isBefore(widget.opensAt)) {
        _done = true;
        _tick?.cancel();
        widget.onOpened();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Monday 00:00 of this week.
  DateTime get _weekStart {
    final o = widget.opensAt;
    return DateTime(o.year, o.month, o.day - (o.weekday - DateTime.monday));
  }

  /// How far we are from Monday to the opening: 0.0 to 1.0.
  double _weekProgress() {
    final total = widget.opensAt.difference(_weekStart).inSeconds;
    if (total <= 0) return 1;
    final gone = DateTime.now().difference(_weekStart).inSeconds;
    return (gone / total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    var d = widget.opensAt.difference(DateTime.now());
    if (d.isNegative) d = Duration.zero;
    String two(int n) => n.toString().padLeft(2, '0');
    const unitColor = Color(0xFF9FB4F0);

    // One part of the timer: a big number and a small unit.
    List<Widget> part(String number, String unit, {Color color = Colors.white}) => [
      Text(
        number,
        style: _inter(
          46,
          weight: FontWeight.w700,
          color: color,
          letterSpacing: -1.5,
          height: 1,
        ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
      Padding(
        padding: const EdgeInsets.only(left: 2, right: 10, bottom: 5),
        child: Text(unit, style: _inter(15, color: unitColor)),
      ),
    ];

    Widget when(String label, String value, {bool right = false}) => Column(
      crossAxisAlignment:
      right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: _inter(13, color: unitColor)),
        const SizedBox(height: 2),
        Text(
          value,
          style: _inter(13, weight: FontWeight.w600, color: Colors.white),
        ),
      ],
    );

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardTop(
            widget.week,
            _Chip(
              'Starting soon',
              bg: Colors.white.withValues(alpha: 0.30),
              fg: const Color(0xFFC9D6FF),
              outline: true,
            ),
            color: unitColor,
            dark: true,
          ),
          const SizedBox(height: 18),
          Text(
            'Weekly Pulse opens in',
            style: _inter(15, color: const Color(0xFFC9D6FF)),
          ),
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
                ...part(
                  two(d.inSeconds % 60),
                  's',
                  color: const Color(0xFF7FA2FF),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // A heartbeat line from Monday (left) to the heart (the moment it
          // opens). The bright part is the time that has passed, and the
          // glowing dot is now. When the line reaches the heart, it opens.
          PulseLine(progress: _weekProgress()),
          const SizedBox(height: 10),
          // When it starts and when it ends.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: when('Starts', widget.opensText)),
              when('Ends', widget.closesText, right: true),
            ],
          ),
        ],
      ),
    );
  }
}

/// 2. Open now: the same night-sky card. The heartbeat line is full and
/// the heart has turned pink: the Weekly Pulse is open.
class _OpenCard extends StatelessWidget {
  const _OpenCard({
    required this.week,
    required this.everyDay,
    required this.opensAt,
    required this.closesAt,
    required this.closesText,
    required this.onAnswer,
    required this.onClosed,
  });

  final String week;
  final bool everyDay;
  final DateTime opensAt;
  final DateTime closesAt;
  final String closesText;
  final VoidCallback onAnswer;
  final VoidCallback onClosed;

  static const Color _unit = Color(0xFF9FB4F0);

  @override
  Widget build(BuildContext context) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardTop(
            week,
            const _Chip(
              'Open now',
              bg: Colors.white,
              fg: Color(0xFF15803D),
              dot: Color(0xFF16A34A),
            ),
            color: _unit,
            dark: true,
          ),
          const SizedBox(height: 18),
          Text(
            'How was your week?',
            style: _inter(
              28,
              weight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 10),
          // The line has reached the heart, and keeps running like a
          // heart monitor (same as management and sign in).
          const PulseLine(
            progress: 1,
            heartColor: Color(0xFFFF6B8A),
            showDot: false,
            moving: true,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onAnswer,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.blue,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: _inter(15.5, weight: FontWeight.w600),
            ),
            child: const Text('Rate your week'),
          ),
          const SizedBox(height: 18),
          if (everyDay)
            Text('Test mode: open every day', style: _inter(13, color: _unit))
          else
          // Opened → Now (time left) → Closes. Same as management.
            _Timeline(opensAt: opensAt, closesAt: closesAt, onClosed: onClosed),
        ],
      ),
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

/// 3. Done: the answer large on a soft coloured top, and the next
/// feedback date below. All dates come from settings/pulse.
class _DoneCard extends StatelessWidget {
  const _DoneCard({
    required this.week,
    required this.rating,
    required this.nextAt,
    required this.onSeeMine,
  });

  final String week;
  final String rating;

  /// When the next one opens. Null in test mode (open every day).
  final DateTime? nextAt;
  final VoidCallback onSeeMine;

  /// "in 8 days", "tomorrow", "today".
  static String _inDays(DateTime at) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final days = day.difference(today).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return 'tomorrow';
    return 'in $days days';
  }

  @override
  Widget build(BuildContext context) {
    // '' = answered, but what was chosen is not in this history.
    final known = PulseRating.all.contains(rating);
    final color = known ? PulseRating.color(rating) : AppColors.blue;
    // A darker shade of the answer colour, for small text on the tint.
    final deep = Color.lerp(color, const Color(0xFF0E1A3A), 0.45)!;

    // "Fri 23 Oct, 5:00 PM" -> "Fri 23 Oct" and "5:00 PM".
    String? date;
    String? time;
    if (nextAt != null) {
      final parts = PulseService.dateTimeLabel(nextAt!).split(', ');
      date = parts.first;
      time = parts.length > 1 ? parts[1] : null;
    }

    TextStyle cap(Color c) => _inter(
      11,
      weight: FontWeight.w600,
      color: c,
    ).copyWith(letterSpacing: 1.1);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE3E8F1), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top: soft colour of the answer.
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.13),
                  color.withValues(alpha: 0.04),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('FEEDBACK FOR THIS WEEK', style: cap(deep)),
                          const SizedBox(height: 3),
                          Text(
                            week,
                            style: _inter(13, color: deep)
                                .copyWith(fontWeight: FontWeight.w400),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x2615803D),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check,
                            size: 14,
                            color: Color(0xFF15803D),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Done',
                            style: _inter(
                              12,
                              weight: FontWeight.w600,
                              color: const Color(0xFF15803D),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(known ? 'YOU SAID' : 'ANSWERED', style: cap(deep)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        known ? PulseRating.label(rating) : 'Done',
                        style: _inter(
                          32,
                          weight: FontWeight.w800,
                          color: color,
                        ).copyWith(letterSpacing: -0.8, height: 1.15),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      known ? PulseRating.icon(rating) : Icons.check_circle_outline,
                      color: color,
                      size: 30,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Thanks for sharing this week.',
                  style: _inter(14, color: deep)
                      .copyWith(fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ),

          // Bottom: when the next one opens.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: date == null
                      ? Text(
                    'You can answer again any day.',
                    style: _inter(14, color: AppColors.muted),
                  )
                      : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NEXT FEEDBACK',
                        style: cap(const Color(0xFF8A94AD)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        date,
                        style: _inter(19, weight: FontWeight.w700)
                            .copyWith(letterSpacing: -0.3),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (time != null) 'at $time',
                          _inDays(nextAt!),
                        ].join(' · '),
                        style: _inter(13.5, color: AppColors.muted)
                            .copyWith(fontWeight: FontWeight.w400),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: onSeeMine,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.blue,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    textStyle: _inter(14.5, weight: FontWeight.w600),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('See mine'),
                      SizedBox(width: 2),
                      Icon(Icons.chevron_right, size: 20),
                    ],
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

/// 4. Missed: a grey card that says when the next one opens.
class _MissedCard extends StatelessWidget {
  const _MissedCard({
    required this.week,
    required this.closesText,
    required this.next,
  });

  final String week;
  final String closesText;
  final String next;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F5F8),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardTop(
            week,
            const _Chip(
              'Closed',
              bg: Color(0xFFE6E9EF),
              fg: Color(0xFF5B6478),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'You missed this week',
            style: _inter(20, weight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            'It closed $closesText.',
            style: _inter(14, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Next one opens', style: _inter(12, color: _soft)),
                const SizedBox(height: 2),
                Text(next, style: _inter(15, weight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Suggestion Box
// ---------------------------------------------------------------------

/// A light blue card: a blue bulb tile, "Suggestion Box", a short line
/// and a round blue Write button. Tapping anywhere opens the box.
class _SuggestCard extends StatelessWidget {
  const _SuggestCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.blueTint,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.blue,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.lightbulb_outline,
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
                      'Suggestion Box',
                      style: _inter(16, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ideas, concerns, requests. Any day.',
                      style: _inter(13, color: AppColors.muted, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: const StadiumBorder(),
                  textStyle: _inter(14, weight: FontWeight.w700),
                ),
                child: const Text('Write'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Broadcast: updates from admin
// ---------------------------------------------------------------------

/// A white card: a megaphone tile, "Broadcast", how many updates, and a
/// red badge with the number of new (unread) ones.
class _BroadcastCard extends StatefulWidget {
  const _BroadcastCard({required this.uid, required this.onTap});

  final String uid;
  final VoidCallback onTap;

  @override
  State<_BroadcastCard> createState() => _BroadcastCardState();
}

class _BroadcastCardState extends State<_BroadcastCard> {
  late final Stream<List<Broadcast>> _stream =
      BroadcastService.instance.watchAll();
  late final Stream<DateTime?> _seen =
      BroadcastService.instance.watchSeenAt(widget.uid);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DateTime?>(
      stream: _seen,
      builder: (context, seenSnap) => StreamBuilder<List<Broadcast>>(
        stream: _stream,
        builder: (context, snap) {
          final all = snap.data ?? const <Broadcast>[];
          final seenAt = seenSnap.data;
          // Still loading "last seen": show no badge yet, so it doesn't flash.
          final loading = seenSnap.connectionState == ConnectionState.waiting;
          final fresh = loading
              ? 0
              : all
              .where((b) =>
                  seenAt == null ||
                  (b.createdAt != null && b.createdAt!.isAfter(seenAt)))
              .length;
          final String sub;
          if (all.isEmpty) {
            sub = 'Updates from admin show here.';
          } else if (fresh > 0) {
            sub = fresh == 1 ? '1 new update' : '$fresh new updates';
          } else {
            sub = all.length == 1 ? '1 update · all read' : '${all.length} updates · all read';
          }
          return Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: const BorderSide(color: _line, width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.blueTint,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.campaign_outlined,
                        color: AppColors.blue,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Broadcast', style: _inter(16, weight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _inter(
                              13,
                              color: fresh > 0 ? AppColors.blue : AppColors.muted,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (fresh > 0) ...[
                      Container(
                        constraints: const BoxConstraints(minWidth: 22),
                        height: 22,
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2583E),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Text(
                          fresh > 99 ? '99+' : '$fresh',
                          style: _inter(12, weight: FontWeight.w600, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    const Icon(Icons.chevron_right, color: _soft),
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

// ---------------------------------------------------------------------
// Your feedback (latest 3)
// ---------------------------------------------------------------------

class _RecentActivity extends StatefulWidget {
  const _RecentActivity({required this.employee, required this.onOpen});

  final Employee employee;

  /// Opens My Feedback: 0 = Suggestions, 1 = Weekly Pulse.
  final void Function(int tab) onOpen;

  @override
  State<_RecentActivity> createState() => _RecentActivityState();
}

/// One row in "Your feedback": a suggestion, a Weekly Pulse comment, or
/// a Weekly Pulse answer with no comment (Great / Good).
class _Recent {
  const _Recent({
    required this.date,
    required this.isBox,
    required this.title,
    required this.sub,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    this.status,
    this.hasReply = false,
    this.item,
  });

  final DateTime date;
  final bool isBox;
  final String title;
  final String sub;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;

  /// The FeedbackStatus, shown as a small chip. Null for an answer with
  /// no comment.
  final String? status;
  final bool hasReply;

  /// The suggestion or comment behind this row. Tapping the row opens
  /// its conversation. Null for an answer with no comment (nothing more
  /// to show, so the row can't be tapped).
  final FeedbackItem? item;
}

class _RecentActivityState extends State<_RecentActivity> {
  late final Stream<List<FeedbackItem>> _stream;
  late final String _thisWeek;

  static const int _weeksBack = 6;

  @override
  void initState() {
    super.initState();
    _stream = FeedbackService.instance.watchMyFeedback(widget.employee.uid);
    _thisWeek = PulseService.currentWeekId();
  }

  /// My Weekly Pulse answers of the last few weeks, from the locked
  /// history (the server never stores what someone chose).
  List<Map<String, dynamic>> _answers(VaultData? vault) {
    final oldest = PulseService.shiftWeek(_thisWeek, -_weeksBack);
    final out = <Map<String, dynamic>>[
      for (final e in (vault?.pulse ?? const <String, String>{}).entries)
        if (e.key.compareTo(oldest) >= 0) {'weekId': e.key, 'rating': e.value},
    ];
    // Sample answers (DemoData), for weeks without a real answer.
    if (DemoData.on) {
      final have = {for (final a in out) a['weekId']};
      DemoData.myAnswers().forEach((weekId, a) {
        if (have.contains(weekId) || weekId == _thisWeek) return;
        out.add({
          'weekId': weekId,
          'rating': a.$1,
          'createdAt': Timestamp.fromDate(a.$2),
        });
      });
    }
    return out;
  }

  static String _date(DateTime? d) {
    if (d == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  static DateTime _weekDate(String weekId) {
    final p = weekId.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  /// Suggestions + pulse comments + pulse answers, newest first.
  List<_Recent> _merge(
      List<FeedbackItem> items,
      List<Map<String, dynamic>> answers,
      ) {
    final out = <_Recent>[];
    // Pulse comments by week, to put them together with their answer.
    final commentByWeek = <String, FeedbackItem>{
      for (final f in items)
        if (!f.isFromBox && f.weekId != null) f.weekId!: f,
    };
    final usedComments = <String>{};

    for (final a in answers) {
      final weekId = a['weekId'] as String;
      final rating = a['rating'] as String?;
      if (rating == null) continue;
      // Just sent: the time may not be there yet, so use now.
      final at = (a['createdAt'] as Timestamp?)?.toDate() ??
          (weekId == _thisWeek ? DateTime.now() : _weekDate(weekId));
      final c = commentByWeek[weekId];
      final color = PulseRating.color(rating);
      if (c != null && c.rating == rating) {
        // Answer with a comment: one row with the comment text.
        usedComments.add(c.id);
        out.add(
          _Recent(
            date: c.createdAt ?? at,
            isBox: false,
            title: c.text,
            sub: [
              'You said ${PulseRating.label(rating)}',
              _date(c.createdAt ?? at),
            ].join(' · '),
            icon: PulseRating.icon(rating),
            iconColor: color,
            iconBg: color.withValues(alpha: 0.12),
            status: c.status,
            hasReply: c.hasReply,
            item: c,
          ),
        );
      } else {
        // Answer with no comment (Great / Good).
        out.add(
          _Recent(
            date: at,
            isBox: false,
            title: 'You said ${PulseRating.label(rating)}',
            sub: 'Week of ${PulseService.weekLabel(weekId)}',
            icon: PulseRating.icon(rating),
            iconColor: color,
            iconBg: color.withValues(alpha: 0.12),
          ),
        );
      }
    }

    for (final f in items) {
      if (!f.isFromBox && usedComments.contains(f.id)) continue;
      final rating = f.rating;
      out.add(
        _Recent(
          date: f.createdAt ?? DateTime.now(),
          isBox: f.isFromBox,
          title: f.text,
          sub: [
            if (!f.isFromBox && rating != null)
              'You said ${PulseRating.label(rating)}',
            _date(f.createdAt),
          ].where((x) => x.isNotEmpty).join(' · '),
          icon: f.isFromBox ? Icons.lightbulb_outline : Icons.favorite,
          iconColor: AppColors.blue,
          iconBg: AppColors.blueTint,
          status: f.status,
          hasReply: f.hasReply,
          item: f,
        ),
      );
    }

    out.sort((x, y) => y.date.compareTo(x.date));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FeedbackItem>>(
      stream: _stream,
      builder: (context, snap) {
        final items = snap.data ?? const <FeedbackItem>[];
        return ValueListenableBuilder<VaultData?>(
          valueListenable: VaultService.instance.data,
          builder: (context, vault, _) {
            final answers = _answers(vault);
            // Wait until everything has loaded once, so the empty box
            // does not flash before the data arrives.
            final loading = !snap.hasData && !snap.hasError;
            if (loading) return const SizedBox.shrink();
            final rows = _merge(items, answers);
            if (rows.isEmpty) return _empty();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Your feedback',
                        style: _inter(
                          18,
                          weight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    TextButton(
                      // Opens My Feedback on the tab of the newest item.
                      onPressed: () => widget.onOpen(rows.first.isBox ? 0 : 1),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.blue,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        textStyle: _inter(14.5, weight: FontWeight.w600),
                      ),
                      child: const Text('See all'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final r in rows.take(3)) ...[
                  _row(r),
                  const SizedBox(height: 10),
                ],
              ],
            );
          },
        );
      },
    );
  }

  /// Shown when there is nothing yet: a dashed box that explains.
  Widget _empty() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your feedback',
          style: _inter(18, weight: FontWeight.w800, letterSpacing: -0.3),
        ),
        const SizedBox(height: 10),
        CustomPaint(
          painter: _DashedBorder(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
            child: Column(
              children: [
                const Icon(
                  Icons.chat_bubble_outline,
                  size: 28,
                  color: Color(0xFF8A94AA),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nothing here yet',
                  style: _inter(15, weight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your Weekly Pulse answers and suggestions show here, '
                      'with replies from admin.',
                  textAlign: TextAlign.center,
                  style: _inter(13.5, color: AppColors.muted, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// One white row with a thin border: icon, type and status chip,
  /// the text, and the date (+ "Management replied" in green).
  Widget _row(_Recent r) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: _line, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // A suggestion or comment opens in a bottom sheet. "You said
        // Good" has nothing more to show, so it can't be tapped.
        onTap: r.item == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => FeedbackThreadScreen(item: r.item!),
                  ),
                ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: r.iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(r.icon, color: r.iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // What it is, and its status.
                    Row(
                      children: [
                        Text(
                          r.isBox ? 'Suggestion' : 'Weekly Pulse',
                          style: _inter(
                            12,
                            weight: FontWeight.w700,
                            color: AppColors.blue,
                          ),
                        ),
                        if (r.status != null) ...[
                          const SizedBox(width: 6),
                          _statusChip(r.status!),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      r.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _inter(15, weight: FontWeight.normal),
                    ),
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: r.sub),
                          // Green words when management has written back.
                          if (r.hasReply)
                            TextSpan(
                              text: '  ·  Admin replied',
                              style: _inter(
                                12.5,
                                weight: FontWeight.w600,
                                color: const Color(0xFF15803D),
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _inter(12.5, color: _soft),
                    ),
                  ],
                ),
              ),
              if (r.item != null)
                const Icon(Icons.chevron_right, color: _soft)
              else
                const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
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

/// A small coloured chip with the status, e.g. "New" or "Implemented".
Widget _statusChip(String status, {double size = 11.5}) {
  final (fg, bg) = _statusColors(status);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(11),
    ),
    child: Text(
      FeedbackStatus.label(status),
      style: _inter(size, weight: FontWeight.w400, color: fg),
    ),
  );
}

/// A rounded dashed border, for the empty "Your feedback" box.
class _DashedBorder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD5DCE8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(20),
        ),
      );
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => false;
}