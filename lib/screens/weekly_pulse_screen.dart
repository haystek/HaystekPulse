import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/employee.dart';
import '../models/pulse_rating.dart';
import '../services/feedback_service.dart';
import '../services/pulse_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

enum _Stage { loading, loadError, closed, alreadyDone, pick, done }

/// Weekly Pulse: one rating, one extra question for Okay or Difficult,
/// and a confirmation. One answer per employee per week.
///
/// The question screen ("night sky + list" design):
/// - a dark blue top with the week and "How was your week?",
/// - a white card with the four answers, each in its own colour, with a
///   short line and a tick circle,
/// - for Okay and Difficult, the comment box under it,
/// - a short privacy line and the Send button at the bottom.
class WeeklyPulseScreen extends StatefulWidget {
  const WeeklyPulseScreen({
    super.key,
    required this.employee,
    this.initialRating,
  });

  final Employee employee;

  /// The face tapped on the home screen. It starts already chosen.
  final String? initialRating;

  @override
  State<WeeklyPulseScreen> createState() => _WeeklyPulseScreenState();
}

class _WeeklyPulseScreenState extends State<WeeklyPulseScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _text = TextEditingController();
  final _scroll = ScrollController();

  /// The comment box, so the screen can scroll to it.
  final _commentKey = GlobalKey();

  final _textFocus = FocusNode();

  _Stage _stage = _Stage.loading;
  String? _rating;
  bool _anonymous = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _rating = widget.initialRating;
    _check();
    // The keyboard opening changes the screen size: see didChangeMetrics.
    WidgetsBinding.instance.addObserver(this);
    _textFocus.addListener(_scrollToEndSoon);
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    _textFocus.dispose();
    _settle?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _stage = _Stage.loading);
    if (!PulseService.isOpen()) {
      setState(() => _stage = _Stage.closed);
      return;
    }
    try {
      final existing =
      await PulseService.instance.myRatingThisWeek(widget.employee.uid);
      if (!mounted) return;
      setState(
            () => _stage = existing == null ? _Stage.pick : _Stage.alreadyDone,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _stage = _Stage.loadError);
    }
  }

  Timer? _settle;

  /// The keyboard is opening (the screen size changes on every frame).
  @override
  void didChangeMetrics() => _scrollToEndSoon();

  /// While typing: once the keyboard has finished opening, scroll all the
  /// way up, so the whole comment box, down to "Send anonymously", is
  /// above the Send button.
  void _scrollToEndSoon() {
    if (!_textFocus.hasFocus) return;
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 180), () {
      if (!mounted || !_scroll.hasClients || !_textFocus.hasFocus) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _pick(String rating) {
    final hadBox = _rating != null && PulseRating.needsText(_rating!);
    setState(() {
      _rating = rating;
      _error = null;
    });
    // Okay or Difficult: scroll up so the comment box is in view.
    if (PulseRating.needsText(rating) && !hadBox) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final box = _commentKey.currentContext;
        if (box == null || !mounted) return;
        Scrollable.ensureVisible(
          box,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          alignment: 0.05,
        );
      });
    }
  }

  Future<void> _submit() async {
    final rating = _rating;
    if (rating == null) return;
    if (PulseRating.needsText(rating) &&
        !_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await PulseService.instance.submit(
        employee: widget.employee,
        rating: rating,
        text: _text.text,
        anonymous: _anonymous,
      );
      if (!mounted) return;
      setState(() => _stage = _Stage.done);
    } catch (_) {
      if (!mounted) return;
      setState(
            () => _error = 'Could not send. Please check your internet '
            'connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_stage == _Stage.pick) return _buildPick(context);
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 68,
        leading: const AppBackButton(),
        titleSpacing: 4,
        centerTitle: false,
        title: Text('Weekly Pulse', style: heading(22)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Center(
              child: Text(
                PulseService.weekLabel(PulseService.currentWeekId()),
                style: const TextStyle(color: AppColors.muted, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: _body(context),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (_stage) {
      case _Stage.loading:
        return const Center(child: CircularProgressIndicator());
      case _Stage.loadError:
        return _Info(
          icon: Icons.wifi_off,
          title: 'Could not load',
          text: 'Please check your internet connection and try again.',
          buttonLabel: 'Try again',
          onPressed: _check,
        );
      case _Stage.closed:
        final next = PulseService.dateTimeLabel(PulseService.nextOpensAt());
        final beforeOpen = PulseService.notOpenYet();
        return _Info(
          icon: beforeOpen ? Icons.event : Icons.event_busy,
          title: beforeOpen ? 'Opens $next' : 'This week is closed',
          text: beforeOpen
              ? 'Please come back then.\n'
              'The Suggestion Box is open every day.'
              : 'The next Weekly Pulse opens $next.\n'
              'The Suggestion Box is open every day.',
          buttonLabel: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        );
      case _Stage.alreadyDone:
        return _Info(
          icon: Icons.check,
          title: 'Already answered',
          text: 'You have shared your feedback for this week.\nThank you.',
          buttonLabel: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        );
      case _Stage.pick:
        return _buildPick(context);
      case _Stage.done:
        return _Info(
          icon: Icons.check,
          title: 'Feedback sent',
          text: 'Thank you for your feedback.\nIt helps us improve.',
          buttonLabel: 'Done',
          onPressed: () => Navigator.of(context).pop(),
        );
    }
  }

  Widget _buildPick(BuildContext context) {
    final rating = _rating;
    final needsText = rating != null && PulseRating.needsText(rating);
    final top = MediaQuery.of(context).padding.top;
    final typing = MediaQuery.of(context).viewInsets.bottom > 0;
    final week = _weekDates(PulseService.currentWeekId());

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // White clock and battery icons on the dark top.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  SingleChildScrollView(
                    controller: _scroll,
                    padding: EdgeInsets.zero,
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // The dark blue "night sky" top. It scrolls
                          // with the page.
                          Container(
                            padding: EdgeInsets.fromLTRB(16, top + 8, 16, 20),
                            decoration: const BoxDecoration(
                              gradient: _sky,
                            ),
                            child: Center(
                              child: ConstrainedBox(
                                constraints:
                                const BoxConstraints(maxWidth: 480),
                                child: _header(context, week),
                              ),
                            ),
                          ),
                          // The answers and the comment box. The card sits
                          // half on the blue, like a sheet. (No Transform:
                          // so scrolling to the text box lands exactly.)
                          Stack(
                            children: [
                              const Positioned(
                                left: 0,
                                right: 0,
                                top: 0,
                                height: 44,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFF173A9E),
                                        AppColors.blue,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Center(
                                child: ConstrainedBox(
                                  constraints:
                                  const BoxConstraints(maxWidth: 480),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                      children: [
                                        _answers(rating),
                                        if (needsText) ...[
                                          const SizedBox(height: 14),
                                          KeyedSubtree(
                                            key: _commentKey,
                                            child: _commentBox(rating),
                                          ),
                                        ],
                                        if (_error != null) ...[
                                          const SizedBox(height: 12),
                                          Text(
                                            _error!,
                                            style: _inter(
                                              14,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                  // A fixed dark strip behind the clock and battery, so
                  // the page never scrolls under them.
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: top,
                    child: const ColoredBox(color: Color(0xFF0B1B4D)),
                  ),
                ],
              ),
            ),
            // The privacy line and the Send button, at the bottom.
            SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Hidden while the keyboard is open, to keep
                      // room for the text box.
                      if (!typing) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.lock_outline,
                              size: 14,
                              color: Color(0xFF8E97AB),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Your rating is only counted in the totals',
                              style: _inter(
                                12.5,
                                color: const Color(0xFF8E97AB),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      FilledButton(
                        onPressed:
                        rating == null || _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.blue,
                          disabledBackgroundColor: const Color(0xFFDDE4F2),
                          minimumSize: const Size.fromHeight(56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: _inter(16, weight: FontWeight.w600),
                        ),
                        child: _busy
                            ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : Text(
                          rating == null
                              ? 'Pick one to send'
                              : needsText
                              ? 'Send feedback'
                              : 'Send',
                        ),
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

  /// The top: back button, the week, and the question.
  Widget _header(BuildContext context, String week) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: Colors.white.withValues(alpha: 0.12),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Feedback for this week',
                style: _inter(12.5, color: const Color(0xFF9FB4F0)),
              ),
              const SizedBox(height: 2),
              Text(
                week,
                style: _inter(14, weight: FontWeight.w600, color: Colors.white),
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
              const SizedBox(height: 4),
              Text(
                'Pick the one that fits best.',
                style: _inter(14, color: const Color(0xFFC9D6FF)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The four answers in one white card.
  Widget _answers(String? rating) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F0E1A3A),
            blurRadius: 30,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          for (final option in PulseRating.all)
            _RatingRow(
              rating: option,
              selected: option == rating,
              onTap: _busy ? null : () => _pick(option),
            ),
        ],
      ),
    );
  }

  /// For Okay and Difficult: the question, a soft text box, and the
  /// anonymous switch in its own light row.
  Widget _commentBox(String rating) {
    final color = _colorOf(rating);
    OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c, width: w),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE6EBF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A small coloured tag, then the question.
          Row(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
                decoration: BoxDecoration(
                  color: _tintOf(rating),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PulseRating.icon(rating), size: 14, color: color),
                    const SizedBox(width: 5),
                    Text(
                      'You said ${PulseRating.label(rating)}',
                      style: _inter(12, weight: FontWeight.w600, color: color),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            PulseRating.question(rating),
            style: _inter(16, weight: FontWeight.w600, height: 1.35),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _text,
            focusNode: _textFocus,
            minLines: 4,
            maxLines: 8,
            maxLength: FeedbackService.maxTextLength,
            textCapitalization: TextCapitalization.sentences,
            style: _inter(15, height: 1.4),
            decoration: InputDecoration(
              hintText: 'A few words is enough. You can mention the '
                  'project, team or process.',
              hintStyle: _inter(14.5, color: const Color(0xFF9AA3B5)),
              hintMaxLines: 2,
              filled: true,
              fillColor: const Color(0xFFF6F8FB),
              contentPadding: const EdgeInsets.all(14),
              counterStyle: _inter(11.5, color: const Color(0xFF9AA3B5)),
              border: border(Colors.transparent, 0),
              enabledBorder: border(Colors.transparent, 0),
              focusedBorder: border(color, 1.5),
              errorBorder: border(const Color(0xFFE2583E), 1.2),
              focusedErrorBorder: border(const Color(0xFFE2583E), 1.5),
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Please write a few words'
                : null,
          ),
          const SizedBox(height: 6),
          // Anonymous: its own light row.
          Material(
            color: const Color(0xFFF6F8FB),
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _busy ? null : () => setState(() => _anonymous = !_anonymous),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _anonymous ? Icons.lock_outline : Icons.person_outline,
                        size: 18,
                        color: _anonymous ? AppColors.blue : AppColors.muted,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Send anonymously',
                            style: _inter(14.5, weight: FontWeight.w600),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            _anonymous
                                ? 'Your name and employee ID are hidden.'
                                : 'Management will see your name.',
                            style: _inter(12.5, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _anonymous,
                      activeTrackColor: AppColors.blue,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _anonymous = v),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The dark blue "night sky", same as the home card.
const LinearGradient _sky = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF0B1B4D), Color(0xFF14328F), AppColors.blue],
  stops: [0, 0.55, 1],
);

/// One font for this screen: Inter.
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

/// Each answer's own colour: Great blue, Good light blue, Okay amber,
/// Difficult red.
Color _colorOf(String rating) {
  switch (rating) {
    case PulseRating.great:
      return AppColors.blue;
    case PulseRating.good:
      return const Color(0xFF5B83EE);
    case PulseRating.okay:
      return const Color(0xFFD9961F);
    default:
      return const Color(0xFFE2583E);
  }
}

/// The light background of a chosen answer.
Color _tintOf(String rating) {
  switch (rating) {
    case PulseRating.great:
      return const Color(0xFFEAF0FF);
    case PulseRating.good:
      return const Color(0xFFEEF3FF);
    case PulseRating.okay:
      return const Color(0xFFFFF6E5);
    default:
      return const Color(0xFFFDEEEA);
  }
}

/// A short line under each answer.
String _hintOf(String rating) {
  switch (rating) {
    case PulseRating.great:
      return 'Productive and happy';
    case PulseRating.good:
      return 'A normal, fine week';
    case PulseRating.okay:
      return 'Some things were hard';
    default:
      return 'It was a tough week';
  }
}

/// One answer as a row: a face in its colour, the name and a short line,
/// and a tick circle. The chosen one gets a light colour and a border.
class _RatingRow extends StatelessWidget {
  const _RatingRow({
    required this.rating,
    required this.selected,
    required this.onTap,
  });

  final String rating;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = _colorOf(rating);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? _tintOf(rating) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected ? color : Colors.transparent,
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Icon(PulseRating.icon(rating), size: 34, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        PulseRating.label(rating),
                        style: _inter(16, weight: FontWeight.w600),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _hintOf(rating),
                        style: _inter(13, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: selected ? color : Colors.transparent,
                    shape: BoxShape.circle,
                    border: selected
                        ? null
                        : Border.all(color: const Color(0xFFD5DCE8), width: 2),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({
    required this.icon,
    required this.title,
    required this.text,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String text;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            child: CircleAvatar(
              radius: 36,
              backgroundColor: AppColors.blue,
              child: Icon(icon, color: Colors.white, size: 38),
            ),
          ),
          const SizedBox(height: 24),
          Text(title, textAlign: TextAlign.center, style: heading(28)),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 15.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}