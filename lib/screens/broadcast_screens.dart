import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/employee.dart';
import '../services/broadcast_service.dart';
import '../services/typed_name.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'typed_name_field.dart';
import 'feedback_thread_screen.dart'
    show ThreadComposer, ThreadTitlePill, keepLastInView, threadDate, threadSoft, threadText;

const Color _line = Color(0xFFE3E8F1);

/// "Today, 10:15 AM", "Yesterday, 4:12 PM" or "26 Oct".
String _when(DateTime? d) {
  if (d == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final time = '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today, $time';
  if (diff == 1) return 'Yesterday, $time';
  return threadDate(d).split(',').first;
}

Widget _withInter(BuildContext context, Widget child) {
  final t = Theme.of(context);
  return Theme(
    data: t.copyWith(textTheme: GoogleFonts.interTextTheme(t.textTheme)),
    child: child,
  );
}

// ---------------------------------------------------------------------
// List
// ---------------------------------------------------------------------

/// Employees: the Broadcast tab as its own screen. Opening it marks
/// every broadcast as read (the "new" count on home goes away).
class BroadcastListScreen extends StatefulWidget {
  const BroadcastListScreen({super.key, required this.employee});

  final Employee employee;

  @override
  State<BroadcastListScreen> createState() => _BroadcastListScreenState();
}

class _BroadcastListScreenState extends State<BroadcastListScreen> {
  Employee get employee => widget.employee;

  @override
  void initState() {
    super.initState();
    BroadcastService.instance.markSeen(widget.employee.uid);
  }

  @override
  Widget build(BuildContext context) {
    return _withInter(
      context,
      Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          leadingWidth: 68,
          leading: const AppBackButton(),
          title: const SizedBox.shrink(),
          actions: const [
            ThreadTitlePill('Broadcast', icon: Icons.campaign_outlined),
          ],
        ),
        body: BroadcastList(employee: employee),
      ),
    );
  }
}

/// The list of broadcasts, newest first. Admins also get "New broadcast"
/// at the top. Used on its own screen (employees) and as a tab (admin).
class BroadcastList extends StatefulWidget {
  const BroadcastList({super.key, required this.employee});

  final Employee employee;

  @override
  State<BroadcastList> createState() => _BroadcastListState();
}

class _BroadcastListState extends State<BroadcastList> {
  late final Stream<List<Broadcast>> _stream =
      BroadcastService.instance.watchAll();

  void _open(Broadcast b) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BroadcastDetailScreen(
          employee: widget.employee,
          broadcastId: b.id,
          initial: b,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final admin = widget.employee.isManagement;
    return StreamBuilder<List<Broadcast>>(
      stream: _stream,
      builder: (context, snap) {
        final items = snap.data ?? const <Broadcast>[];
        final children = <Widget>[
          if (admin) ...[
            // Admin tab: title, and a soft "Share an update…" box that
            // opens New broadcast.
            Text('Broadcast', style: threadText(24, weight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('Updates you sent to everyone',
                style: threadText(13.5, color: threadSoft)),
            const SizedBox(height: 14),
            const _ShareBox(),
            const SizedBox(height: 14),
          ],
        ];
        if (snap.hasError) {
          children.add(_note('Could not load. Please check your internet.'));
        } else if (!snap.hasData) {
          children.add(
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.blue,
                  ),
                ),
              ),
            ),
          );
        } else if (items.isEmpty) {
          children.add(
            _note(
              admin
                  ? 'Nothing sent yet. Share an update with everyone, for '
                      'example what changed after a suggestion.'
                  : 'No broadcasts yet. Updates from admin will show here.',
            ),
          );
        } else {
          for (final b in items) {
            children
              ..add(_Card(b: b, onTap: () => _open(b)))
              ..add(const SizedBox(height: 10));
          }
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: children,
        );
      },
    );
  }

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.only(top: 50),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: threadText(14.5, color: threadSoft, height: 1.45),
        ),
      );
}

/// Admin: "Share an update with everyone…", like a post box. Tap to write.
class _ShareBox extends StatelessWidget {
  const _ShareBox();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF6F8FB),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const NewBroadcastScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: AppColors.blue,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.campaign_outlined,
                    size: 19, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Share an update with everyone…',
                  style: threadText(14.5, color: threadSoft),
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: _line),
                ),
                child: const Icon(Icons.edit_outlined,
                    size: 16, color: AppColors.blue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.b, required this.onTap});

  final Broadcast b;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = b.commentCount;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: _line, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Admin',
                      style: threadText(12, color: AppColors.blue),
                    ),
                    TextSpan(text: '  ·  ${_when(b.createdAt)}'),
                  ],
                ),
                style: threadText(12, color: threadSoft),
              ),
              const SizedBox(height: 6),
              Text(b.title, style: threadText(15.5, weight: FontWeight.w500)),
              if (b.quote != null) ...[
                const SizedBox(height: 6),
                _Quote(text: b.quote!, maxLines: 2),
              ],
              if (b.body.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  b.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: threadText(14, color: const Color(0xFF344054), height: 1.4),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                count == 0
                    ? 'Be the first to comment'
                    : count == 1
                        ? '💬 1 comment'
                        : '💬 $count comments',
                style: threadText(12.5, color: threadSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The suggestion a broadcast answers, in quotes with a grey bar.
class _Quote extends StatelessWidget {
  const _Quote({required this.text, this.maxLines});

  final String text;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 2, 0, 2),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Color(0xFFDDE3EE), width: 3)),
      ),
      child: Text(
        '“${text.trim()}”',
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
        style: threadText(13, color: const Color(0xFF5F6A84), height: 1.4),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// One broadcast + discussion
// ---------------------------------------------------------------------

class BroadcastDetailScreen extends StatefulWidget {
  const BroadcastDetailScreen({
    super.key,
    required this.employee,
    required this.broadcastId,
    this.initial,
  });

  final Employee employee;
  final String broadcastId;
  final Broadcast? initial;

  @override
  State<BroadcastDetailScreen> createState() => _BroadcastDetailScreenState();
}

class _BroadcastDetailScreenState extends State<BroadcastDetailScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  late final Stream<Broadcast?> _item =
      BroadcastService.instance.watchOne(widget.broadcastId);
  late final Stream<List<BroadcastComment>> _comments =
      BroadcastService.instance.watchComments(widget.broadcastId);

  /// Employees: hide the name by default.
  bool _showName = false;

  /// No name in the app (joined with an entry code): they type one.
  late final bool _needsName = TypedName.needed(widget.employee);
  final _name = TextEditingController();
  int _lastCount = -1;
  double _lastInset = 0;

  bool get _admin => widget.employee.isManagement;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    if (_needsName) {
      TypedName.load().then((n) {
        if (mounted && _name.text.isEmpty) setState(() => _name.text = n);
      });
    }
    // Opened (for example from a notification): counts as read.
    BroadcastService.instance.markSeen(widget.employee.uid);
  }

  @override
  void dispose() {
    _text.dispose();
    _name.dispose();
    _scroll.dispose();
    super.dispose();
  }

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

  void _send() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final typed = !_admin && _showName && _needsName;
    if (typed) {
      final problem = TypedName.check(_name.text);
      if (problem != null) {
        messenger.showSnackBar(SnackBar(content: Text(problem)));
        return;
      }
      unawaited(TypedName.save(_name.text));
    }
    _text.clear();
    unawaited(
      BroadcastService.instance
          .comment(
            broadcastId: widget.broadcastId,
            me: widget.employee,
            text: text,
            showName: _showName,
            name: typed ? _name.text.trim() : null,
          )
          .catchError((Object e) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not send. Please try again.')),
        );
        if (mounted && _text.text.isEmpty) _text.text = text;
      }),
    );
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text('Delete this broadcast?'),
        content: const Text('It will be removed for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFD92D20)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final nav = Navigator.of(context);
    try {
      await BroadcastService.instance.delete(widget.broadcastId);
      nav.pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
            if (_admin)
              IconButton(
                tooltip: 'Delete',
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline_rounded, color: threadSoft),
              ),
            const ThreadTitlePill('Broadcast', icon: Icons.campaign_outlined),
          ],
        ),
        body: StreamBuilder<Broadcast?>(
          stream: _item,
          initialData: widget.initial,
          builder: (context, itemSnap) {
            final b = itemSnap.data;
            if (b == null) {
              return Center(
                child: itemSnap.connectionState == ConnectionState.waiting
                    ? const CircularProgressIndicator(color: AppColors.blue)
                    : Text('This broadcast was removed.',
                        style: threadText(14.5, color: threadSoft)),
              );
            }
            return Column(
              children: [
                _Header(b: b),
                Expanded(
                  child: StreamBuilder<List<BroadcastComment>>(
                    stream: _comments,
                    builder: (context, snap) {
                      final comments = snap.data ?? const <BroadcastComment>[];
                      if (snap.hasData) _scrollDownIfNew(comments.length);
                      return ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 8),
                            child: Text(
                              comments.isEmpty
                                  ? 'Discussion'
                                  : 'Discussion · ${comments.length}',
                              style: threadText(13, color: threadSoft),
                            ),
                          ),
                          if (snap.hasData && comments.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Text(
                                'No comments yet. Share what you think.',
                                style: threadText(13.5,
                                    color: AppColors.muted, height: 1.45),
                              ),
                            ),
                          for (final c in comments) _CommentBubble(c: c),
                        ],
                      );
                    },
                  ),
                ),
                if (!_admin) _NameChoice(
                  show: _showName,
                  name: widget.employee.name,
                  onChanged: (v) => setState(() => _showName = v),
                ),
                if (!_admin && _showName && _needsName)
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: TypedNameField(controller: _name, compact: true),
                  ),
                ThreadComposer(
                  controller: _text,
                  hint: _admin ? 'Reply as Admin…' : 'Write a comment…',
                  onSend: _send,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The broadcast itself, fixed on top.
class _Header extends StatelessWidget {
  const _Header({required this.b});

  final Broadcast b;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEEF1F6))),
      ),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.38,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F8FB),
            borderRadius: BorderRadius.circular(16),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Admin',
                        style: threadText(12, color: AppColors.blue),
                      ),
                      TextSpan(text: '  ·  ${_when(b.createdAt)}'),
                    ],
                  ),
                  style: threadText(12, color: threadSoft),
                ),
                const SizedBox(height: 6),
                Text(b.title, style: threadText(16, weight: FontWeight.w500)),
                if (b.quote != null) ...[
                  const SizedBox(height: 8),
                  _Quote(text: b.quote!),
                ],
                if (b.body.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    b.body,
                    style: threadText(14.5, color: const Color(0xFF344054), height: 1.45),
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

/// One comment: name (or "Name hidden" / "Admin") and the text.
class _CommentBubble extends StatelessWidget {
  const _CommentBubble({required this.c});

  final BroadcastComment c;

  @override
  Widget build(BuildContext context) {
    final who = c.admin ? 'Admin' : (c.name ?? '🔒 Name hidden');
    final time = c.pending
        ? 'Sending…'
        : (c.createdAt == null ? '' : threadDate(c.createdAt!).split(', ').last);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.82,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(13, 9, 13, 7),
            decoration: BoxDecoration(
              color: c.admin ? AppColors.blueTint : const Color(0xFFF2F4F8),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  who,
                  style: threadText(
                    12,
                    weight: FontWeight.w500,
                    color: c.admin ? AppColors.blue : const Color(0xFF475467),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  c.text,
                  style: threadText(
                    14.5,
                    height: 1.4,
                    color: c.pending ? AppColors.muted : AppColors.ink,
                  ),
                ),
                if (time.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(time, style: threadText(10.5, color: threadSoft)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Employees: "🔒 Hide my name" / "👤 Show my name" above the comment box.
class _NameChoice extends StatelessWidget {
  const _NameChoice({
    required this.show,
    required this.name,
    required this.onChanged,
  });

  final bool show;
  final String name;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SendAsChoice(named: show, onChanged: onChanged, compact: true),
    );
  }
}

// ---------------------------------------------------------------------
// New broadcast (admin)
// ---------------------------------------------------------------------

/// Admin: write a broadcast. From a suggestion, [quote] is its text
/// (never the name of who wrote it), and can be removed with ✕.
class NewBroadcastScreen extends StatefulWidget {
  const NewBroadcastScreen({super.key, this.quote});

  final String? quote;

  @override
  State<NewBroadcastScreen> createState() => _NewBroadcastScreenState();
}

class _NewBroadcastScreenState extends State<NewBroadcastScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  String? _quote;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _quote = widget.quote;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await BroadcastService.instance.send(
        title: _title.text,
        body: _body.text,
        quote: _quote,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Sent to everyone.')),
      );
      nav.pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not send. Please check your internet and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: 1.5),
        );
    InputDecoration deco(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: threadText(15, color: const Color(0xFF9AA3B8)),
          contentPadding: const EdgeInsets.all(14),
          border: border(_line),
          enabledBorder: border(_line),
          focusedBorder: border(AppColors.blue),
          errorBorder: border(Theme.of(context).colorScheme.error),
          focusedErrorBorder: border(Theme.of(context).colorScheme.error),
        );
    Widget label(String s) => Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(s, style: threadText(13, color: const Color(0xFF5F6A84))),
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
          title: const SizedBox.shrink(),
          actions: const [
            ThreadTitlePill('New broadcast', icon: Icons.campaign_outlined),
          ],
        ),
        body: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  children: [
                    label('Title'),
                    TextFormField(
                      controller: _title,
                      maxLength: 120,
                      textCapitalization: TextCapitalization.sentences,
                      style: threadText(15),
                      decoration: deco('For example: Air dryer added on 5th floor')
                          .copyWith(counterText: ''),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Write a short title'
                          : null,
                    ),
                    if (_quote != null) ...[
                      const SizedBox(height: 16),
                      label('From a suggestion (name not shared)'),
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF6F8FB),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                '“${_quote!.trim()}”',
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: threadText(13.5,
                                    color: const Color(0xFF5F6A84), height: 1.4),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => setState(() => _quote = null),
                              icon: const Icon(Icons.close_rounded,
                                  size: 18, color: threadSoft),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    label('Message'),
                    TextFormField(
                      controller: _body,
                      minLines: 4,
                      maxLines: 10,
                      maxLength: 2000,
                      textCapitalization: TextCapitalization.sentences,
                      style: threadText(15, height: 1.45),
                      decoration: deco('What do you want to tell everyone?'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 6),
                      Text(_error!,
                          style: threadText(13.5,
                              color: Theme.of(context).colorScheme.error)),
                    ],
                  ],
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFEEF1F6))),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton(
                          onPressed: _busy ? null : _send,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.blue,
                            minimumSize: const Size.fromHeight(52),
                            shape: const StadiumBorder(),
                            textStyle: threadText(15.5, weight: FontWeight.w500),
                          ),
                          child: _busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Send to everyone'),
                        ),
                        const SizedBox(height: 6),
                        Text('Everyone gets a notification',
                            style: threadText(12, color: threadSoft)),
                      ],
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
