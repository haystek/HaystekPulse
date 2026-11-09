import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/feedback_item.dart';
import '../models/pulse_rating.dart';
import '../services/feedback_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

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

  @override
  void initState() {
    super.initState();
    _itemStream = FeedbackService.instance.watchOne(widget.item.id);
    _threadStream = FeedbackService.instance.watchThread(
      widget.item.id,
      limit: _limit,
    );
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
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
      data: t.copyWith(textTheme: GoogleFonts.interTextTheme(t.textTheme)),
      child: StreamBuilder<FeedbackItem?>(
        stream: _itemStream,
        builder: (context, itemSnap) {
          // Live copy (status changes), or the one we were given.
          final item = itemSnap.data ?? widget.item;
          // Keyboard opening: keep the newest message in view.
          _lastInset = keepLastInView(context, _scroll, _lastInset);
          return Scaffold(
            backgroundColor: Colors.white,
            resizeToAvoidBottomInset: true,
            appBar: AppBar(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              leadingWidth: 68,
              leading: const AppBackButton(),
              title: const SizedBox.shrink(),
              actions: [
                ThreadTitlePill(
                  item.isFromBox ? 'Suggestion' : 'Weekly Pulse',
                  icon: item.isFromBox
                      ? Icons.lightbulb_outline
                      : Icons.monitor_heart_outlined,
                ),
              ],
            ),
            body: Column(
              children: [
                // Sticky: the original message stays on top.
                _MyMessageCard(item: item),
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
                            Text(
                              'No reply yet. You’ll get a notification when '
                              'admin replies. You can add more here '
                              'any time.',
                              style: threadText(
                                13.5,
                                color: AppColors.muted,
                                height: 1.45,
                              ),
                            )
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

/// The employee's own message, sticky on top.
class _MyMessageCard extends StatelessWidget {
  const _MyMessageCard({required this.item});

  final FeedbackItem item;

  @override
  Widget build(BuildContext context) {
    final rating = item.rating;
    final meta = [
      'You',
      if (item.createdAt != null) threadDate(item.createdAt!),
      if (!item.isFromBox && rating != null) PulseRating.label(rating),
    ].join(' · ');
    return ThreadHeaderCard(
      text: item.text,
      top: Row(
        children: [
          ThreadStatusPill(status: item.status),
          const Spacer(),
          Icon(
            item.anonymous ? Icons.lock_outline : Icons.person_outline,
            size: 13,
            color: threadSoft,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: threadText(12, color: threadSoft),
            ),
          ),
        ],
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
}) => GoogleFonts.inter(
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
  const ThreadHeaderCard({super.key, required this.top, required this.text});

  /// Name / date / status row.
  final Widget top;
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
                widget.top,
                const SizedBox(height: 8),
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
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: box.maxHeight > 20 ? box.maxHeight - 20 : 0.0,
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
  }) : status = null;

  const ThreadRow.status({required String this.status, this.at})
    : fromManagement = true,
      text = '',
      pending = false;

  final bool fromManagement;
  final String text;
  final String? status;
  final DateTime? at;
  final bool pending;

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
    if (e.status != null) {
      rows.add(ThreadRow.status(status: e.status!, at: e.at));
    }
    if (e.text.trim().isNotEmpty) {
      rows.add(
        ThreadRow.message(
          fromManagement: e.fromManagement,
          text: e.text,
          at: e.at,
          pending: e.pending,
        ),
      );
    }
  }
  return rows;
}

/// The conversation as chat bubbles, like WhatsApp:
///   my messages      – blue, on the right
///   their messages   – light grey, on the left, with the name
///   status changes   – a small grey note in the middle
///   a day label ("Today", "Yesterday", "27 Oct") when the day changes
/// "Mine" is the employee on the employee screen, and management on the
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
    final children = <Widget>[];
    String? lastDay;
    for (final row in rows) {
      final day = _day(row.at ?? DateTime.now());
      if (day != lastDay) {
        lastDay = day;
        children.add(_DayLabel(day));
      }
      if (row.isStatus) {
        children.add(_StatusNote(row: row));
      } else {
        final mine = row.fromManagement == managementView;
        children.add(
          _Bubble(
            row: row,
            mine: mine,
            name: mine
                ? null
                : (row.fromManagement ? 'Admin' : (employeeName ?? 'Employee')),
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
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Text(text, style: threadText(11.5, color: threadSoft)),
      ),
    );
  }
}

/// "Status changed to Noted · 9:21 PM" in the middle.
class _StatusNote extends StatelessWidget {
  const _StatusNote({required this.row});

  final ThreadRow row;

  @override
  Widget build(BuildContext context) {
    final color = FeedbackStatus.color(row.status!);
    final time = _time(row);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F4F8),
            borderRadius: BorderRadius.circular(12),
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
              Flexible(
                child: Text(
                  'Status changed to ${FeedbackStatus.label(row.status!)}'
                  '${time.isEmpty ? '' : ' · $time'}',
                  style: threadText(12, color: const Color(0xFF5F6A84)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One message bubble.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.row, required this.mine, this.name});

  final ThreadRow row;
  final bool mine;

  /// Shown on top of the other side's bubbles.
  final String? name;

  @override
  Widget build(BuildContext context) {
    final time = _time(row);
    final maxWidth = MediaQuery.sizeOf(context).width * 0.75;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Container(
            padding: const EdgeInsets.fromLTRB(13, 9, 13, 7),
            decoration: BoxDecoration(
              color: mine
                  ? (row.pending ? const Color(0xFF7D9BEA) : AppColors.blue)
                  : const Color(0xFFF2F4F8),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(mine ? 18 : 4),
                bottomRight: Radius.circular(mine ? 4 : 18),
              ),
            ),
            child: Column(
              crossAxisAlignment: mine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (name != null) ...[
                  Text(
                    name!,
                    style: threadText(
                      12,
                      weight: FontWeight.w500,
                      color: name == 'Admin'
                          ? AppColors.blue
                          : const Color(0xFF475467),
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  row.text.trim(),
                  style: threadText(
                    14.5,
                    height: 1.4,
                    color: mine ? Colors.white : AppColors.ink,
                  ),
                ),
                if (time.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    time,
                    style: threadText(
                      10.5,
                      color: mine ? const Color(0xFFC9D6FF) : threadSoft,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
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
