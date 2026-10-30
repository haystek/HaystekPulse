import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/app_notification.dart';
import '../models/employee.dart';
import '../services/notification_feed.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'feedback_detail_screen.dart';
import 'my_feedback_screen.dart';
import 'weekly_pulse_screen.dart';

/// One font for this screen: Inter.
TextStyle _inter(
    double size, {
      FontWeight weight = FontWeight.w400,
      Color color = AppColors.ink,
      double? height,
    }) =>
    GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );

const Color _soft = Color(0xFF8E97AB);

/// The in-app list of notifications.
/// - Tap a row, or swipe it to the right: opens what it is about.
/// - Swipe a row to the left: deletes it (with Undo).
/// - Menu at the top right: "Delete all".
/// - Rows are grouped: Today, Yesterday, Earlier.
/// Deleting saves the id in Firebase (user_state/{uid}), so it stays
/// deleted on every phone. The feedback itself is never deleted, and
/// other people still see their own notifications.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.employee});

  final Employee employee;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final Stream<List<AppNotification>> _stream;

  /// When the person last looked, before this visit. Rows newer than this
  /// are marked as new.
  DateTime? _seenBefore;
  bool _seenLoaded = false;

  /// Just deleted, so the row goes at once (before Firebase answers).
  final Set<String> _justDeleted = {};
  bool _showTip = false;
  ScaffoldMessengerState? _messenger;

  NotificationFeed get _feed => NotificationFeed.instance;
  String get _uid => widget.employee.uid;

  @override
  void initState() {
    super.initState();
    _stream = _feed.watch(widget.employee);
    _rememberAndMarkSeen();
    _loadTip();
    _cleanOld();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.of(context);
  }

  @override
  void dispose() {
    // Leaving Notifications: remove the Undo bar.
    _messenger?.hideCurrentSnackBar();
    super.dispose();
  }

  Future<void> _loadTip() async {
    final seen = await _feed.fetchTipSeen(_uid);
    if (mounted) setState(() => _showTip = !seen);
  }

  void _closeTip() {
    setState(() => _showTip = false);
    _feed.markTipSeen(_uid).catchError((_) {});
  }

  /// Keeps the saved "deleted" list small.
  Future<void> _cleanOld() async {
    try {
      final all = await _feed.watchAllRows(widget.employee).first;
      await _feed.cleanHidden(_uid, all.map((n) => n.id).toSet());
    } catch (_) {}
  }

  void _showSnack(String text, VoidCallback onUndo) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          // Close by itself, even with the Undo button.
          persist: false,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(label: 'Undo', onPressed: onUndo),
        ),
      );
  }

  void _failed() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Could not delete. Please check the internet.'),
        ),
      );
  }

  Future<void> _rememberAndMarkSeen() async {
    final feed = NotificationFeed.instance;
    final uid = widget.employee.uid;
    DateTime? before;
    try {
      before = await feed.fetchSeenAt(uid);
    } catch (_) {
      before = null;
    }
    if (mounted) {
      setState(() {
        _seenBefore = before;
        _seenLoaded = true;
      });
    }
    try {
      await feed.markSeen(uid);
    } catch (_) {
      // The badge simply stays until the next visit.
    }
  }

  void _open(AppNotification n) {
    final employee = widget.employee;
    Widget? screen;
    switch (n.kind) {
      case AppNotificationKind.feedbackNew:
        final item = n.item;
        if (item != null) screen = FeedbackDetailScreen(item: item);
      case AppNotificationKind.feedbackReply:
      // Open that one suggestion or comment in the bottom sheet, with
      // the reply. If it is not known, open My Feedback on the right
      // tab (Weekly Pulse comments on the Weekly Pulse tab).
        final item = n.item;
        if (item != null) {
          showMyFeedbackSheet(context, item);
          return;
        }
        screen = MyFeedbackScreen(employee: employee);
      case AppNotificationKind.pulseOpen:
      case AppNotificationKind.pulseReminder:
        screen = WeeklyPulseScreen(employee: employee);
    }
    final target = screen;
    if (target == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('This item is no longer available.')),
        );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => target),
    );
  }

  Future<void> _delete(AppNotification n) async {
    setState(() => _justDeleted.add(n.id));
    _showSnack('Notification deleted', () => _undo([n.id]));
    try {
      await _feed.hide(_uid, [n.id]);
    } catch (_) {
      if (mounted) setState(() => _justDeleted.remove(n.id));
      _failed();
    }
  }

  Future<void> _undo(List<String> ids) async {
    if (!mounted) return;
    setState(() => _justDeleted.removeAll(ids));
    try {
      await _feed.unhide(_uid, ids);
    } catch (_) {}
  }

  Future<void> _deleteAll(List<AppNotification> rows) async {
    if (rows.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all notifications?'),
        content: const Text(
          'They will be removed from your list on all your phones. '
              'The feedback and replies themselves are not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFD92D20),
            ),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final ids = rows.map((n) => n.id).toList();
    setState(() => _justDeleted.addAll(ids));
    _showSnack('All notifications deleted', () => _undo(ids));
    try {
      await _feed.hide(_uid, ids);
    } catch (_) {
      if (mounted) setState(() => _justDeleted.removeAll(ids));
      _failed();
    }
  }

  /// "Today", "Yesterday" or "Earlier".
  static String _group(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return 'Earlier';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppNotification>>(
      stream: _stream,
      builder: (context, snap) {
        final all = snap.data ?? const <AppNotification>[];
        final rows = all.where((n) => !_justDeleted.contains(n.id)).toList()
          ..sort((a, b) => b.time.compareTo(a.time));

        Widget body;
        if (snap.hasError) {
          body = const _Empty(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load notifications',
            text: 'Please go back and try again.',
          );
        } else if (!snap.hasData || !_seenLoaded) {
          body = const Center(child: CircularProgressIndicator());
        } else if (rows.isEmpty) {
          body = const _Empty(
            icon: Icons.notifications_none_rounded,
            title: 'Nothing to see right now',
            text: 'New notifications will show here.',
          );
        } else {
          // Rows with group headers in between.
          final children = <Widget>[];
          if (_showTip) children.add(_Tip(onClose: _closeTip));
          String? lastGroup;
          for (final n in rows) {
            final g = _group(n.time);
            if (g != lastGroup) {
              children.add(
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    4,
                    lastGroup == null ? 4 : 18,
                    4,
                    8,
                  ),
                  child: Text(
                    g,
                    style: _inter(13, weight: FontWeight.w600, color: _soft),
                  ),
                ),
              );
              lastGroup = g;
            }
            final seen = _seenBefore;
            final isNew = seen == null || n.time.isAfter(seen);
            children.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SwipeRow(
                  key: ValueKey(n.id),
                  onOpen: () => _open(n),
                  onDelete: () => _delete(n),
                  child: _NotificationRow(
                    notification: n,
                    isNew: isNew,
                    onTap: () => _open(n),
                  ),
                ),
              ),
            );
          }
          body = ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: children,
          );
        }

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            leadingWidth: 68,
            leading: const AppBackButton(),
            // No title on the left: the name sits on the right in a pill.
            title: const SizedBox.shrink(),
            actions: [
              const _TitlePill(
                'Notifications',
                icon: Icons.notifications_none_rounded,
              ),
              if (rows.isNotEmpty)
                PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_vert),
                  position: PopupMenuPosition.under,
                  onSelected: (v) {
                    if (v == 'all') _deleteAll(rows);
                    if (v == 'tip') setState(() => _showTip = true);
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'all',
                      child: Row(
                        children: [
                          Icon(Icons.delete_sweep_outlined, size: 20),
                          SizedBox(width: 10),
                          Text('Delete all'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'tip',
                      child: Row(
                        children: [
                          Icon(Icons.help_outline, size: 20),
                          SizedBox(width: 10),
                          Text('How to use'),
                        ],
                      ),
                    ),
                  ],
                ),
              const SizedBox(width: 4),
            ],
          ),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: body,
              ),
            ),
          ),
        );
      },
    );
  }
}

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


/// A small blue tip at the top that explains the swipes.
class _Tip extends StatelessWidget {
  const _Tip({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    Widget line(IconData icon, Color color, String text) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: _inter(13, color: const Color(0xFF3B4560)),
            ),
          ),
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE6FB)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quick tip',
                  style: _inter(14, weight: FontWeight.w600),
                ),
                line(
                  Icons.touch_app_outlined,
                  AppColors.blue,
                  'Tap a notification to open it.',
                ),
                line(
                  Icons.swipe_right_alt,
                  AppColors.blue,
                  'Swipe right to open.',
                ),
                line(
                  Icons.swipe_left_alt,
                  const Color(0xFFD92D20),
                  'Swipe left to delete. You can undo.',
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Got it',
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18, color: _soft),
          ),
        ],
      ),
    );
  }
}

/// A row that can be swiped:
/// to the right = open (blue), to the left = delete (red).
class _SwipeRow extends StatelessWidget {
  const _SwipeRow({
    super.key,
    required this.child,
    required this.onOpen,
    required this.onDelete,
  });

  final Widget child;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  Widget _bg({
    required Color color,
    required IconData icon,
    required String label,
    required bool left,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      alignment: left ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 8),
          Text(
            label,
            style: _inter(14, weight: FontWeight.w600, color: Colors.white),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: key!,
      // Swipe right: open.
      background: _bg(
        color: AppColors.blue,
        icon: Icons.open_in_new_rounded,
        label: 'Open',
        left: true,
      ),
      // Swipe left: delete.
      secondaryBackground: _bg(
        color: const Color(0xFFD92D20),
        icon: Icons.delete_outline_rounded,
        label: 'Delete',
        left: false,
      ),
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.3,
        DismissDirection.endToStart: 0.35,
      },
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Open, and leave the row in the list.
          onOpen();
          return false;
        }
        return true;
      },
      onDismissed: (_) => onDelete(),
      child: child,
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFF2F6FF),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: AppColors.blue),
            ),
            const SizedBox(height: 14),
            Text(title, style: _inter(17, weight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              text,
              textAlign: TextAlign.center,
              style: _inter(14, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// One notification: a coloured icon, a small type label
/// ("New suggestion", "Reply", ...), the title, the text and the time.
class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.notification,
    required this.isNew,
    required this.onTap,
  });

  final AppNotification notification;
  final bool isNew;
  final VoidCallback onTap;

  IconData get _icon {
    switch (notification.kind) {
      case AppNotificationKind.feedbackNew:
        return Icons.mark_email_unread_outlined;
      case AppNotificationKind.feedbackReply:
        return Icons.forum_outlined;
      case AppNotificationKind.pulseOpen:
        return Icons.favorite_rounded;
      case AppNotificationKind.pulseReminder:
        return Icons.alarm_rounded;
    }
  }

  Color get _color {
    switch (notification.kind) {
      case AppNotificationKind.feedbackNew:
        return const Color(0xFF7C3AED);
      case AppNotificationKind.feedbackReply:
        return const Color(0xFF15803D);
      case AppNotificationKind.pulseOpen:
        return AppColors.blue;
      case AppNotificationKind.pulseReminder:
        return const Color(0xFFD9770B);
    }
  }

  /// A short, plain label for the type, so everyone knows what it is.
  String get _type {
    switch (notification.kind) {
      case AppNotificationKind.feedbackNew:
        return 'New feedback';
      case AppNotificationKind.feedbackReply:
        return 'Reply from admin';
      case AppNotificationKind.pulseOpen:
        return 'Weekly Pulse is open';
      case AppNotificationKind.pulseReminder:
        return 'Reminder';
    }
  }

  /// "Just now", "5 min ago", "2 h ago", "Yesterday, 4:12 PM", "9 Oct, 4:12 PM".
  static String _when(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    final time = '$hour12:$minute ${d.hour < 12 ? 'AM' : 'PM'}';
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final days = today.difference(day).inDays;
    if (days == 0) return '${diff.inHours} h ago';
    if (days == 1) return 'Yesterday, $time';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}, $time';
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Material(
      color: isNew ? const Color(0xFFF2F6FF) : const Color(0xFFF6F8FB),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _type,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _inter(
                              12.5,
                              weight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _when(notification.time),
                          style: _inter(12, color: _soft),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      notification.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _inter(
                        15,
                        weight: isNew ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    if (notification.body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        notification.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _inter(
                          13.5,
                          color: const Color(0xFF5B6478),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                children: [
                  if (isNew)
                    Container(
                      width: 9,
                      height: 9,
                      margin: const EdgeInsets.only(top: 4, bottom: 6),
                      decoration: const BoxDecoration(
                        color: AppColors.blue,
                        shape: BoxShape.circle,
                      ),
                    )
                  else
                    const SizedBox(height: 19),
                  const Icon(Icons.chevron_right, color: _soft, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}