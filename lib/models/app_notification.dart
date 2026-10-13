import 'feedback_item.dart';

/// What a row in the Notifications screen is about.
enum AppNotificationKind { feedbackNew, feedbackReply, pulseOpen, pulseReminder }

/// One row in the in-app Notifications screen.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.time,
    this.item,
  });

  /// A fixed name for this notification, used to delete (hide) it.
  /// For example "fb_abc123_new", "fb_abc123_planned" or "bc_xyz789".
  final String id;

  final AppNotificationKind kind;
  final String title;
  final String body;
  final DateTime time;

  /// The feedback entry this is about, when there is one.
  final FeedbackItem? item;
}