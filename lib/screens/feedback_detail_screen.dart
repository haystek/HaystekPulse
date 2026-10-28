import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/feedback_item.dart';
import '../models/pulse_rating.dart';
import '../services/feedback_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'feedback_thread_screen.dart';

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

/// Management: open one entry, see the whole conversation, and reply.
///
/// Design C:
///   the employee's message in a grey card
///   the conversation as a timeline
///   at the bottom: [status button] [reply box] [send]
/// The status button opens a sheet: choose a new status, add an
/// optional message (needed for "Implemented"), "Change to …".
class FeedbackDetailScreen extends StatefulWidget {
  const FeedbackDetailScreen({super.key, required this.item});

  final FeedbackItem item;

  @override
  State<FeedbackDetailScreen> createState() => _FeedbackDetailScreenState();
}

class _FeedbackDetailScreenState extends State<FeedbackDetailScreen> {
  final _reply = TextEditingController();
  final _scroll = ScrollController();

  /// Live copy of the entry (status changes show at once).
  late FeedbackItem _item;
  StreamSubscription<FeedbackItem?>? _itemSub;
  late final Stream<List<ThreadEntry>> _thread;
  int _lastCount = -1;
  double _lastInset = 0;

  /// First name of the author, or null when anonymous or unknown.
  String? get _firstName {
    final item = _item;
    if (item.anonymous) return null;
    final name = (item.authorName ?? '').trim();
    if (name.isEmpty) return null;
    return name.split(RegExp(r'\s+')).first;
  }

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _reply.addListener(() => setState(() {}));
    _thread = FeedbackService.instance.watchThread(widget.item.id);
    _itemSub = FeedbackService.instance.watchOne(widget.item.id).listen((i) {
      if (i != null && mounted) setState(() => _item = i);
    });
  }

  @override
  void dispose() {
    _itemSub?.cancel();
    _reply.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// New line in the conversation: scroll down to it.
  void _scrollDownIfNew(int count) {
    if (count == _lastCount) return;
    final first = _lastCount < 0;
    _lastCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (first) {
        _scroll.jumpTo(end);
      } else {
        _scroll.animateTo(
          end,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  /// Reply only: shows at once, goes to the server when there is internet.
  void _sendReply() {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    _reply.clear();
    unawaited(
      FeedbackService.instance
          .sendMessage(item: _item, fromManagement: true, text: text)
          .catchError((Object e) {
        messenger.showSnackBar(SnackBar(content: Text('$e')));
        if (mounted && _reply.text.isEmpty) _reply.text = text;
      }),
    );
  }

  /// The "Change status" sheet.
  Future<void> _openStatusSheet() async {
    FocusScope.of(context).unfocus();
    final changed = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => _withInter(
        context,
        _StatusSheet(item: _item, employeeName: _firstName),
      ),
    );
    if (changed != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status changed to ${FeedbackStatus.label(changed)}.'),
        ),
      );
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
    final name = _firstName;
    // Keyboard opening: keep the newest message in view.
    _lastInset = keepLastInView(context, _scroll, _lastInset);
    return _withInter(
      context,
      Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          leadingWidth: 68,
          leading: const AppBackButton(),
          title: const SizedBox.shrink(),
          actions: [
            _TitlePill(
              _item.isFromBox ? 'Suggestion' : 'Weekly Pulse',
              icon: _item.isFromBox
                  ? Icons.lightbulb_outline
                  : Icons.monitor_heart_outlined,
            ),
          ],
        ),
        body: Column(
          children: [
            // Sticky: the employee's message stays on top.
            _MessageCard(item: _item, date: _date(_item.createdAt)),
            Expanded(
              child: StreamBuilder<List<ThreadEntry>>(
                stream: _thread,
                builder: (context, snap) {
                  final entries = snap.data ?? const <ThreadEntry>[];
                  if (snap.hasData) _scrollDownIfNew(entries.length);
                  final rows = buildThreadRows(_item, entries);
                  return ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    children: [
                      if (rows.isEmpty)
                        Text(
                          'No replies yet. Write below to reply, or tap the '
                              'list button to change the status.',
                          style: _t(
                            13.5,
                            weight: FontWeight.w400,
                            color: AppColors.muted,
                            height: 1.45,
                          ),
                        )
                      else
                        FeedbackTimeline(
                          rows: rows,
                          managementView: true,
                          employeeName: name,
                        ),
                    ],
                  );
                },
              ),
            ),
            ThreadComposer(
              controller: _reply,
              hint: name == null ? 'Reply to the employee…' : 'Reply to $name…',
              onSend: _sendReply,
              leading: Tooltip(
                message: 'Change status',
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(
                    side: BorderSide(color: Color(0xFFE3E8F1)),
                  ),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _openStatusSheet,
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(
                        Icons.tune_rounded,
                        size: 19,
                        color: AppColors.blue,
                      ),
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

/// The "Change status" sheet: the other statuses as a list, an optional
/// message (needed for "Implemented"), and "Change to …".
/// Closes with the new status when saved.
class _StatusSheet extends StatefulWidget {
  const _StatusSheet({required this.item, this.employeeName});

  final FeedbackItem item;
  final String? employeeName;

  @override
  State<_StatusSheet> createState() => _StatusSheetState();
}

class _StatusSheetState extends State<_StatusSheet> {
  final _message = TextEditingController();
  String? _chosen;
  bool _busy = false;
  String? _error;

  bool get _implemented => _chosen == FeedbackStatus.implemented;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final status = _chosen;
    if (status == null) return;
    final text = _message.text.trim();
    if (_implemented && text.isEmpty) {
      setState(() => _error = 'A message is needed for Implemented.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      await FeedbackService.instance.updateStatus(
        id: widget.item.id,
        status: status,
        message: text,
      );
      navigator.pop(status);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not update. Please check your internet '
            'connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = [
      for (final s in FeedbackStatus.all)
        if (s != widget.item.status) s,
    ];
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: 1.5),
    );

    return Padding(
      // Stay above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Change status', style: _t(17, weight: FontWeight.w400)),
                  ),
                  Text(
                    'Now: ',
                    style: _t(12.5, weight: FontWeight.w400, color: const Color(0xFF8E97AB)),
                  ),
                  _Pill(status: widget.item.status),
                ],
              ),
              const SizedBox(height: 12),
              _StatusList(
                options: options,
                chosen: _chosen,
                onTap: _busy
                    ? null
                    : (s) => setState(() {
                  _chosen = s == _chosen ? null : s;
                  _error = null;
                }),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _message,
                minLines: 2,
                maxLines: 5,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                style: _t(15, weight: FontWeight.w400, height: 1.4),
                decoration: InputDecoration(
                  hintText: _implemented
                      ? 'Tell ${widget.employeeName ?? 'them'} what has been done (needed)'
                      : 'Add a message (optional)',
                  hintStyle: _t(14.5, weight: FontWeight.w400, color: const Color(0xFF9AA3B8)),
                  contentPadding: const EdgeInsets.all(14),
                  border: border(const Color(0xFFE3E8F1)),
                  enabledBorder: border(const Color(0xFFE3E8F1)),
                  focusedBorder: border(AppColors.blue),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  style: _t(13.5, weight: FontWeight.w400, color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _busy || _chosen == null ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  disabledBackgroundColor: const Color(0xFFE3E8F1),
                  disabledForegroundColor: const Color(0xFF8E97AB),
                  minimumSize: const Size.fromHeight(52),
                  shape: const StadiumBorder(),
                  textStyle: _t(15.5),
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
                      : 'Change to ${FeedbackStatus.label(_chosen!)}',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The employee's message, sticky on top (grey card):
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

    return ThreadHeaderCard(
      text: item.text,
      top: Row(
        children: [
          Container(
            width: 32,
            height: 32,
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