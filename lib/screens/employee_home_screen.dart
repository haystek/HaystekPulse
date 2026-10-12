import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/employee.dart';
import '../models/feedback_item.dart';
import '../models/pulse_rating.dart';
import '../services/feedback_service.dart';
import '../services/pulse_service.dart';
import '../theme/app_theme.dart';
import '../widgets/notification_bell.dart';
import '../widgets/ui.dart';
import 'my_feedback_screen.dart';
import 'profile_screen.dart';
import 'suggestion_box_screen.dart';
import 'weekly_pulse_screen.dart';

const Color _purple = Color(0xFF7C3AED);
const Color _purpleTint = Color(0xFFF1EBFE);
const Color _softBlue = Color(0xFFC9D8FF);

/// One font for this whole screen: Inter (clean and easy to read).
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

/// Employee home (Inter font, "clean" design):
/// - a blue top with the real logo in a white box, and a greeting,
/// - the Weekly Pulse card sitting half over the blue,
/// - a Suggestion Box card with a Write button,
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

    final top = MediaQuery.of(context).padding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // White clock and battery icons on the blue top.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Blue top, with the Pulse card sitting half over it.
            Stack(
              children: [
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  bottom: 120,
                  child: ColoredBox(color: AppColors.blue),
                ),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, top + 10, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              // Real logo inside a small white box, so its
                              // blue and dark colours show clearly on blue.
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Image.asset(
                                  'assets/haystek_pulse_logo.png',
                                  height: 24,
                                  fit: BoxFit.contain,
                                ),
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
                                  MenuAction(
                                    'My Feedback',
                                        () => openFeedback(0),
                                  ),
                                  MenuAction(
                                    'Sign out',
                                        () => confirmSignOut(context),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Small greeting line.
                              Text(
                                '${_greeting().replaceAll(',', '')} 👋',
                                style: _inter(
                                  15,
                                  weight: FontWeight.w600,
                                  color: _softBlue,
                                ),
                              ),
                              const SizedBox(height: 4),
                              // Big name, first letter capital.
                              Text(
                                name[0].toUpperCase() + name.substring(1),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _inter(
                                  30,
                                  weight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1.1,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your week matters. Tell us how it went.',
                            style: _inter(15, color: _softBlue),
                          ),
                          const SizedBox(height: 20),
                          _PulseCard(
                            employee: employee,
                            onAnswer: () => _push(
                              context,
                              WeeklyPulseScreen(employee: employee),
                            ),
                            onSeeMine: () => openFeedback(1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    28 + MediaQuery.of(context).padding.bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SuggestCard(
                        onTap: () => _push(
                          context,
                          SuggestionBoxScreen(employee: employee),
                        ),
                      ),
                      const SizedBox(height: 22),
                      _RecentActivity(
                        employee: employee,
                        onOpen: openFeedback,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// White round button with a blue letter (for the blue top).
/// Opens a small menu.
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
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Text(
          initial,
          style: _inter(16, weight: FontWeight.w800, color: AppColors.blue),
        ),
      ),
    );
  }
}

/// White card with a soft shadow.
BoxDecoration _cardDecoration({Color color = Colors.white}) => BoxDecoration(
  color: color,
  borderRadius: BorderRadius.circular(24),
  border: Border.all(color: const Color(0xFFE6EBF4)),
  boxShadow: const [
    BoxShadow(
      color: Color(0x140E1A3A),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ],
);

// ---------------------------------------------------------------------
// Weekly Pulse card
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

  /// "5–9 OCT".
  String _weekShort() {
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    final p = _weekId.split('-').map(int.parse).toList();
    final d = DateTime(p[0], p[1], p[2]);
    final mon = DateTime(d.year, d.month, d.day - (d.weekday - 1));
    final fri = DateTime(mon.year, mon.month, mon.day + 4);
    return mon.month == fri.month
        ? '${mon.day}–${fri.day} ${months[fri.month - 1]}'
        : '${mon.day} ${months[mon.month - 1]}–${fri.day} '
        '${months[fri.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String?>(
      stream: _myRating,
      builder: (context, snap) {
        final rating = snap.data;
        final open = PulseService.isOpen();
        final openDay = PulseService.openDayLabel();
        final openTime = PulseService.openTimeLabel();
        final closeDay = PulseService.closeDayLabel();

        // Pill at the top right.
        final Widget pill;
        if (rating != null) {
          pill = const _Pill(text: 'Done', dot: Color(0xFF16A34A));
        } else if (open) {
          pill = const _Pill(text: 'Open', dot: Color(0xFF16A34A));
        } else {
          pill = _Pill(
            text: 'Opens ${openDay.length > 3 ? openDay.substring(0, 3) : openDay}',
            dot: const Color(0xFF8A94AA),
          );
        }

        // Icon, title and line in the middle.
        final IconData icon;
        final Color iconColor;
        final String title;
        final String line;
        if (rating != null) {
          icon = PulseRating.icon(rating);
          iconColor = PulseRating.color(rating);
          title = 'You said ${PulseRating.label(rating)}';
          line = open
              ? 'Thanks! See you next week.'
              : 'Next one opens $openDay $openTime';
        } else if (open) {
          icon = Icons.favorite;
          iconColor = AppColors.blue;
          title = 'Weekly Pulse';
          line = '10 seconds · until $closeDay night';
        } else {
          icon = Icons.schedule;
          iconColor = AppColors.blue;
          title = 'Weekly Pulse';
          line = 'Opens $openDay at $openTime';
        }

        return Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'THIS WEEK · ${_weekShort()}',
                      style: _inter(
                        12,
                        weight: FontWeight.w800,
                        color: AppColors.muted,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  pill,
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(icon, color: iconColor, size: 30),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: _inter(
                            19,
                            weight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          line,
                          style: _inter(14, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (rating != null)
                OutlinedButton(
                  onPressed: widget.onSeeMine,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: const StadiumBorder(),
                    side: const BorderSide(color: Color(0xFFD5DCE8), width: 1.5),
                    textStyle: _inter(15.5, weight: FontWeight.w700),
                  ),
                  child: const Text('See my Weekly Pulse'),
                )
              else
                FilledButton(
                  onPressed: open ? widget.onAnswer : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: const StadiumBorder(),
                    textStyle: _inter(15.5, weight: FontWeight.w700),
                  ),
                  child: Text(
                    open ? 'Give your rating' : 'Opens $openDay $openTime',
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Small pill with a coloured dot: "● Open".
class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.dot});

  final String text;
  final Color dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: dot.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: _inter(
              12.5,
              weight: FontWeight.w800,
              color: Color.lerp(dot, Colors.black, 0.35)!,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Suggestion Box card
// ---------------------------------------------------------------------

/// One wide card: icon, "Suggestion Box", a short line and a purple
/// Write button. Tapping anywhere on the card opens the Suggestion Box.
class _SuggestCard extends StatelessWidget {
  const _SuggestCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _cardDecoration(color: const Color(0xFFFAF7FF)),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _purpleTint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.lightbulb_outline,
                    color: _purple,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Suggestion Box',
                        style: _inter(16.5, weight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Any idea or problem? Any day.',
                        style: _inter(13.5, color: AppColors.muted),
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
                    minimumSize: const Size(0, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: const StadiumBorder(),
                    textStyle: _inter(14.5, weight: FontWeight.w700),
                  ),
                  child: const Text('Write'),
                ),
              ],
            ),
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
              'Weekly Pulse · ${PulseRating.label(rating)}',
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
            sub: 'Weekly Pulse · ${PulseService.weekLabel(weekId)}',
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
            if (f.isFromBox)
              'Suggestion'
            else if (rating != null)
              'Weekly Pulse · ${PulseRating.label(rating)}'
            else
              'Weekly Pulse',
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
            final rows = _merge(items, answers);
            if (rows.isEmpty) return const SizedBox.shrink();
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
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => widget.onOpen(0),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        textStyle: _inter(14.5, weight: FontWeight.w800),
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

  Widget _row(_Recent r) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFEEF1F6), width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onOpen(r.isBox ? 0 : 1),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: r.iconBg,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(r.icon, color: r.iconColor, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _inter(15, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (r.dot != null) ...[
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: r.dot,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            r.sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _inter(13, color: AppColors.muted),
                          ),
                        ),
                      ],
                    ),
                    // Clear line when management has written back.
                    if (r.hasReply) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F6EC),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.chat_bubble_outline,
                              size: 14,
                              color: Color(0xFF16A34A),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Management replied',
                              style: _inter(
                                12.5,
                                weight: FontWeight.w800,
                                color: const Color(0xFF166534),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.blue),
            ],
          ),
        ),
      ),
    );
  }
}
