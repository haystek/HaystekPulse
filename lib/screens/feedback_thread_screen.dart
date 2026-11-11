import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/feedback_item.dart';
import '../models/pulse_rating.dart';
import '../services/feedback_service.dart';
import '../theme/app_theme.dart';
import '../services/notification_service.dart';

/// Employee: one suggestion or Weekly Pulse comment, with the whole
/// conversation and a reply box.
///
/// Design B "Timeline":
///   grey card    – status, "You · date", the full text
///   Conversation – replies and status changes on one line, oldest first
///   reply box    – at the bottom, above the keyboard
class FeedbackThreadScreen extends StatefulWidget {
  const FeedbackThreadScreen({super.key, required this.item});

  final FeedbackItem item;

  @override
  State<FeedbackThreadScreen> createState() => _FeedbackThreadScreenState();
}

class _FeedbackThreadScreenState extends State<FeedbackThreadScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  late final Stream<FeedbackItem?> _itemStream;
  late Stream<List<ThreadEntry>> _threadStream;
  int _limit = threadPageSize;
  final _keeper = ThreadScrollKeeper();
  bool _loadingOlder = false;
  int _shown = 0;
  double _lastInset = 0;

  /// Collapsing header: slim when reading older messages (or typing).
  bool _scrolledUp = false;

  /// Slim header tapped: stay open until the next scroll.
  bool _pinOpen = false;
  double _pinAt = 0;

  @override
  void initState() {
    super.initState();
    _itemStream = FeedbackService.instance.watchOne(widget.item.id);
    NotificationService.instance.openThreadId = widget.item.id;
    _threadStream = FeedbackService.instance.watchThread(
      widget.item.id,
      limit: _limit,
    );
    _text.addListener(() => setState(() {}));
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    if (NotificationService.instance.openThreadId == widget.item.id) {
      NotificationService.instance.openThreadId = null;
    }
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The list is reversed: offset 0 = newest at the bottom.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final o = _scroll.offset;
    final up = _scrolledUp ? o > 8 : o > 40;
    final pin = _pinOpen && (o - _pinAt).abs() <= 80;
    if (up != _scrolledUp || pin != _pinOpen) {
      setState(() {
        _scrolledUp = up;
        _pinOpen = pin;
      });
    }
  }

  /// Tap on the slim header: open the big one.
  void _expand() {
    FocusScope.of(context).unfocus();
    setState(() {
      _pinOpen = true;
      _pinAt = _scroll.hasClients ? _scroll.offset : 0;
    });
  }

  /// "Show older messages": load 50 more, with a small loader on top.
  void _showOlder() {
    if (_loadingOlder) return;
    setState(() {
      _loadingOlder = true;
      _limit += threadPageSize;
      _threadStream = FeedbackService.instance.watchThread(
        widget.item.id,
        limit: _limit,
      );
    });
    // Safety: never spin for ever (for example, no older ones after all).
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (mounted && _loadingOlder) setState(() => _loadingOlder = false);
    });
  }

  /// Shows on screen at once, goes to the server when there is internet.
  void _send(FeedbackItem item) {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    _text.clear();
    unawaited(
      FeedbackService.instance
          .sendMessage(item: item, fromManagement: false, text: text)
          .catchError((Object e) {
            messenger.showSnackBar(SnackBar(content: Text('$e')));
            // Put the text back so nothing is lost.
            if (mounted && _text.text.isEmpty) _text.text = text;
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Theme(
      data: t.copyWith(textTheme: GoogleFonts.plusJakartaSansTextTheme(t.textTheme)),
      child: StreamBuilder<FeedbackItem?>(
        stream: _itemStream,
        builder: (context, itemSnap) {
          // Live copy (status changes), or the one we were given.
          final item = itemSnap.data ?? widget.item;
          // Keyboard opening: keep the newest message in view.
          _lastInset = keepLastInView(context, _scroll, _lastInset);
          final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
          final collapsed = typing || (!_pinOpen && _scrolledUp);
          return Scaffold(
            backgroundColor: Colors.white,
            resizeToAvoidBottomInset: true,
            body: Column(
              children: [
                ThreadQuoteHeader(
                  item: item,
                  collapsed: collapsed,
                  onExpand: _expand,
                ),
                Expanded(
                  child: StreamBuilder<List<ThreadEntry>>(
                    stream: _threadStream,
                    builder: (context, snap) {
                      final entries = snap.data ?? const <ThreadEntry>[];
                      if (snap.hasData) _keeper.update(_scroll, entries);
                      // Older ones arrived: hide the loader.
                      if (_loadingOlder && entries.length > _shown) {
                        _loadingOlder = false;
                      }
                      if (!_loadingOlder) _shown = entries.length;
                      final hasOlder = entries.length >= _limit;
                      final showBar = hasOlder || _loadingOlder;
                      final rows = buildThreadRows(
                        item,
                        entries,
                        hasOlder: showBar,
                      );
                      return ThreadChatList(
                        controller: _scroll,
                        children: [
                          if (!snap.hasData && !snap.hasError)
                            const Padding(
                              padding: EdgeInsets.only(top: 20),
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: AppColors.blue,
                                  ),
                                ),
                              ),
                            )
                          else if (rows.isEmpty)
                            const _NoRepliesYet()
                          else ...[
                            if (showBar)
                              ThreadOlderBar(
                                loading: _loadingOlder,
                                onTap: _showOlder,
                              ),
                            FeedbackTimeline(rows: rows, managementView: false),
                          ],
                        ],
                      );
                    },
                  ),
                ),
                ThreadComposer(
                  controller: _text,
                  hint: 'Reply to admin…',
                  onSend: () => _send(item),
                  footnote: item.anonymous
                      ? 'Your name stays hidden in replies too.'
                      : null,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Shared with the management screen (feedback_detail_screen.dart)
// ---------------------------------------------------------------------

const Color threadSoft = Color(0xFF8E97AB);
const Color threadLine = Color(0xFFE9EDF4);

TextStyle threadText(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.ink,
  double? height,
}) => GoogleFonts.plusJakartaSans(
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
);

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "22 Oct, 2:40 PM".
String threadDate(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${_months[d.month - 1]}, $h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// When the keyboard opens (or grows), jump to the newest message so
/// it stays just above the reply box. Call from build; returns the
/// keyboard height to keep for next time.
double keepLastInView(
  BuildContext context,
  ScrollController scroll,
  double lastInset,
) {
  final inset = MediaQuery.viewInsetsOf(context).bottom;
  if (inset > lastInset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) return;
      final p = scroll.position;
      // Chat list is upside down (newest = 0); other lists: the end.
      scroll.jumpTo(
        p.axisDirection == AxisDirection.up ? 0 : p.maxScrollExtent,
      );
    });
  }
  return inset;
}

/// The original message, fixed under the top bar (does not scroll).
/// Long text shows 3 lines with "More"; 2 lines while typing, so the
/// chat keeps its space.
class ThreadHeaderCard extends StatefulWidget {
  const ThreadHeaderCard({super.key, this.top, required this.text});

  /// Name / date / status row.
  final Widget? top;
  final String text;

  @override
  State<ThreadHeaderCard> createState() => _ThreadHeaderCardState();
}

class _ThreadHeaderCardState extends State<ThreadHeaderCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    final lines = typing ? 2 : 3;
    final open = _open && !typing;
    final style = threadText(15, height: 1.45);
    final text = widget.text.trim();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEEF1F6))),
      ),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F8FB),
          borderRadius: BorderRadius.circular(16),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            // Does the text need more than [lines] lines?
            final painter = TextPainter(
              text: TextSpan(text: text, style: style),
              maxLines: lines,
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: box.maxWidth);
            final long = painter.didExceedMaxLines;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.top != null) ...[
                  widget.top!,
                  const SizedBox(height: 8),
                ],
                if (open)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.35,
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(text, style: style),
                    ),
                  )
                else
                  Text(
                    text,
                    maxLines: lines,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                if (long && !typing)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: () => setState(() => _open = !_open),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          open ? 'Less' : 'More',
                          style: threadText(13, color: AppColors.blue),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Messages loaded at a time (and per "Show older messages").
const int threadPageSize = 50;

/// Keeps the newest message in view. The chat list is upside down
/// (see [ThreadChatList]), so 0 is the bottom:
///   older messages added on top – nothing moves
///   a new message               – slide down to it
class ThreadScrollKeeper {
  String? _newest;

  void update(ScrollController scroll, List<ThreadEntry> entries) {
    final newest = entries.isEmpty ? '' : entries.last.id;
    if (newest == _newest) return;
    final first = _newest == null;
    _newest = newest;
    if (first) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients || scroll.offset <= 0) return;
      scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    });
  }
}

/// The conversation, newest at the bottom (like WhatsApp). Inside it is
/// upside down (reverse), so when older messages are added on top the
/// messages on screen do not move: smooth, no jump. A short chat still
/// starts at the top.
class ThreadChatList extends StatelessWidget {
  const ThreadChatList({
    super.key,
    required this.controller,
    required this.children,
  });

  final ScrollController controller;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        return ListView(
          controller: controller,
          reverse: true,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: box.maxHeight > 32 ? box.maxHeight - 32 : 0.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// On top of the chat: "Show older messages", or a small loader while
/// they come. Same height for both, so nothing jumps.
class ThreadOlderBar extends StatelessWidget {
  const ThreadOlderBar({super.key, required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: loading
              ? const SizedBox(
                  key: ValueKey('loading'),
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.blue,
                  ),
                )
              : TextButton.icon(
                  key: const ValueKey('button'),
                  onPressed: onTap,
                  icon: const Icon(
                    Icons.history_rounded,
                    size: 16,
                    color: AppColors.blue,
                  ),
                  label: Text(
                    'Show older messages',
                    style: threadText(13, color: AppColors.blue),
                  ),
                ),
        ),
      ),
    );
  }
}

/// One line of the timeline.
class ThreadRow {
  const ThreadRow.message({
    required this.fromManagement,
    required this.text,
    this.at,
    this.pending = false,
    this.movedTo,
  }) : status = null;

  const ThreadRow.status({required String this.status, this.at})
    : fromManagement = true,
      text = '',
        pending = false,
        movedTo = null;

  final bool fromManagement;
  final String text;
  final String? status;
  final DateTime? at;
  final bool pending;

  /// Status changed together with this message ("Moved to …" on top).
  final String? movedTo;

  bool get isStatus => status != null;
}

/// Turns the saved conversation into timeline lines. A status change
/// with a message becomes two lines: "Moved to …", then the message.
/// Older entries (before conversations existed) only have one reply in
/// the entry itself: it is shown as the first management message.
/// [hasOlder]: older messages are not loaded yet, so the old single
/// reply is not shown (it may be in the older part).
List<ThreadRow> buildThreadRows(
  FeedbackItem item,
  List<ThreadEntry> entries, {
  bool hasOlder = false,
}) {
  final rows = <ThreadRow>[];
  final anyFromManagement = entries.any((e) => e.fromManagement);
  if (!hasOlder && !anyFromManagement && item.hasReply) {
    rows.add(
      ThreadRow.message(
        fromManagement: true,
        text: item.managementMessage,
        at: item.updatedAt,
      ),
    );
  }
  for (final e in entries) {
    final hasText = e.text.trim().isNotEmpty;
    if (e.status != null && !hasText) {
      rows.add(ThreadRow.status(status: e.status!, at: e.at));
    }
    if (hasText) {
      rows.add(
        ThreadRow.message(
          fromManagement: e.fromManagement,
          text: e.text,
          at: e.at,
          pending: e.pending,
          movedTo: e.status,
        ),
      );
    }
  }
  return rows;
}

/// No reply yet (employee screen, design A "Track"): what happens next,
/// as 4 steps. Done steps get a green tick, the current one is blue.
class ThreadNextSteps extends StatelessWidget {
  const ThreadNextSteps({super.key, required this.item});

  final FeedbackItem item;

  static const Color _green = Color(0xFF16A34A);

  @override
  Widget build(BuildContext context) {
    final s = item.status;
    final done = s == FeedbackStatus.implemented || s == FeedbackStatus.noted;
    final started =
        s == FeedbackStatus.underReview ||
        s == FeedbackStatus.planned ||
        s == FeedbackStatus.inProgress;
    // 0 = Sent, 1 = Admin reads it, 2 = Reply and status, 3 = Done.
    final current = done ? 4 : (started ? 2 : 1);
    final sentWhen = item.createdAt == null
        ? ''
        : '${threadDate(item.createdAt!)} · ';
    final steps = <List<String>>[
      [
        'Sent to admin',
        '$sentWhen${item.anonymous ? 'without your name' : 'with your name'}',
      ],
      ['Admin reads it', 'You’ll get a notification when they reply'],
      ['Reply and status update', 'Under review, Planned or In progress'],
      ['Done', 'Implemented or Noted'],
    ];

    Widget step(int i) {
      final isDone = i < current;
      final isNow = i == current;
      final last = i == steps.length - 1;
      final Widget dot;
      if (isDone) {
        dot = Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: _green,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
        );
      } else if (isNow) {
        dot = Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.blueTint,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.blue, width: 2),
          ),
          child: Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.blue,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      } else {
        dot = Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFD0D5DD), width: 2),
          ),
        );
      }
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 28,
              child: Column(
                children: [
                  dot,
                  if (!last)
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 2,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          color: isDone ? _green : threadLine,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 4, bottom: last ? 0 : 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      steps[i][0],
                      style: threadText(
                        15,
                        weight: isDone || isNow
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: isNow
                            ? AppColors.blue
                            : (isDone
                                  ? AppColors.ink
                                  : const Color(0xFF475467)),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      steps[i][1],
                      style: threadText(13, color: const Color(0xFF667085)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12, left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHAT HAPPENS NEXT',
            style: threadText(
              12,
              weight: FontWeight.w600,
              color: const Color(0xFF5F6A84),
            ).copyWith(letterSpacing: 0.9),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < steps.length; i++) step(i),
        ],
      ),
    );
  }
}

/// One block of the timeline: a day label, a status change, or messages
/// from one side in a row.
class _Block {
  _Block.day(this.day) : status = null, messages = null;
  _Block.status(this.status) : day = null, messages = null;
  _Block.messages(this.messages) : day = null, status = null;

  final String? day;
  final ThreadRow? status;
  final List<ThreadRow>? messages;
}

/// The conversation as a timeline (design A, "Track"):
///   messages: a small avatar, the name and time, then the text;
///   messages from the same side in a row share one header;
///   status changes: a coloured dot, "Moved to …";
///   a thin line joins them, top to bottom;
///   a day label ("Today", "Yesterday", "27 Oct") when the day changes.
/// "You" is the employee on the employee screen, and admin on the
/// management screen.
class FeedbackTimeline extends StatelessWidget {
  const FeedbackTimeline({
    super.key,
    required this.rows,
    required this.managementView,
    this.employeeName,
  });

  final List<ThreadRow> rows;

  /// True on the management screen: management messages are "mine".
  final bool managementView;

  /// First name of the employee (management view, name not hidden).
  final String? employeeName;

  static String _day(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return d.year == now.year
        ? '${d.day} ${_months[d.month - 1]}'
        : '${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final blocks = <_Block>[];
    String? lastDay;
    for (final row in rows) {
      final day = _day(row.at ?? DateTime.now());
      if (day != lastDay) {
        lastDay = day;
        blocks.add(_Block.day(day));
      }
      if (row.isStatus) {
        blocks.add(_Block.status(row));
        continue;
      }
      final prev = blocks.isEmpty ? null : blocks.last;
      final run = prev?.messages;
      if (run != null && run.first.fromManagement == row.fromManagement) {
        run.add(row);
      } else {
        blocks.add(_Block.messages([row]));
      }
    }

    final children = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      // The line goes on while anything but a day label follows.
      final line = blocks.skip(i + 1).any((x) => x.day == null);
      if (b.day != null) {
        children.add(_DayLabel(b.day!));
      } else if (b.status != null) {
        children.add(_StatusStep(row: b.status!, line: line));
      } else {
        final msgs = b.messages!;
        final fromAdmin = msgs.first.fromManagement;
        final mine = fromAdmin == managementView;
        children.add(
          _MessageGroup(
            rows: msgs,
            line: line,
            fromAdmin: fromAdmin,
            name: mine
                ? 'You'
                : (fromAdmin ? 'Admin' : (employeeName ?? 'Employee')),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// "9:21 PM", or "Sending…" while it is on its way.
String _time(ThreadRow row) {
  if (row.pending) return 'Sending…';
  final d = row.at;
  if (d == null) return '';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

class _DayLabel extends StatelessWidget {
  const _DayLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 14),
      child: Center(
        child: Text(text, style: threadText(12, color: threadSoft)),
      ),
    );
  }
}

/// The thin line under an avatar or dot, down to the next block.
Widget _timelineLine() => Expanded(
  child: Center(
    child: Container(
      width: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: threadLine,
    ),
  ),
);

/// "Moved to Under review · 10:20 PM" with a coloured dot.
class _StatusStep extends StatelessWidget {
  const _StatusStep({required this.row, required this.line});

  final ThreadRow row;
  final bool line;

  @override
  Widget build(BuildContext context) {
    final color = FeedbackStatus.color(row.status!);
    final time = _time(row);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                const SizedBox(height: 2),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(alpha: 0.25),
                      width: 3,
                    ),
                  ),
                ),
                if (line) _timelineLine(),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: line ? 18 : 4),
              child: Text.rich(
                TextSpan(
                  text: 'Moved to ',
                  children: [
                    TextSpan(
                      text: FeedbackStatus.label(row.status!),
                      style: threadText(
                        13,
                        weight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    if (time.isNotEmpty) TextSpan(text: ' · $time'),
                  ],
                ),
                style: threadText(13, color: const Color(0xFF475467)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Messages from one side in a row: avatar, name and time, the texts.
class _MessageGroup extends StatelessWidget {
  const _MessageGroup({
    required this.rows,
    required this.line,
    required this.fromAdmin,
    required this.name,
  });

  final List<ThreadRow> rows;
  final bool line;
  final bool fromAdmin;
  final String name;

  @override
  Widget build(BuildContext context) {
    final first = rows.first;
    final headTime = first.pending ? '' : _time(first);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: fromAdmin ? AppColors.blue : const Color(0xFFF2F4F7),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    fromAdmin
                        ? Icons.shield_outlined
                        : Icons.person_outline_rounded,
                    size: 16,
                    color: fromAdmin ? Colors.white : const Color(0xFF475467),
                  ),
                ),
                if (line) _timelineLine(),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 5, bottom: line ? 18 : 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        name,
                        style: threadText(
                          14,
                          weight: FontWeight.w600,
                          color: fromAdmin ? AppColors.blue : AppColors.ink,
                        ),
                      ),
                      if (headTime.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          headTime,
                          style: threadText(12, color: threadSoft),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (final r in rows) ...[
                    if (r.movedTo != null) _MovedTag(status: r.movedTo!),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text.rich(
                        TextSpan(
                          text: r.text.trim(),
                          children: [
                            if (r.pending)
                              TextSpan(
                                text: '  Sending…',
                                style: threadText(11, color: threadSoft),
                              ),
                          ],
                        ),
                        style: threadText(
                          15,
                          height: 1.5,
                          color: r.pending
                              ? threadSoft
                              : const Color(0xFF344054),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reply box at the bottom: grey rounded field and a blue send button.
class ThreadComposer extends StatelessWidget {
  const ThreadComposer({
    super.key,
    required this.controller,
    required this.hint,
    required this.onSend,
    this.footnote,
    this.leading,
  });

  final TextEditingController controller;
  final String hint;
  final VoidCallback onSend;
  final String? footnote;

  /// Optional button before the field (management: change status).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final canSend = controller.text.trim().isNotEmpty;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEF1F6))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 10)],
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      inputFormatters: [LengthLimitingTextInputFormatter(1000)],
                      style: threadText(15, height: 1.4),
                      decoration: InputDecoration(
                        hintText: hint,
                        hintStyle: threadText(
                          15,
                          color: const Color(0xFF9AA3B8),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF6F8FB),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        // Light border, light blue when typing (not the
                        // app's dark default).
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: const BorderSide(
                            color: Color(0xFFE9EDF4),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(
                            color: AppColors.blue.withValues(alpha: 0.5),
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: canSend ? AppColors.blue : const Color(0xFFE3E8F1),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: canSend ? onSend : null,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(
                          Icons.send_rounded,
                          size: 19,
                          color: canSend ? Colors.white : threadSoft,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (footnote != null) ...[
                const SizedBox(height: 6),
                Text(footnote!, style: threadText(11.5, color: threadSoft)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small coloured status tag with a dot.
class ThreadStatusPill extends StatelessWidget {
  const ThreadStatusPill({super.key, required this.status});

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
            style: threadText(11.5, weight: FontWeight.w500, color: color),
          ),
        ],
      ),
    );
  }
}

/// Screen name on the right of the AppBar (same as the other screens).
class ThreadTitlePill extends StatelessWidget {
  const ThreadTitlePill(this.text, {super.key, required this.icon});

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
            Text(text, style: threadText(16)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// V1 "Clean card": collapsing header (employee + management)
// ---------------------------------------------------------------------

const Color _v1Ink = Color(0xFF111827);
const Color _v1Soft = Color(0xFF6B7280);
const Color _v1Faint = Color(0xFF9CA3AF);

/// Step 1–5 of a status (Noted and Implemented are the last step).
int threadStep(String s) {
  if (s == FeedbackStatus.underReview) return 2;
  if (s == FeedbackStatus.planned) return 3;
  if (s == FeedbackStatus.inProgress) return 4;
  if (s == FeedbackStatus.implemented || s == FeedbackStatus.noted) return 5;
  return 1;
}

/// Top bar (back · type · broadcast) and one card: who + date and the
/// status, the message, a 5-part progress bar. Slim while scrolling or
/// typing; tap it to open again.
class ThreadQuoteHeader extends StatelessWidget {
  const ThreadQuoteHeader({
    super.key,
    required this.item,
    required this.collapsed,
    required this.onExpand,
    this.management = false,
    this.actionIcon,
    this.actionTooltip,
    this.onAction,
  });

  final FeedbackItem item;
  final bool collapsed;
  final VoidCallback onExpand;

  /// Management sees the sender; the employee sees "You".
  final bool management;

  /// Optional round button on the right (admin: broadcast).
  final IconData? actionIcon;
  final String? actionTooltip;
  final VoidCallback? onAction;

  String get _meta {
    final rating = item.rating;
    final String who;
    if (management) {
      final name = (item.authorName ?? '').trim();
      final id = (item.authorEmployeeId ?? '').trim();
      who = item.anonymous || name.isEmpty
          ? 'Name hidden'
          : [name, if (id.isNotEmpty) id].join(' · ');
    } else {
      who = item.anonymous ? 'You · name hidden' : 'You';
    }
    return [
      who,
      if (item.createdAt != null) threadDate(item.createdAt!),
      if (!item.isFromBox && rating != null) PulseRating.label(rating),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    void back() => Navigator.of(context).maybePop();
    final type = item.isFromBox ? 'Suggestion' : 'Weekly Pulse';
    final color = FeedbackStatus.color(item.status);
    final step = threadStep(item.status);
    final action = onAction == null
        ? null
        : _W3Button(
            icon: actionIcon ?? Icons.more_horiz,
            tooltip: actionTooltip ?? '',
            onTap: onAction!,
            color: AppColors.blue,
            size: 42,
          );
    final tile = Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: item.isFromBox
            ? const Color(0xFFFEF3C7)
            : const Color(0xFFEAF0FF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        item.isFromBox ? Icons.lightbulb_outline : Icons.monitor_heart_outlined,
        size: 14,
        color: item.isFromBox ? const Color(0xFFB7791F) : AppColors.blue,
      ),
    );
    final bar = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          _W3Button(
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: 'Back',
            onTap: back,
            size: 42,
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                tile,
                const SizedBox(width: 8),
                Text(
                  type,
                  style: threadText(16, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
          action ?? const SizedBox(width: 42),
        ],
      ),
    );
    final card = Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FB),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                item.anonymous
                    ? Icons.lock_outline_rounded
                    : Icons.person_outline_rounded,
                size: 13,
                color: _v1Faint,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: threadText(
                    12.5,
                    weight: FontWeight.w500,
                    color: _v1Soft,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      FeedbackStatus.label(item.status),
                      style: threadText(
                        12,
                        weight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _V1Text(text: item.text),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < 5; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i < step ? color : const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Step $step of 5',
            style: threadText(11.5, color: _v1Faint),
          ),
        ],
      ),
    );
    final slim = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        children: [
          _W3Button(
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: 'Back',
            onTap: back,
            size: 40,
            iconSize: 16,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onExpand,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.text.trim().replaceAll(RegExp(r'\s+'), ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: threadText(15, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '${FeedbackStatus.label(item.status)} · tap to read',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: threadText(12, color: _v1Faint),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (onAction != null) ...[
            const SizedBox(width: 10),
            _W3Button(
              icon: actionIcon ?? Icons.more_horiz,
              tooltip: actionTooltip ?? '',
              onTap: onAction!,
              color: AppColors.blue,
              size: 40,
              iconSize: 18,
            ),
          ],
        ],
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Container(
        padding: EdgeInsets.only(top: top),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFF0F1F4))),
        ),
        child: AnimatedCrossFade(
          duration: const Duration(milliseconds: 240),
          sizeCurve: Curves.easeOutCubic,
          firstCurve: Curves.easeOut,
          secondCurve: Curves.easeOut,
          crossFadeState:
              collapsed ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [bar, card],
          ),
          secondChild: slim,
        ),
      ),
    );
  }
}

/// The message: 5 lines, then "More" / "Less".
class _V1Text extends StatefulWidget {
  const _V1Text({required this.text});

  final String text;

  @override
  State<_V1Text> createState() => _V1TextState();
}

class _V1TextState extends State<_V1Text> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final text = widget.text.trim();
    final style = threadText(
      18,
      weight: FontWeight.w500,
      color: _v1Ink,
      height: 1.5,
    ).copyWith(letterSpacing: -0.15);
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 5,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: box.maxWidth);
        final long = painter.didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_open)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.35,
                ),
                child: SingleChildScrollView(
                  child: SelectableText(text, style: style),
                ),
              )
            else
              Text(
                text,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            if (long)
              GestureDetector(
                onTap: () => setState(() => _open = !_open),
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _open ? 'Less' : 'More',
                    style: threadText(
                      13,
                      weight: FontWeight.w600,
                      color: AppColors.blue,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Employee, no reply yet: a calm note in the middle.
class _NoRepliesYet extends StatelessWidget {
  const _NoRepliesYet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0xFFEEF2FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 26,
              color: AppColors.blue,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No replies yet',
            style: threadText(17, weight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Admin will reply here. You will get a notification.',
            textAlign: TextAlign.center,
            style: threadText(14, color: _v1Soft, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// "Moved to Noted" on top of the message sent with that change.
class _MovedTag extends StatelessWidget {
  const _MovedTag({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = FeedbackStatus.color(status);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text.rich(
          TextSpan(
            text: 'Moved to ',
            children: [
              TextSpan(
                text: FeedbackStatus.label(status),
                style: threadText(12, weight: FontWeight.w700, color: color),
              ),
            ],
          ),
          style: threadText(12, color: const Color(0xFF475467)),
        ),
      ),
    );
  }
}

/// Round white button with a thin border.
class _W3Button extends StatelessWidget {
  const _W3Button({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color = const Color(0xFF101828),
    this.size = 44,
    this.iconSize = 17,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(
          side: BorderSide(color: Color(0xFFE3E8F1)),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: iconSize, color: color),
          ),
        ),
      ),
    );
  }
}
