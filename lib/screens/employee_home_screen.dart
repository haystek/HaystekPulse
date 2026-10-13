import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config.dart';
import '../models/employee.dart';
import '../models/feedback_item.dart';
import '../models/pulse_rating.dart';
import '../services/feedback_service.dart';
import '../services/pulse_service.dart';
import '../theme/app_theme.dart';
import '../widgets/notification_bell.dart';
import '../widgets/pulse_line.dart';
import '../widgets/ui.dart' hide PulseLine;
import 'my_feedback_screen.dart';
import 'profile_screen.dart';
import 'suggestion_box_screen.dart';
import 'weekly_pulse_screen.dart';

const Color _purple = Color(0xFF7C3AED);
const Color _purpleTint = Color(0xFFF1EBFE);

/// Light grey panels (Suggestion Box and feedback rows).
const Color _panel = Color(0xFFF6F8FB);

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
/// - a quiet Suggestion Box panel with a Write button,
/// - your feedback (latest 3, with See all).
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
  late Stream<String?> _myRating;

  void _watch() {
    _weekId = PulseService.currentWeekId();
    _myRating = FirebaseFirestore.instance
        .collection('pulse_responses')
        .doc('${_weekId}_${widget.employee.uid}')
        .snapshots()
        .map((doc) => doc.data()?['rating'] as String?);
  }

  @override
  void initState() {
    super.initState();
    _watch();
    WidgetsBinding.instance.addObserver(this);
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
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String?>(
      stream: _myRating,
      builder: (context, snap) {
        final rating = snap.data;
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
        final week = 'This week, ${PulseService.shortWeekLabel(_weekId)}';

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

        if (rating != null) {
          return _DoneCard(
            week: week,
            rating: rating,
            next: open || everyDay ? null : next,
            onSeeMine: widget.onSeeMine,
          );
        }
        if (open) {
          return _OpenCard(
            week: week,
            everyDay: everyDay,
            closesAt: closesAt,
            closesText: closesText,
            onAnswer: widget.onAnswer,
            onClosed: _refresh,
          );
        }

        return _MissedCard(week: week, closesText: closesText, next: next);
      },
    );
  }
}

/// The small chip at the top right of each card.
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

/// The top line of each card: the week on the left, a chip on the right.
Widget _cardTop(String week, Widget chip, {Color color = _soft}) => Row(
  children: [
    Expanded(child: Text(week, style: _inter(13, color: color))),
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

  /// "Mon 12 Oct".
  String _monday() {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final m = _weekStart;
    return '${days[m.weekday - 1]} ${m.day} ${months[m.month - 1]}';
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
    final openDay = PulseService.openDayLabel();

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
              'Opens $openDay',
              bg: Colors.white.withValues(alpha: 0.30),
              fg: const Color(0xFFC9D6FF),
              outline: true,
            ),
            color: unitColor,
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
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: when('Week started', _monday())),
              when('Opens', widget.opensText, right: true),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Open till ${widget.closesText}',
            style: _inter(13, color: const Color(0xFFC9D6FF)),
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
    required this.closesAt,
    required this.closesText,
    required this.onAnswer,
    required this.onClosed,
  });

  final String week;
  final bool everyDay;
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
          ),
          const SizedBox(height: 16),
          Text(
            'Weekly Pulse is open',
            style: _inter(15, color: const Color(0xFFC9D6FF)),
          ),
          const SizedBox(height: 2),
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
          // The line has reached the heart.
          const PulseLine(
            progress: 1,
            heartColor: Color(0xFFFF6B8A),
            showDot: false,
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
          const SizedBox(height: 12),
          if (everyDay)
            Text('Test mode: open every day', style: _inter(13, color: _unit))
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Closes $closesText',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _inter(13, color: _unit),
                  ),
                ),
                const SizedBox(width: 8),
                LiveCountdown(
                  to: closesAt,
                  onDone: onClosed,
                  suffix: ' left',
                  color: const Color(0xFF7FA2FF),
                  size: 13,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 3. Done: a calm white card with a green tick.
class _DoneCard extends StatelessWidget {
  const _DoneCard({
    required this.week,
    required this.rating,
    required this.next,
    required this.onSeeMine,
  });

  final String week;
  final String rating;

  /// When the next one opens. Null while this week is still open.
  final String? next;
  final VoidCallback onSeeMine;

  @override
  Widget build(BuildContext context) {
    final color = PulseRating.color(rating);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE3E8F1), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardTop(
            week,
            const _Chip(
              'Done',
              bg: Color(0xFFE7F6EC),
              fg: Color(0xFF15803D),
              dot: Color(0xFF16A34A),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(PulseRating.icon(rating), color: color, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You said ${PulseRating.label(rating)}',
                      style: _inter(20, weight: FontWeight.w700),
                    ),
                    Text(
                      'Thanks for sharing this week.',
                      style: _inter(14, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (next != null) ...[
            const SizedBox(height: 14),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Next one: '),
                  TextSpan(
                    text: next,
                    style: _inter(13.5, weight: FontWeight.w600),
                  ),
                ],
              ),
              style: _inter(13.5, color: const Color(0xFF4A5470)),
            ),
          ],
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: onSeeMine,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.blue,
              minimumSize: const Size.fromHeight(50),
              side: const BorderSide(color: Color(0xFFD9DEEA), width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: _inter(15, weight: FontWeight.w600),
            ),
            child: const Text('See my Weekly Pulse'),
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

/// A quiet grey panel: icon, "Suggestion Box", a short line and a dark
/// Write button. Tapping anywhere on it opens the Suggestion Box.
class _SuggestCard extends StatelessWidget {
  const _SuggestCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _panel,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _purpleTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.lightbulb_outline,
                  color: _purple,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Suggestion Box',
                      style: _inter(15.5, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Share an idea or a problem, any day',
                      style: _inter(13, color: _soft),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.ink,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: _inter(14, weight: FontWeight.w600),
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
    this.dot,
    this.hasReply = false,
  });

  final DateTime date;
  final bool isBox;
  final String title;
  final String sub;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final Color? dot;
  final bool hasReply;
}

class _RecentActivityState extends State<_RecentActivity> {
  late final Stream<List<FeedbackItem>> _stream;
  late final String _thisWeek;
  late final Stream<Map<String, dynamic>?> _thisWeekAnswer;

  /// Answers from the last few weeks (not this week). Null while loading.
  List<Map<String, dynamic>>? _oldAnswers;

  static const int _weeksBack = 6;

  @override
  void initState() {
    super.initState();
    final uid = widget.employee.uid;
    _stream = FeedbackService.instance.watchMyFeedback(uid);
    _thisWeek = PulseService.currentWeekId();
    // This week live, so a new answer shows at once.
    _thisWeekAnswer = FirebaseFirestore.instance
        .collection('pulse_responses')
        .doc('${_thisWeek}_$uid')
        .snapshots()
        .map((d) => d.data() == null ? null : {...d.data()!, 'weekId': _thisWeek});
    _loadOld();
  }

  Future<void> _loadOld() async {
    final db = FirebaseFirestore.instance.collection('pulse_responses');
    final uid = widget.employee.uid;
    final found = await Future.wait([
      for (var i = 1; i <= _weeksBack; i++)
            () async {
          final w = PulseService.shiftWeek(_thisWeek, -i);
          try {
            final d = await db.doc('${w}_$uid').get();
            final data = d.data();
            return data == null ? null : {...data, 'weekId': w};
          } catch (_) {
            return null;
          }
        }(),
    ]);
    if (!mounted) return;
    setState(() => _oldAnswers = found.whereType<Map<String, dynamic>>().toList());
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

  static Color _statusDot(String status) {
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
              FeedbackStatus.label(c.status),
              _date(c.createdAt ?? at),
            ].join(' · '),
            icon: PulseRating.icon(rating),
            iconColor: color,
            iconBg: color.withValues(alpha: 0.12),
            dot: _statusDot(c.status),
            hasReply: c.hasReply,
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
            FeedbackStatus.label(f.status),
            _date(f.createdAt),
          ].where((x) => x.isNotEmpty).join(' · '),
          icon: f.isFromBox ? Icons.lightbulb_outline : Icons.favorite,
          iconColor: f.isFromBox ? _purple : AppColors.blue,
          iconBg: f.isFromBox ? _purpleTint : AppColors.blueTint,
          dot: _statusDot(f.status),
          hasReply: f.hasReply,
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
        return StreamBuilder<Map<String, dynamic>?>(
          stream: _thisWeekAnswer,
          builder: (context, weekSnap) {
            final answers = [
              if (weekSnap.data != null) weekSnap.data!,
              ...?_oldAnswers,
            ];
            // Wait until everything has loaded once, so the empty box
            // does not flash before the data arrives.
            final loading = (!snap.hasData && !snap.hasError) ||
                weekSnap.connectionState == ConnectionState.waiting ||
                _oldAnswers == null;
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
                          weight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    TextButton(
                      // Opens My Feedback on the tab of the newest item.
                      onPressed: () => widget.onOpen(rows.first.isBox ? 0 : 1),
                      style: TextButton.styleFrom(
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
          style: _inter(18, weight: FontWeight.w700, letterSpacing: -0.2),
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
                      'with replies from management.',
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

  Widget _row(_Recent r) {
    return Material(
      color: _panel,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onOpen(r.isBox ? 0 : 1),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
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
                    // What it is: Weekly Pulse or Suggestion.
                    Text(
                      r.isBox ? 'Suggestion' : 'Weekly Pulse',
                      style: _inter(
                        12.5,
                        weight: FontWeight.w600,
                        color: r.isBox ? _purple : AppColors.blue,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      r.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _inter(15, weight: FontWeight.w500),
                    ),
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: r.sub),
                          // Green words when management has written back.
                          if (r.hasReply)
                            TextSpan(
                              text: '  ·  Management replied',
                              style: _inter(
                                13,
                                weight: FontWeight.w500,
                                color: const Color(0xFF15803D),
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _inter(13, color: _soft),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: _soft),
            ],
          ),
        ),
      ),
    );
  }
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