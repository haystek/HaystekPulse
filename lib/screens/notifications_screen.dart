import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../widgets/ui.dart';
import '../models/employee.dart';
import '../services/notification_feed.dart';
import '../theme/app_theme.dart';
import 'feedback_detail_screen.dart';
import 'my_feedback_screen.dart';
import 'weekly_pulse_screen.dart';

/// The in-app list of notifications. Tapping a row opens what it is about.
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

  @override
  void initState() {
    super.initState();
    _stream = NotificationFeed.instance.watch(widget.employee);
    _rememberAndMarkSeen();
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
        screen = MyFeedbackScreen(employee: employee);
      case AppNotificationKind.pulseOpen:
      case AppNotificationKind.pulseReminder:
        screen = WeeklyPulseScreen(employee: employee);
    }
    final target = screen;
    if (target == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => target),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 68,
        leading: const AppBackButton(),
        title: const Text('Notifications'),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: StreamBuilder<List<AppNotification>>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return const _Empty(
                    text: 'Could not load notifications. '
                        'Please go back and try again.',
                  );
                }
                if (!snap.hasData || !_seenLoaded) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snap.data!;
                if (rows.isEmpty) {
                  return const _Empty(text: 'No notifications yet.');
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final n = rows[i];
                    final seen = _seenBefore;
                    final isNew = seen == null || n.time.isAfter(seen);
                    return _NotificationRow(
                      notification: n,
                      isNew: isNew,
                      onTap: () => _open(n),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}

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
        return Icons.inventory_2;
      case AppNotificationKind.feedbackReply:
        return Icons.check_circle;
      case AppNotificationKind.pulseOpen:
        return Icons.notifications;
      case AppNotificationKind.pulseReminder:
        return Icons.notifications_active;
    }
  }

  Color get _color {
    switch (notification.kind) {
      case AppNotificationKind.feedbackNew:
        return AppColors.green;
      case AppNotificationKind.feedbackReply:
        return AppColors.success;
      case AppNotificationKind.pulseOpen:
        return AppColors.blue;
      case AppNotificationKind.pulseReminder:
        return const Color(0xFFD9770B);
    }
  }

  String _when(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    return '${d.day} ${months[d.month - 1]}, $hour12:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: isNew ? const Color(0xFFEAF2FE) : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_icon, color: _color, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (notification.body.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        notification.body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      _when(notification.time),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (isNew) ...[
                const SizedBox(width: 8),
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: CircleAvatar(
                    radius: 5,
                    backgroundColor: AppColors.blue,
                  ),
                ),
              ],
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
