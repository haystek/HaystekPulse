import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../models/employee.dart';
import '../screens/notifications_screen.dart';
import '../services/notification_feed.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// The bell in the top bar, with a count of notifications not yet seen.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key, required this.employee});

  final Employee employee;

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  late final Stream<List<AppNotification>> _rows;
  late final Stream<DateTime?> _seenAt;

  @override
  void initState() {
    super.initState();
    final feed = NotificationFeed.instance;
    _rows = feed.watch(widget.employee);
    _seenAt = feed.watchSeenAt(widget.employee.uid);
  }

  void _open() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationsScreen(employee: widget.employee),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppNotification>>(
      stream: _rows,
      builder: (context, rowsSnap) {
        return StreamBuilder<DateTime?>(
          stream: _seenAt,
          builder: (context, seenSnap) {
            // Show a count only once both have loaded, so the badge does
            // not flash a wrong number on start.
            final ready = rowsSnap.hasData &&
                seenSnap.connectionState != ConnectionState.waiting;
            final unread = ready
                ? NotificationFeed.unreadCount(rowsSnap.data!, seenSnap.data)
                : 0;
            return RoundIconButton(
              tooltip: 'Notifications',
              onPressed: _open,
              child: Badge(
                isLabelVisible: unread > 0,
                backgroundColor: AppColors.alert,
                label: Text(unread > 9 ? '9+' : '$unread'),
                child: const Icon(
                  Icons.notifications_none,
                  color: AppColors.ink,
                  size: 22,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
