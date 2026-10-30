import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/employee.dart';
import '../models/pulse_rating.dart';
import '../services/feedback_service.dart';
import '../services/pulse_service.dart';
import '../services/typed_name.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'help_screen.dart';
import 'typed_name_field.dart';

enum _Stage { loading, loadError, closed, alreadyDone, pick, done }

/// Soft greys used on this screen.
const _panel = Color(0xFFF6F8FB);
const _line = Color(0xFFE3E8F1);
const _soft = Color(0xFF8E97AB);

/// Weekly Pulse: one rating, one extra question for Okay or Difficult,
/// and a confirmation. One answer per employee per week.
///
/// The question screen ("four tiles" design):
/// - back arrow on the left, "Weekly Pulse" pill on the right,
/// - the week and "How was your week?",
/// - the four answers as a 2 x 2 grid of tiles, each in its own colour,
/// - for Okay and Difficult, the comment box (6 lines, scrolls inside)
///   with a counter and "Keep my name hidden",
/// - the Send button at the bottom.
///
/// When the keyboard opens, the title folds away and the comment box
/// moves up above the Send button.
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

  /// What was typed for Okay and for Difficult, kept apart, so switching
  /// between them shows each one's own text (empty the first time).
  final Map<String, String> _drafts = {};

  /// No name in the app (joined with an entry code): they type one.
  late final bool _needsName = TypedName.needed(widget.employee);

  /// Anonymous by default. "With my name" is a choice for this message.
  bool _anonymous = true;
  final _name = TextEditingController();
  String? _nameError;
  bool _busy = false;
  String? _error;

  Timer? _settle;

  @override
  void initState() {
    super.initState();
    _rating = widget.initialRating;
    if (_needsName) {
      TypedName.load().then((n) {
        if (mounted && _name.text.isEmpty) setState(() => _name.text = n);
      });
    }
    _check();
    // The keyboard opening changes the screen size: see didChangeMetrics.
    WidgetsBinding.instance.addObserver(this);
    _textFocus.addListener(() {
      if (!mounted) return;
      setState(() {}); // Border colour of the comment box.
      _scrollToEndSoon();
    });
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

  /// The keyboard is opening (the screen size changes on every frame).
  @override
  void didChangeMetrics() => _scrollToEndSoon();

  /// While typing: once the keyboard has finished opening, scroll all the
  /// way up, so the whole comment box is above the Send button.
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
    final old = _rating;
    final hadBox = old != null && PulseRating.needsText(old);
    if (rating == old) return;
    // Keep what was typed for the old answer, and show the new answer's own.
    if (hadBox) _drafts[old] = _text.text;
    final draft = _drafts[rating] ?? '';
    _text.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
    setState(() {
      _rating = rating;
      _error = null;
    });
    // Okay or Difficult: scroll so the comment box is in view.
    if (PulseRating.needsText(rating) && !hadBox) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final box = _commentKey.currentContext;
        if (box == null || !mounted) return;
        Scrollable.ensureVisible(
          box,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
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
    final named = PulseRating.needsText(rating) && _needsName && !_anonymous;
    if (named) {
      final problem = TypedName.check(_name.text);
      setState(() => _nameError = problem);
      if (problem != null) return;
      unawaited(TypedName.save(_name.text));
    }
    FocusScope.of(context).unfocus();
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
        name: named ? _name.text.trim() : null,
      );
      if (!mounted) return;
      setState(() => _stage = _Stage.done);
    } catch (error) {
      if (!mounted) return;
      if (error is SendError && error.alreadyAnswered) {
        // Answered already (maybe from another phone): show that screen.
        setState(() => _stage = _Stage.alreadyDone);
        return;
      }
      setState(
            () => _error = error is SendError
            ? error.message
            : 'Could not send. Please check your internet connection '
            'and try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      // Inter for every text on this screen.
      data: theme.copyWith(
        textTheme: GoogleFonts.interTextTheme(theme.textTheme),
      ),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            leadingWidth: 68,
            leading: const AppBackButton(),
            // No title on the left: the name sits on the right in a pill.
            title: const SizedBox.shrink(),
            actions: const [
              _TitlePill('Weekly Pulse', icon: Icons.monitor_heart_outlined),
            ],
          ),
          body: _stage == _Stage.pick
              ? _buildPick(context)
              : SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: _body(context),
              ),
            ),
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
    // Keyboard open: fold the title away to make room.
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: typing
                            ? const SizedBox(width: double.infinity)
                            : Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: _header(),
                        ),
                      ),
                      _tiles(rating),
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
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // The Send button, at the bottom.
        SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      onPressed: rating == null || _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _line,
                        disabledForegroundColor: _soft,
                        minimumSize: const Size.fromHeight(56),
                        shape: const StadiumBorder(),
                        textStyle: _inter(16, weight: FontWeight.w700),
                      ),
                      child: _busy
                          ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text('Sending…'),
                        ],
                      )
                          : Text(
                        rating == null
                            ? 'Pick one to send'
                            : needsText
                            ? 'Send feedback'
                            : 'Send',
                      ),
                    ),
                    // Only Okay / Difficult send words (with a name or not).
                    if (needsText) ...[
                      const SizedBox(height: 8),
                      SentAsLine(
                        named: !_anonymous,
                        name: _needsName
                            ? _name.text
                            : widget.employee.name,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The week, "How was your week?" and a short line.
  Widget _header() {
    final week = _weekDates(PulseService.currentWeekId()).toUpperCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          week,
          style: _inter(
            13,
            weight: FontWeight.w700,
            color: AppColors.blue,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'How was your week?',
          style: _inter(
            28,
            weight: FontWeight.w800,
            letterSpacing: -0.7,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Pick the one that fits best.',
          style: _inter(15, color: AppColors.muted),
        ),
      ],
    );
  }

  /// The four answers as a 2 x 2 grid.
  Widget _tiles(String? rating) {
    final all = PulseRating.all;
    Widget tile(int i) => Expanded(
      child: _RatingTile(
        rating: all[i],
        selected: all[i] == rating,
        onTap: _busy ? null : () => _pick(all[i]),
      ),
    );

    return Column(
      children: [
        for (var row = 0; row < all.length; row += 2) ...[
          if (row > 0) const SizedBox(height: 10),
          Row(
            children: [
              tile(row),
              const SizedBox(width: 10),
              if (row + 1 < all.length)
                tile(row + 1)
              else
                const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ],
    );
  }

  /// For Okay and Difficult: the question, the text box, and
  /// "Keep my name hidden".
  Widget _commentBox(String rating) {
    final color = _colorOf(rating);
    final focused = _textFocus.hasFocus;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: focused ? color : _line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            PulseRating.question(rating),
            style: _inter(15.5, weight: FontWeight.w700, height: 1.35),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _text,
            focusNode: _textFocus,
            // Fixed height: long text scrolls inside the box.
            minLines: 3,
            maxLines: 6,
            maxLength: FeedbackService.maxTextLength,
            enabled: !_busy,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            style: _inter(15.5, height: 1.5),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.zero,
              hintText: 'A few words is enough',
              hintStyle: _inter(15, color: _soft, height: 1.5),
              counterText: '',
              errorStyle: _inter(12.5, color: const Color(0xFFE2583E)),
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Please write a few words'
                : null,
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${_text.text.length} / ${FeedbackService.maxTextLength}',
              style: _inter(12, color: _soft),
            ),
          ),
          const SizedBox(height: 8),
          const SizedBox(height: 6),
          SendAsChoice(
            named: !_anonymous,
            enabled: !_busy,
            onChanged: (named) => setState(() {
              _anonymous = !named;
              _nameError = null;
            }),
          ),
          if (!_anonymous) ...[
            const SizedBox(height: 12),
            if (_needsName)
              TypedNameField(
                controller: _name,
                enabled: !_busy,
                error: _nameError,
                onChanged: (_) => setState(() => _nameError = null),
              )
            else
              Text(
                'Admin will see: ${widget.employee.name}',
                style: _inter(12.5, color: AppColors.muted),
              ),
          ],
          _privacyLink(),
        ],
      ),
    );
  }

  /// "How is my name hidden?" under the hide-name row. Opens Help & Privacy.
  Widget _privacyLink() {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const HelpScreen()),
        ),
        icon: const Icon(Icons.help_outline_rounded, size: 16),
        label: const Text('How is my name hidden?'),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.blue,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          textStyle: GoogleFonts.inter(fontSize: 13.5),
        ),
      ),
    );
  }

}

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

/// The light background of each answer.
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

/// One answer as a tile: the face in a circle at the top, the name and a
/// short line at the bottom. The chosen one takes its own colour.
class _RatingTile extends StatelessWidget {
  const _RatingTile({
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
    final tint = _tintOf(rating);
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: selected
              ? [
            BoxShadow(
              color: color.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ]
              : null,
        ),
        child: Material(
          color: selected ? tint : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: selected ? color : _line, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 112,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: selected ? Colors.white : tint,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            PulseRating.icon(rating),
                            size: 28,
                            color: color,
                          ),
                        ),
                        const Spacer(),
                        // Small tick on the chosen tile.
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: selected ? 1 : 0,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          PulseRating.label(rating),
                          style: _inter(
                            16,
                            weight: FontWeight.w800,
                            color: selected ? color : AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          _hintOf(rating),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _inter(12, color: AppColors.muted),
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
            style: _inter(15.5, color: AppColors.muted, height: 1.4),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.blue,
              minimumSize: const Size.fromHeight(56),
              shape: const StadiumBorder(),
              textStyle: _inter(16, weight: FontWeight.w700),
            ),
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}

/// Screen name on the right of the AppBar: pill with an icon.
/// Same as the Suggestion Box.
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