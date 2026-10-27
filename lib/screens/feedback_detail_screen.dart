import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/feedback_item.dart';
import '../models/pulse_rating.dart';
import '../services/feedback_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

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
/// Design A: the employee's message in a grey card, the last reply,
/// and the statuses to move to as a simple list.
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
      Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          leadingWidth: 68,
          leading: const AppBackButton(),
          // No title on the left: the name sits on the right in a pill.
          title: const SizedBox.shrink(),
          actions: [
            _TitlePill(
              widget.item.isFromBox ? 'Suggestion' : 'Weekly Pulse',
              icon: widget.item.isFromBox
                  ? Icons.lightbulb_outline
                  : Icons.monitor_heart_outlined,
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // The employee's message.
                      _MessageCard(
                        item: widget.item,
                        date: _date(widget.item.createdAt),
                      ),
                      // The reply already sent, on its own.
                      if (widget.item.hasReply) ...[
                        const SizedBox(height: 14),
                        _LastReply(
                          text: widget.item.managementMessage,
                          date: _date(widget.item.updatedAt),
                        ),
                      ],
                      const SizedBox(height: 22),
                      Text(
                        'Change status to',
                        style: _t(13, weight: FontWeight.w400, color: AppColors.muted),
                      ),
                      const SizedBox(height: 8),
                      _StatusList(
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
                                style: _t(13, weight: FontWeight.w400, color: AppColors.muted),
                              ),
                            ),
                            Text(
                              _implemented ? 'Needed' : 'Optional',
                              style: _t(
                                12,
                                weight: FontWeight.w400,
                                color: _implemented
                                    ? AppColors.blue
                                    : const Color(0xFF8E97AB),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _message,
                          minLines: 3,
                          maxLines: 8,
                          maxLength: 1000,
                          // When typing, keep the whole box and the line
                          // under it above the keyboard.
                          scrollPadding: const EdgeInsets.only(bottom: 140),
                          textCapitalization: TextCapitalization.sentences,
                          style: _t(15, weight: FontWeight.w400, height: 1.45),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            hintText: _replyHint(_status),
                            hintStyle: _t(
                              15,
                              weight: FontWeight.w400,
                              color: const Color(0xFF9AA3B8),
                            ),
                            contentPadding: const EdgeInsets.all(14),
                            border: replyBorder(const Color(0xFFE3E8F1), 1.5),
                            enabledBorder:
                            replyBorder(const Color(0xFFE3E8F1), 1.5),
                            focusedBorder: replyBorder(AppColors.blue, 1.5),
                            errorBorder:
                            replyBorder(theme.colorScheme.error, 1.5),
                            focusedErrorBorder:
                            replyBorder(theme.colorScheme.error, 1.5),
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
                            12.5,
                            weight: FontWeight.w400,
                            color: const Color(0xFF8E97AB),
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
                            weight: FontWeight.w400,
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // The button stays at the bottom, above the keyboard.
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFEEF1F6))),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: FilledButton(
                    onPressed: _busy || !_canSave ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.blue,
                      disabledBackgroundColor: const Color(0xFFE3E8F1),
                      disabledForegroundColor: const Color(0xFF8E97AB),
                      minimumSize: const Size.fromHeight(54),
                      shape: const StadiumBorder(),
                      textStyle: _t(16),
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
    );
  }
}

/// The reply already sent to the employee: a small green note. Read only.
///   ✓ Your last reply · 21 Oct
///     Thanks Ravi, we are checking with the cleaning team.
class _LastReply extends StatelessWidget {
  const _LastReply({required this.text, required this.date});

  final String text;
  final String date;

  static const _green = Color(0xFF15803D);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.check_rounded, size: 16, color: _green),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date.isEmpty ? 'Your last reply' : 'Your last reply · $date',
                  style: _t(13, color: _green),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: _t(
                    13.5,
                    weight: FontWeight.w400,
                    color: const Color(0xFF475467),
                    height: 1.4,
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

/// The employee's message in a light grey card:
///   [R]  Ravi Kumar               [● Under review]
///        HST1065 · 21 Oct
///   The pantry wasn't cleaned last week…
class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.item, required this.date});

  final FeedbackItem item;
  final String date;

  @override
  Widget build(BuildContext context) {
    final name = (item.authorName ?? '').trim();
    final anonymous = item.anonymous || name.isEmpty;
    final id = (item.authorEmployeeId ?? '').trim();
    final rating = item.rating;
    final sub = [
      if (!anonymous && id.isNotEmpty) id,
      if (date.isNotEmpty) date,
      if (!item.isFromBox && rating != null) PulseRating.label(rating),
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FB),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: anonymous ? Colors.white : AppColors.blueTint,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: anonymous
                    ? const Icon(
                  Icons.lock_outline_rounded,
                  size: 17,
                  color: Color(0xFF8E97AB),
                )
                    : Text(
                  name[0].toUpperCase(),
                  style: _t(14, color: AppColors.blue),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      anonymous ? 'Name hidden' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _t(14),
                    ),
                    if (sub.isNotEmpty)
                      Text(
                        sub,
                        style: _t(
                          12,
                          weight: FontWeight.w400,
                          color: const Color(0xFF8E97AB),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _Pill(status: item.status),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            item.text.trim(),
            style: _t(16, weight: FontWeight.w400, height: 1.5),
          ),
        ],
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
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            FeedbackStatus.label(status),
            style: _t(11.5, color: color),
          ),
        ],
      ),
    );
  }
}

/// The statuses to move to: one list, one per line, with a short hint and
/// a round select button. Tap again to undo.
class _StatusList extends StatelessWidget {
  const _StatusList({
    required this.options,
    required this.chosen,
    required this.onTap,
  });

  final List<String> options;
  final String? chosen;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE9EDF4)),
      ),
      clipBehavior: Clip.antiAlias,
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE9EDF4)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, thickness: 1, color: Color(0xFFF0F2F7)),
            _StatusRow(
              status: options[i],
              selected: options[i] == chosen,
              onTap: onTap == null ? null : () => onTap!(options[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
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
        color: selected ? const Color(0xFFF5F8FF) : Colors.white,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        FeedbackStatus.label(status),
                        style: _t(14.5, weight: FontWeight.w400),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _hint(status),
                        style: _t(
                          12,
                          weight: FontWeight.w400,
                          color: const Color(0xFF8E97AB),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Round select button.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? AppColors.blue
                          : const Color(0xFFC9D0DC),
                      width: selected ? 6 : 2,
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

/// Screen name on the right of the AppBar: a rounded pill with a blue
/// icon circle (same as the other screens).
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
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: AppColors.ink,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}