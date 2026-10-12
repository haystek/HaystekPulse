import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../config.dart';
import '../models/app_notification.dart';
import '../models/employee.dart';
import '../models/feedback_item.dart';
import '../models/pulse_rating.dart';
import 'feedback_service.dart';
import 'pulse_service.dart';
import 'push_sender.dart';

/// The list behind the in-app Notifications screen.
///
/// Nothing extra is stored per notification. The list is built from what
/// already exists:
/// - management: every feedback entry, newest first;
/// - employee: replies to their own feedback, plus the "Weekly Pulse is
///   open" and reminder messages management has sent.
class NotificationFeed {
  NotificationFeed._();
  static final NotificationFeed instance = NotificationFeed._();

  static const int _maxRows = 50;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// One document per "Notify all" or "Remind" tap by management.
  CollectionReference<Map<String, dynamic>> get _broadcasts =>
      _db.collection('broadcasts');

  /// Each person's own "last looked at notifications" time.
  DocumentReference<Map<String, dynamic>> _state(String uid) =>
      _db.collection('user_state').doc(uid);

  /// Whether this employee answered the pulse in a given week.
  final Map<String, bool> _answeredCache = {};

  Stream<List<AppNotification>> watch(Employee employee) {
    return employee.isManagement
        ? _watchManagement()
        : _watchEmployee(employee);
  }

  Stream<List<AppNotification>> _watchManagement() {
    return FeedbackService.instance.watchAll().map((items) {
      final fallback = DateTime.now();
      return [
        for (final item in items.take(_maxRows))
          AppNotification(
            kind: AppNotificationKind.feedbackNew,
            title: item.isFromBox
                ? 'New suggestion received'
                : item.rating == null
                    ? 'Weekly Pulse feedback'
                    : 'Weekly Pulse feedback: '
                        '${PulseRating.label(item.rating!)}',
            body: PushSender.shorten(item.text),
            time: item.createdAt ?? fallback,
            item: item,
          ),
      ];
    });
  }

  Stream<List<AppNotification>> _watchEmployee(Employee employee) {
    final replies =
        FeedbackService.instance.watchMyFeedback(employee.uid).map((items) {
      final fallback = DateTime.now();
      return [
        for (final item in items)
          if (_notifiesEmployee(item))
            AppNotification(
              kind: AppNotificationKind.feedbackReply,
              title: item.status == FeedbackStatus.implemented
                  ? 'Your feedback has been implemented'
                  : 'Your feedback was updated: '
                      '${FeedbackStatus.label(item.status)}',
              body: item.hasReply
                  ? PushSender.shorten(item.managementMessage)
                  : PushSender.shorten(item.text),
              time: item.updatedAt ?? item.createdAt ?? fallback,
              item: item,
            ),
      ];
    });

    final broadcasts = _broadcasts
        .orderBy('createdAt', descending: true)
        .limit(15)
        .snapshots()
        .asyncMap((snap) => _broadcastRows(snap, employee.uid));

    return _combine2<List<AppNotification>, List<AppNotification>,
        List<AppNotification>>(replies, broadcasts, (a, b) {
      final all = [...a, ...b]..sort((x, y) => y.time.compareTo(x.time));
      return all.take(_maxRows).toList();
    });
  }

  bool _notifiesEmployee(FeedbackItem item) {
    if (item.status == FeedbackStatus.implemented) return true;
    return AppConfig.notifyEmployeeOnEveryStatus &&
        item.status != FeedbackStatus.newItem;
  }

  /// A reminder is listed only for a week this employee did not answer.
  Future<List<AppNotification>> _broadcastRows(
    QuerySnapshot<Map<String, dynamic>> snap,
    String uid,
  ) async {
    final rows = <AppNotification>[];
    final fallback = DateTime.now();
    for (final doc in snap.docs) {
      final data = doc.data();
      final reminder = data['type'] == PushSender.typePulseReminder;
      final weekId = (data['weekId'] ?? '') as String;
      if (weekId.isNotEmpty && await _answered(uid, weekId)) {
        continue;
      }
      final created = data['createdAt'];
      rows.add(
        AppNotification(
          kind: reminder
              ? AppNotificationKind.pulseReminder
              : AppNotificationKind.pulseOpen,
          title: (data['title'] ?? '') as String,
          body: (data['body'] ?? '') as String,
          time: created is Timestamp ? created.toDate() : fallback,
        ),
      );
    }
    return rows;
  }

  Future<bool> _answered(String uid, String weekId) async {
    final key = '${weekId}_$uid';
    final cached = _answeredCache[key];
    if (cached == true) return true;
    try {
      final doc = await _db.collection('pulse_responses').doc(key).get();
      _answeredCache[key] = doc.exists;
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  /// Management: records a "Notify all" or "Remind" message so it also
  /// appears in every employee's Notifications screen.
  Future<void> recordBroadcast({
    required String type,
    required String title,
    required String body,
  }) {
    return _broadcasts.add(<String, dynamic>{
      'type': type,
      'title': title,
      'body': body,
      'weekId': PulseService.currentWeekId(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// When this person last opened the Notifications screen.
  Stream<DateTime?> watchSeenAt(String uid) {
    return _state(uid).snapshots().map((doc) => _seenAt(doc.data()));
  }

  Future<DateTime?> fetchSeenAt(String uid) async {
    final doc = await _state(uid).get();
    return _seenAt(doc.data());
  }

  Future<void> markSeen(String uid) {
    return _state(uid).set(<String, dynamic>{
      'notificationsSeenAt': Timestamp.now(),
    });
  }

  DateTime? _seenAt(Map<String, dynamic>? data) {
    final v = data?['notificationsSeenAt'];
    return v is Timestamp ? v.toDate() : null;
  }

  static int unreadCount(List<AppNotification> rows, DateTime? seenAt) {
    if (seenAt == null) return rows.length;
    return rows.where((r) => r.time.isAfter(seenAt)).length;
  }
}

/// Emits a combined value whenever either stream changes, once both
/// have produced at least one value.
Stream<R> _combine2<A, B, R>(
  Stream<A> a,
  Stream<B> b,
  R Function(A, B) combine,
) {
  late final StreamController<R> controller;
  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;
  A? lastA;
  B? lastB;
  var hasA = false;
  var hasB = false;

  void emit() {
    if (hasA && hasB && !controller.isClosed) {
      controller.add(combine(lastA as A, lastB as B));
    }
  }

  controller = StreamController<R>(
    onListen: () {
      subA = a.listen(
        (value) {
          lastA = value;
          hasA = true;
          emit();
        },
        onError: controller.addError,
      );
      subB = b.listen(
        (value) {
          lastB = value;
          hasB = true;
          emit();
        },
        onError: controller.addError,
      );
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
    },
  );
  return controller.stream;
}
