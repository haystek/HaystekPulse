import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/feedback_item.dart';
import '../models/pulse_rating.dart';
import '../services/feedback_service.dart';
import '../theme/app_theme.dart';

/// Inter font for everything on this screen (same as the other screens).
Widget _withInter(BuildContext context, Widget child) {
  final t = Theme.of(context);
  return Theme(
    data: t.copyWith(textTheme: GoogleFonts.interTextTheme(t.textTheme)),
    child: child,
  );
}

TextStyle _t(
    double size, {
      FontWeight weight = FontWeight.w500,
      Color color = AppColors.ink,
      double? height,
    }) =>
    GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: size >= 18 ? -0.3 : -0.1,
    );

/// Night-sky colours (same as the home screens).
const _skyTop = Color(0xFF0B1B4D);
const _skyMid = Color(0xFF14328F);
const _soft = Color(0xFFC9D6FF);

/// A short line that says what each status means.
String _hint(String status) {
  switch (status) {
    case FeedbackStatus.underReview:
      return 'We are looking at it';
    case FeedbackStatus.planned:
      return 'We will do it';
    case FeedbackStatus.inProgress:
      return 'Work has started';
    case FeedbackStatus.implemented:
      return 'Done. Reply needed';
    case FeedbackStatus.noted:
      return 'Needs no work';
    default:
      return 'Just received';
  }
}

/// Example text inside the reply box, for each status.
String _replyHint(String status) {
  switch (status) {
    case FeedbackStatus.underReview:
      return 'For example: We are discussing this with the team leads.';
    case FeedbackStatus.planned:
      return 'For example: We will do this next month.';
    case FeedbackStatus.inProgress:
      return 'For example: Work has started. It should be done by Friday.';
    case FeedbackStatus.implemented:
      return 'Tell them what has been done';
    case FeedbackStatus.noted:
      return 'For example: Thanks for letting us know. Take care.';
    default:
      return 'Write a short message';
  }
}

/// Management: open one entry, move it to a new status, and reply.
/// The last reply sent shows on its own (not inside the box). The reply
/// box opens only after a new status is chosen, and starts empty: what
/// is written there goes with the new status. Needed for "Implemented",
/// optional for the others.
///
/// Design B: the employee's words on the night-sky header, a small
/// progress line, and the statuses to move to as cards.
class FeedbackDetailScreen extends StatefulWidget {
  const FeedbackDetailScreen({super.key, required this.item});

  final FeedbackItem item;

  @override
  State<FeedbackDetailScreen> createState() => _FeedbackDetailScreenState();
}

class _FeedbackDetailScreenState extends State<FeedbackDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _message;
  final _scroll = ScrollController();

  /// The status management tapped. Null until they choose one.
  String? _chosen;
  bool _busy = false;
  String? _error;

  String get _current => widget.item.status;

  /// What will be saved: the chosen status, or the current one.
  String get _status => _chosen ?? _current;

  bool get _implemented => _status == FeedbackStatus.implemented;

  /// The reply box shows once a new status is chosen (not for New).
  /// Needed for Implemented, optional for the others.
  bool get _showsReply =>
      _chosen != null && _chosen != FeedbackStatus.newItem;

  /// Something to save: only a new status (with its reply).
  bool get _canSave => _chosen != null;

  /// First name of the author, or null when anonymous or unknown.
  String? get _firstName {
    final item = widget.item;
    if (item.anonymous) return null;
    final name = (item.authorName ?? '').trim();
    if (name.isEmpty) return null;
    return name.split(RegExp(r'\s+')).first;
  }

  @override
  void initState() {
    super.initState();
    // Starts empty: the last reply shows on its own above.
    _message = TextEditingController();
  }

  @override
  void dispose() {
    _message.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Tap a status card. Tap again to undo the choice.
  /// Text you typed is kept when you switch between statuses.
  /// When the reply box opens, scroll down so the box is in view.
  void _choose(String s) {
    setState(() {
      _chosen = s == _chosen ? null : s;
      _error = null;
    });
    // A status was chosen: always bring the reply box into view.
    if (_chosen != null && _showsReply) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await FeedbackService.instance.updateStatus(
        id: widget.item.id,
        status: _status,
        message: _message.text,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Status updated to ${FeedbackStatus.label(_status)}.',
          ),
        ),
      );
      navigator.pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not update. Please check your internet '
            'connection and try again.';
      });
    }
  }

  String _date(DateTime? d) {
    if (d == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = _firstName;
    final options = [
      for (final s in FeedbackStatus.all)
        if (s != _current) s,
    ];

    OutlineInputBorder replyBorder(Color color, double width) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: color, width: width),
        );

    return _withInter(
      context,
      AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: EdgeInsets.zero,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Blue header with the employee's words.
                        DecoratedBox(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [_skyTop, _skyMid, AppColors.blue],
                              stops: [0, .55, 1],
                            ),
                          ),
                          child: _Header(
                            item: widget.item,
                            date: _date(widget.item.createdAt),
                          ),
                        ),
                        // The progress card sits half on the blue.
                        Stack(
                          children: [
                            const Positioned(
                              left: 0,
                              right: 0,
                              top: 0,
                              height: 44,
                              child: ColoredBox(color: AppColors.blue),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                              child: _ProgressCard(status: _current),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 22, 18, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // The reply already sent, on its own.
                              if (widget.item.hasReply) ...[
                                _LastReply(
                                  text: widget.item.managementMessage,
                                  date: _date(widget.item.updatedAt),
                                ),
                                const SizedBox(height: 22),
                              ],
                              Text(
                                'Move it to',
                                style: _t(15.5, weight: FontWeight.w700),
                              ),
                              const SizedBox(height: 10),
                              _OptionGrid(
                                options: options,
                                chosen: _chosen,
                                onTap: _busy ? null : _choose,
                              ),
                              if (_showsReply) ...[
                                const SizedBox(height: 22),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name == null
                                            ? 'Reply to the employee'
                                            : 'Reply to $name',
                                        style: _t(
                                          15.5,
                                          weight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _implemented ? 'Needed' : 'Optional',
                                      style: _t(
                                        12.5,
                                        color: _implemented
                                            ? AppColors.blue
                                            : AppColors.muted,
                                        weight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                TextFormField(
                                  controller: _message,
                                  minLines: 3,
                                  maxLines: 8,
                                  maxLength: 1000,
                                  // When typing, keep the whole box and the
                                  // line under it above the keyboard.
                                  scrollPadding:
                                  const EdgeInsets.only(bottom: 140),
                                  textCapitalization:
                                  TextCapitalization.sentences,
                                  style: _t(15, height: 1.45),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: Colors.white,
                                    hintText: _replyHint(_status),
                                    hintStyle: _t(
                                      15,
                                      color: const Color(0xFF9AA3B8),
                                    ),
                                    contentPadding: const EdgeInsets.all(14),
                                    border: replyBorder(AppColors.border, 1.5),
                                    enabledBorder:
                                    replyBorder(AppColors.border, 1.5),
                                    focusedBorder:
                                    replyBorder(AppColors.blue, 1.8),
                                    errorBorder: replyBorder(
                                      theme.colorScheme.error,
                                      1.5,
                                    ),
                                    focusedErrorBorder: replyBorder(
                                      theme.colorScheme.error,
                                      1.8,
                                    ),
                                  ),
                                  validator: (v) {
                                    if (!_implemented) return null;
                                    return (v == null || v.trim().isEmpty)
                                        ? 'A reply is needed for Implemented'
                                        : null;
                                  },
                                ),
                                Text(
                                  _implemented
                                      ? '${name ?? 'The employee'} gets a '
                                      'notification and sees it in My Feedback.'
                                      : 'Leave it empty to send only the new '
                                      'status. ${name ?? 'The employee'} sees '
                                      'it in My Feedback.',
                                  style: _t(
                                    13,
                                    color: AppColors.muted,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                              if (_error != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _error!,
                                  style: _t(
                                    14,
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // The button stays at the bottom, above the keyboard.
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.background,
                  border: Border(top: BorderSide(color: Color(0xFFEDF0F6))),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                    child: FilledButton(
                      onPressed: _busy || !_canSave ? null : _save,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        shape: const StadiumBorder(),
                        textStyle: _t(16, weight: FontWeight.w600),
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
                        _chosen == null
                            ? 'Choose a status'
                            : 'Change to '
                            '${FeedbackStatus.label(_chosen!)}',
                      ),
                    ),
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

/// The reply already sent to the employee: a light green card with a
/// small label and the date. Read only.
class _LastReply extends StatelessWidget {
  const _LastReply({required this.text, required this.date});

  final String text;
  final String date;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F7EE),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.check_circle_outline,
                size: 16,
                color: Color(0xFF15803D),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Your last reply',
                  style: _t(
                    12.5,
                    color: const Color(0xFF15803D),
                    weight: FontWeight.w600,
                  ),
                ),
              ),
              if (date.isNotEmpty)
                Text(
                  date,
                  style: _t(12, color: const Color(0xFF15803D)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(text, style: _t(14.5, weight: FontWeight.w400, height: 1.45)),
        ],
      ),
    );
  }
}

/// The blue top: back button, date, source tag, the employee's words
/// and who wrote it.
class _Header extends StatelessWidget {
  const _Header({required this.item, required this.date});

  final FeedbackItem item;
  final String date;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final rating = item.rating;
    final source = item.isFromBox
        ? 'Suggestion Box'
        : rating == null
        ? 'Weekly Pulse'
        : 'Weekly Pulse · ${PulseRating.label(rating)}';
    final name = (item.authorName ?? '').trim();
    final anonymous = item.anonymous || name.isEmpty;
    final who = anonymous ? 'Anonymous' : name;
    final initials = anonymous
        ? '?'
        : name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    final id = (item.authorEmployeeId ?? '').trim();

    return Padding(
      padding: EdgeInsets.fromLTRB(18, top + 8, 18, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _GlassButton(
                icon: Icons.chevron_left,
                tooltip: 'Back',
                onTap: () => Navigator.of(context).maybePop(),
              ),
              const Spacer(),
              if (date.isNotEmpty)
                Text(date, style: _t(13.5, color: _soft)),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: .2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  item.isFromBox
                      ? Icons.lightbulb_outline
                      : Icons.monitor_heart_outlined,
                  size: 15,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  source,
                  style: _t(12.5, color: Colors.white, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            item.text.trim(),
            style: _t(
              19.5,
              color: Colors.white,
              weight: FontWeight.w600,
              height: 1.38,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .18),
                  shape: BoxShape.circle,
                ),
                child: anonymous
                    ? const Icon(
                  Icons.person_outline,
                  size: 16,
                  color: Colors.white,
                )
                    : Text(
                  initials,
                  style: _t(
                    11.5,
                    color: Colors.white,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  !anonymous && id.isNotEmpty ? '$who · $id' : who,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _t(13.5, color: _soft),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: .12),
        shape: CircleBorder(
          side: BorderSide(color: Colors.white.withValues(alpha: .18)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }
}

/// White card on the edge of the blue: the status now, and a small
/// line with the five steps. For Noted it says "Needs no work" instead.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.status});

  final String status;

  static const _short = ['New', 'Review', 'Planned', 'Working', 'Done'];
  static const _done = Color(0xFF178A47);
  static const _grey = Color(0xFFE3E8F2);

  @override
  Widget build(BuildContext context) {
    final color = FeedbackStatus.color(status);
    final noted = status == FeedbackStatus.noted;
    final at = FeedbackStatus.steps.indexOf(status);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140E1A3A),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  noted ? 'Status' : 'Progress',
                  style: _t(15.5, weight: FontWeight.w700),
                ),
              ),
              _Pill(status: status),
            ],
          ),
          const SizedBox(height: 14),
          if (noted)
            Text(
              'Noted. This needs no work.',
              style: _t(13.5, color: AppColors.muted),
            )
          else ...[
            SizedBox(
              height: 22,
              child: Row(
                children: [
                  for (var i = 0; i < 5; i++) ...[
                    _Dot(
                      color: i < at
                          ? _done
                          : i == at
                          ? color
                          : _grey,
                      halo: i == at,
                    ),
                    if (i < 4)
                      Expanded(
                        child: Container(
                          height: 3,
                          color: i < at ? _done : _grey,
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var i = 0; i < 5; i++)
                  Expanded(
                    child: Text(
                      _short[i],
                      textAlign: i == 0
                          ? TextAlign.left
                          : i == 4
                          ? TextAlign.right
                          : TextAlign.center,
                      style: _t(
                        11,
                        color: i == at ? color : AppColors.muted,
                        weight: i == at ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.halo});

  final Color color;
  final bool halo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: halo
            ? [BoxShadow(color: color.withValues(alpha: .22), spreadRadius: 4)]
            : null,
      ),
    );
  }
}

/// Small coloured status tag.
class _Pill extends StatelessWidget {
  const _Pill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = FeedbackStatus.color(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            FeedbackStatus.label(status),
            style: _t(12.5, color: color, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// The statuses to move to, two per row.
class _OptionGrid extends StatelessWidget {
  const _OptionGrid({
    required this.options,
    required this.chosen,
    required this.onTap,
  });

  final List<String> options;
  final String? chosen;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < options.length; i += 2) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 9));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _option(options[i])),
              const SizedBox(width: 9),
              Expanded(
                child: i + 1 < options.length
                    ? _option(options[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _option(String s) => _OptionCard(
    status: s,
    selected: s == chosen,
    onTap: onTap == null ? null : () => onTap!(s),
  );
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final String status;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = FeedbackStatus.color(status);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.blueTint : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? AppColors.blue : AppColors.border,
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        FeedbackStatus.label(status),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _t(14, weight: FontWeight.w600),
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.check,
                        size: 16,
                        color: AppColors.blue,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _hint(status),
                  style: _t(12, color: AppColors.muted, height: 1.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
