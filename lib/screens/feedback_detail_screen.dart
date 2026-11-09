import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../demo_data.dart';
import '../models/feedback_item.dart';
import '../models/pulse_rating.dart';
import '../services/broadcast_service.dart';
import '../services/feedback_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'broadcast_screens.dart';
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
}) => GoogleFonts.inter(
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

  /// Sample items are not in Firestore, so they update from DemoData.
  StreamSubscription<void>? _demoSub;
  late Stream<List<ThreadEntry>> _thread;
  int _limit = threadPageSize;
  final _keeper = ThreadScrollKeeper();
  bool _loadingOlder = false;
  int _shown = 0;
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
    _thread = FeedbackService.instance.watchThread(
      widget.item.id,
      limit: _limit,
    );
    _itemSub = FeedbackService.instance.watchOne(widget.item.id).listen((i) {
      if (i != null && mounted) setState(() => _item = i);
    });
    if (widget.item.id.startsWith(DemoData.idPrefix)) {
      _demoSub = DemoData.changes.listen((_) {
        final latest = DemoData.all()
            .where((i) => i.id == widget.item.id)
            .firstOrNull;
        if (latest != null && mounted) setState(() => _item = latest);
      });
    }
  }

  @override
  void dispose() {
    _itemSub?.cancel();
    _demoSub?.cancel();
    _reply.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// "Show older messages": load 50 more, with a small loader on top.
  void _showOlder() {
    if (_loadingOlder) return;
    setState(() {
      _loadingOlder = true;
      _limit += threadPageSize;
      _thread = FeedbackService.instance.watchThread(
        widget.item.id,
        limit: _limit,
      );
    });
    // Safety: never spin for ever (for example, no older ones after all).
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (mounted && _loadingOlder) setState(() => _loadingOlder = false);
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

    final changed = await showModalBottomSheet<(String, String)>(
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
    if (changed == null || !mounted) return;
    final (status, message) = changed;
    // No snackbar: the status pill on the card already shows the change.
    // Implemented: nothing is saved yet. The dialog asks who gets the
    // message, and saves + sends only when admin taps Send.
    if (status == FeedbackStatus.implemented) {
      // Let the sheet finish sliding down, then open the dialog gently.
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted) return;
      await _askShare(message);
    }
  }

  /// Implemented: who gets the message? Only the employee, or the employee
  /// and everyone (a broadcast, no name). Saves and sends only on Send.
  /// The X closes without changing anything; tapping outside does nothing.
  Future<void> _askShare(String message) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Mark as Implemented',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) =>
          _withInter(context, _ShareDialog(item: _item, message: message)),
      transitionBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  String _date(DateTime? d) {
    if (d == null) return '';
    const months = [
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
            // Share an update about this with everyone (no name).
            IconButton(
              tooltip: 'Broadcast to everyone',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NewBroadcastScreen(quote: _item.text),
                ),
              ),
              icon: const Icon(Icons.campaign_outlined, color: AppColors.blue),
            ),
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
                  if (snap.hasData) _keeper.update(_scroll, entries);
                  // Older ones arrived: hide the loader.
                  if (_loadingOlder && entries.length > _shown) {
                    _loadingOlder = false;
                  }
                  if (!_loadingOlder) _shown = entries.length;
                  final hasOlder = entries.length >= _limit;
                  final showBar = hasOlder || _loadingOlder;
                  final rows = buildThreadRows(
                    _item,
                    entries,
                    hasOlder: showBar,
                  );
                  if (rows.isEmpty) {
                    // Still loading: show nothing, so it does not flash.
                    if (!snap.hasData) return const SizedBox.expand();
                    return _NoReplies(scroll: _scroll);
                  }
                  return ThreadChatList(
                    controller: _scroll,
                    children: [
                      if (showBar)
                        ThreadOlderBar(
                          loading: _loadingOlder,
                          onTap: _showOlder,
                        ),
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

/// "Mark as Implemented" dialog: who gets the message?
///   Only the employee: status + message to the employee.
///   Employee + everyone: the same, plus a broadcast (Title = the
///   suggestion, Message = admin's message, never the sender's name).
/// Nothing is saved until Send. The X closes without changing anything;
/// tapping outside does nothing.
class _ShareDialog extends StatefulWidget {
  const _ShareDialog({required this.item, required this.message});

  final FeedbackItem item;

  /// What admin wrote in the status sheet.
  final String message;

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  static const _line = Color(0xFFE3E8F1);
  static const _soft = Color(0xFF8E97AB);
  static const _muted = Color(0xFF5F6A84);
  static const _green = Color(0xFF16A34A);
  static const _titleMax = 120;

  bool _everyone = false;
  late final _title = TextEditingController(
    text: _shortTitle(widget.item.text),
  );
  late final _body = TextEditingController(text: widget.message);
  bool _busy = false;
  String? _error;

  /// Status + message already saved (only the broadcast failed): Send then
  /// only retries the broadcast.
  bool _statusSaved = false;

  /// The suggestion as the title (cut to fit, if very long).
  static String _shortTitle(String text) {
    final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return t.length <= _titleMax
        ? t
        : '${t.substring(0, _titleMax - 1).trimRight()}…';
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  TextStyle _s(
    double size, {
    FontWeight w = FontWeight.w400,
    Color c = AppColors.ink,
    double? h,
  }) => GoogleFonts.inter(fontSize: size, fontWeight: w, color: c, height: h);

  void _choose(bool everyone) {
    if (_busy || _statusSaved || everyone == _everyone) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _everyone = everyone;
      _error = null;
    });
  }

  Future<void> _send() async {
    final body = _body.text.trim();
    final title = _title.text.trim();
    if (body.isEmpty) {
      setState(() => _error = 'Write a message');
      return;
    }
    if (_everyone && title.isEmpty) {
      setState(() => _error = 'Write a short title');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);

    // 1) Status + message to the employee.
    if (!_statusSaved) {
      try {
        await FeedbackService.instance.updateStatus(
          id: widget.item.id,
          status: FeedbackStatus.implemented,
          message: body,
        );
        _statusSaved = true;
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = 'Could not send. Please check your internet and try again.';
        });
        return;
      }
    }

    // 2) Everyone: the broadcast.
    if (_everyone) {
      try {
        await BroadcastService.instance.send(title: title, body: body);
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error =
              'Sent to the employee, but could not share with everyone. '
              'Tap Send to try again.';
        });
        return;
      }
    }
    nav.pop();
  }

  // Same look as the fields on the New broadcast screen.
  OutlineInputBorder _border(Color c) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: c, width: 1.5),
  );

  InputDecoration _deco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: _s(15, c: const Color(0xFF9AA3B8)),
    contentPadding: const EdgeInsets.all(14),
    border: _border(_line),
    enabledBorder: _border(_line),
    focusedBorder: _border(AppColors.blue),
    counterText: '',
  );

  Widget _label(String s) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 6),
    child: Text(s, style: _s(13, c: _muted)),
  );

  /// Only the employee | Employee + everyone, with a sliding highlight.
  Widget _switch() {
    Widget label(String text, bool on, bool everyone) => Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _choose(everyone),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            style: _s(
              13.5,
              w: on ? FontWeight.w600 : FontWeight.w400,
              c: on ? AppColors.blue : _muted,
            ),
            child: Text(text, maxLines: 1),
          ),
        ),
      ),
    );
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: _everyone ? Alignment.centerRight : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x2E0E1A3A),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                      spreadRadius: -2,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              label('👤 Only the employee', !_everyone, false),
              label('📣 Employee + everyone', _everyone, true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _messageField() => TextField(
    controller: _body,
    enabled: !_busy && !_statusSaved,
    minLines: 3,
    maxLines: 6,
    maxLength: 1000,
    textCapitalization: TextCapitalization.sentences,
    scrollPadding: const EdgeInsets.only(bottom: 160),
    style: _s(15, h: 1.45),
    decoration: _deco('What has been done?'),
  );

  Widget _onlyEmployee() => Column(
    key: const ValueKey('employee'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _label('Message to the employee'),
      _messageField(),
      const SizedBox(height: 8),
      Text(
        'Only the employee who sent it will see this.',
        style: _s(12.5, c: _soft),
      ),
    ],
  );

  Widget _withEveryone() => Column(
    key: const ValueKey('everyone'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _label('Title (the suggestion, name not shared)'),
      TextField(
        controller: _title,
        enabled: !_busy,
        minLines: 1,
        maxLines: 3,
        maxLength: _titleMax,
        textCapitalization: TextCapitalization.sentences,
        scrollPadding: const EdgeInsets.only(bottom: 160),
        style: _s(15, h: 1.4),
        decoration: _deco('For example: Air dryer added on 5th floor'),
      ),
      const SizedBox(height: 14),
      _label('Message'),
      _messageField(),
      const SizedBox(height: 8),
      Text(
        'The employee gets this message. Everyone else sees it as a '
        'broadcast, without the sender’s name.',
        style: _s(12.5, c: _soft, h: 1.4),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    // Dialog moves itself above the keyboard; the content scrolls, so the
    // fields and the button stay visible while typing.
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      insetPadding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Close: nothing changes, nothing is sent.
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: _soft),
                ),
              ),
              Center(
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE7F6EC),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: _green,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Mark as Implemented',
                textAlign: TextAlign.center,
                style: _s(19.5, w: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Who should get your message?',
                textAlign: TextAlign.center,
                style: _s(14, c: _muted),
              ),
              const SizedBox(height: 16),
              _switch(),
              const SizedBox(height: 16),
              // Smooth change between the two: fade + resize.
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topCenter,
                    children: [...previous, if (current != null) current],
                  ),
                  child: _everyone ? _withEveryone() : _onlyEmployee(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: _s(
                    13.5,
                    c: Theme.of(context).colorScheme.error,
                    h: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy ? null : _send,
                icon: _busy
                    ? const SizedBox.shrink()
                    : const Icon(Icons.send_rounded, size: 18),
                label: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Text(
                          _everyone
                              ? 'Send to employee + everyone'
                              : 'Send to employee',
                          key: ValueKey(_everyone),
                        ),
                      ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  minimumSize: const Size.fromHeight(52),
                  shape: const StadiumBorder(),
                  textStyle: _s(15.5, w: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// No replies yet: a small message in the middle of the empty space.
/// It scrolls when the keyboard leaves little room.
class _NoReplies extends StatelessWidget {
  const _NoReplies({required this.scroll});

  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        return SingleChildScrollView(
          controller: scroll,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 16, 32, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        color: AppColors.blueTint,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 24,
                        color: AppColors.blue,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('No replies yet', style: _t(16)),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        text: 'Write a reply below, or tap ',
                        children: const [
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Icon(
                              Icons.tune_rounded,
                              size: 16,
                              color: AppColors.blue,
                            ),
                          ),
                          TextSpan(text: ' to change the status.'),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: _t(
                        13.5,
                        weight: FontWeight.w400,
                        color: AppColors.muted,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
  final _focus = FocusNode();
  final _scroll = ScrollController();
  String? _chosen;
  bool _busy = false;
  String? _error;

  bool get _implemented => _chosen == FeedbackStatus.implemented;

  @override
  void initState() {
    super.initState();
    // Typing: move the sheet up so the box and the button stay visible.
    _focus.addListener(() {
      if (_focus.hasFocus) _showButton();
    });
  }

  @override
  void dispose() {
    _message.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls to the bottom once the keyboard has opened.
  void _showButton() {
    Future<void>.delayed(const Duration(milliseconds: 320), () {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _save() async {
    final status = _chosen;
    if (status == null) return;
    final text = _message.text.trim();
    if (_implemented && text.isEmpty) {
      setState(() => _error = 'A message is needed for Implemented.');
      return;
    }
    final navigator = Navigator.of(context);
    if (_implemented) {
      // Implemented is saved by the next dialog (after choosing who gets it).
      FocusScope.of(context).unfocus();
      await Future<void>.delayed(const Duration(milliseconds: 220));
      navigator.pop((status, text));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FeedbackService.instance.updateStatus(
        id: widget.item.id,
        status: status,
        message: text,
      );
      // Close the keyboard first, then slide the sheet down (smooth).
      if (mounted) FocusScope.of(context).unfocus();
      await Future<void>.delayed(const Duration(milliseconds: 220));
      navigator.pop((status, text));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'Could not update. Please check your internet '
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
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Change status',
                      style: _t(17, weight: FontWeight.w400),
                    ),
                  ),
                  Text(
                    'Now: ',
                    style: _t(
                      12.5,
                      weight: FontWeight.w400,
                      color: const Color(0xFF8E97AB),
                    ),
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
                focusNode: _focus,
                onChanged: (_) => _showButton(),
                scrollPadding: const EdgeInsets.only(bottom: 120),
                minLines: 2,
                maxLines: 5,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                style: _t(15, weight: FontWeight.w400, height: 1.4),
                decoration: InputDecoration(
                  hintText: _implemented
                      ? 'Tell ${widget.employeeName ?? 'them'} what has been done (needed)'
                      : 'Add a message (optional)',
                  hintStyle: _t(
                    14.5,
                    weight: FontWeight.w400,
                    color: const Color(0xFF9AA3B8),
                  ),
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
                  style: _t(
                    13.5,
                    weight: FontWeight.w400,
                    color: theme.colorScheme.error,
                  ),
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
                            : _implemented
                            ? 'Next'
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
      // Joined with an entry code: the name was typed, not checked.
      if (!anonymous && id.isEmpty) 'Name typed by sender',
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
          Text(FeedbackStatus.label(status), style: _t(11.5, color: color)),
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
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
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
