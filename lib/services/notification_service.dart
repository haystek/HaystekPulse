import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config.dart';
import '../models/employee.dart';
import '../models/feedback_item.dart';
import '../screens/feedback_detail_screen.dart';
import '../screens/feedback_list_screen.dart';
import '../screens/my_feedback_screen.dart';
import '../screens/weekly_pulse_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/top_banner.dart';
import 'feedback_service.dart';
import 'pulse_service.dart';
import 'push_sender.dart';
import 'schedule_service.dart';

/// Receiving notifications: permission, this device's token, and the
/// groups (topics) this device belongs to.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  /// Lets a notification that arrives while the app is open be shown
  /// as a message at the bottom of whichever screen is visible.
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
  GlobalKey<ScaffoldMessengerState>();

  /// Lets a tapped notification open a screen from anywhere in the app.
  static final GlobalKey<NavigatorState> navigatorKey =
  GlobalKey<NavigatorState>();

  /// Every management phone is in this group.
  static const String topicManagement = 'management';

  /// Every employee phone is in this group.
  static const String topicEmployees = 'employees';

  /// Phones that have not answered the Weekly Pulse for that week.
  static String pendingTopic(String weekId) => 'pulse_pending_$weekId';

  /// Only the author's phone is in this group, one group per feedback
  /// entry. Management sends status updates here without knowing who
  /// is in it, so anonymous feedback stays anonymous.
  static String feedbackTopic(String feedbackId) => 'fb_$feedbackId';

  /// The feedback groups this phone joined, so sign-out can leave them.
  final Set<String> _followed = <String>{};

  /// The sign-out cleanup, while it is still running.
  Future<void>? _stopping;

  bool get supported => !kIsWeb;

  String? _startedFor;
  String? _token;
  Employee? _employee;
  RemoteMessage? _waitingToOpen;

  /// Shows a normal phone notification while the app is open (Android).
  final FlutterLocalNotificationsPlugin _local =
  FlutterLocalNotificationsPlugin();
  bool _localReady = false;

  /// The same channel the notifications from Firebase use (see
  /// push_sender_io.dart), so open or closed, they look and sound the same.
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'haystek_alerts',
    'Haystek Pulse',
    description: 'Weekly Pulse and feedback updates',
    importance: Importance.high,
  );

  /// Sets up phone notifications shown by the app itself, once.
  Future<void> _initLocal() async {
    if (_localReady) return;
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      // Tapping that notification opens the right screen.
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        final data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
        unawaited(_open(RemoteMessage(data: data)));
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
    _localReady = true;
  }
  bool _checkedLaunchMessage = false;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _tappedSub;
  StreamSubscription<String>? _tokenSub;

  /// This device's address for notifications, once known.
  String? get token => _token;

  FirebaseMessaging get _fm => FirebaseMessaging.instance;

  /// Called once the signed-in person's record has loaded.
  Future<void> start(Employee employee) async {
    if (!supported || _startedFor == employee.uid) return;
    // Only for the person signed in right now. Just after a sign-out the
    // old screens can still ask once with the previous person's record;
    // that must not put this phone back in their groups.
    if (FirebaseAuth.instance.currentUser?.uid != employee.uid) return;
    _startedFor = employee.uid;
    _employee = employee;
    // Listen first, before anything that can fail or be slow, so a
    // notification that arrives while the app is open is always shown.
    _foregroundSub ??= FirebaseMessaging.onMessage.listen(_showInApp);
    _tappedSub ??= FirebaseMessaging.onMessageOpenedApp.listen(_open);
    _tokenSub ??= _fm.onTokenRefresh.listen((t) => _token = t);
    // A sign-out just before this: let its cleanup finish first, so it
    // cannot delete the new sign-in's address.
    final stopping = _stopping;
    if (stopping != null) await stopping;
    // Signed out (or someone else signed in) while waiting: stop here.
    if (FirebaseAuth.instance.currentUser?.uid != employee.uid ||
        _startedFor != employee.uid) {
      return;
    }
    try {
      await _fm.requestPermission();
      await _initLocal();
      // iPhone: show the normal notification even when the app is open.
      // iPhone: when the app is open, our own banner shows it,
      // so no phone notification on top of it.
      await _fm.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );
    } catch (error) {
      debugPrint('Notification setup: $error');
    }
    try {
      // The token is not needed for groups (topics). If it is slow, carry
      // on and join the groups anyway.
      _token = await _fm.getToken().timeout(const Duration(seconds: 15));
    } catch (error) {
      debugPrint('No notification token yet: $error');
    }
    try {

      // A notification tapped while the app was fully closed.
      if (!_checkedLaunchMessage) {
        _checkedLaunchMessage = true;
        final launch = await _fm.getInitialMessage();
        if (launch != null) _waitingToOpen = launch;
      }
      final waiting = _waitingToOpen;
      if (waiting != null) {
        _waitingToOpen = null;
        unawaited(_open(waiting));
      }

      // One phone can be used by different people (or the same tester
      // with a management and an employee account). First leave the
      // other role's groups, so a person never gets the other side's
      // notifications.
      if (employee.isManagement) {
        await _fm.unsubscribeFromTopic(topicEmployees);
        await _leavePendingTopics();
        await _fm.subscribeToTopic(topicManagement);
        // Once more at the end, for the same reason as below.
        await _fm.unsubscribeFromTopic(topicEmployees);
      } else {
        await _fm.unsubscribeFromTopic(topicManagement);
        // The week names come from the open day. If the schedule is
        // changed in Firebase, join the new weeks' reminder groups.
        // Listen first, so a change during start-up is not missed.
        ScheduleService.changed.removeListener(_onScheduleChanged);
        ScheduleService.changed.addListener(_onScheduleChanged);
        await _fm.subscribeToTopic(topicEmployees);
        await _syncPendingTopics(employee.uid);
        await _syncFeedbackTopics(employee.uid);
        // Once more at the end: Android can replay an old "join
        // management" from the previous account after the new address
        // is made. This makes sure the employee phone is out of it.
        await _fm.unsubscribeFromTopic(topicManagement);
      }
    } catch (error) {
      debugPrint('Notifications not started: $error');
    }
  }

  void _onScheduleChanged() {
    final e = _employee;
    if (e == null || e.isManagement) return;
    unawaited(
      _syncPendingTopics(e.uid).catchError(
            (Object error) => debugPrint('Could not rejoin the groups: $error'),
      ),
    );
  }

  /// When the reminder groups were last checked (see [refreshPending]).
  DateTime? _lastPendingSync;

  /// Checks the reminder groups again. Called each time the employee
  /// home opens or the app comes back to the front, so a phone is never
  /// left out of this week's reminder (for example after test answers
  /// were deleted, or when Android kept the app alive in the
  /// background). At most once every 20 seconds.
  Future<void> refreshPending() async {
    final e = _employee;
    if (!supported || e == null || e.isManagement) return;
    final last = _lastPendingSync;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 20)) {
      return;
    }
    try {
      await _syncPendingTopics(e.uid);
    } catch (error) {
      debugPrint('Could not check the reminder groups: $error');
    }
  }

  /// Joins the "pending" group for this week and the coming weeks, so a
  /// reminder reaches this phone even if the app is not opened that week.
  /// Leaves this week's group if the pulse is already answered.
  Future<void> _syncPendingTopics(String uid) async {
    _lastPendingSync = DateTime.now();
    final now = DateTime.now();
    final answered =
        await PulseService.instance.myRatingThisWeek(uid) != null;
    for (var i = 0; i <= AppConfig.pendingTopicWeeksAhead; i++) {
      final weekId = PulseService.currentWeekId(
        DateTime(now.year, now.month, now.day + 7 * i),
      );
      if (i == 0 && answered) {
        await _fm.unsubscribeFromTopic(pendingTopic(weekId));
        debugPrint('[Reminder] answered, left ${pendingTopic(weekId)}');
      } else {
        await _fm.subscribeToTopic(pendingTopic(weekId));
        if (i == 0) debugPrint('[Reminder] joined ${pendingTopic(weekId)}');
      }
    }
  }

  /// Leaves every "pending" group: last week, this week and the coming
  /// weeks. Used for management phones and on sign-out.
  Future<void> _leavePendingTopics() async {
    final now = DateTime.now();
    for (var i = -1; i <= AppConfig.pendingTopicWeeksAhead; i++) {
      final weekId = PulseService.currentWeekId(
        DateTime(now.year, now.month, now.day + 7 * i),
      );
      await _fm.unsubscribeFromTopic(pendingTopic(weekId));
    }
  }

  /// Joins the group of every feedback entry this employee wrote. Runs
  /// at each sign-in, so a new phone or a reinstalled app still gets
  /// status updates for older entries.
  Future<void> _syncFeedbackTopics(String uid) async {
    try {
      final ids = await FeedbackService.instance.myFeedbackIds(uid);
      await Future.wait(ids.map(followFeedback));
    } catch (error) {
      debugPrint('Could not join the feedback groups: $error');
    }
  }

  /// This phone joins the group for one feedback entry (its author only).
  Future<void> followFeedback(String feedbackId) async {
    if (!supported || feedbackId.isEmpty) return;
    final topic = feedbackTopic(feedbackId);
    try {
      await _fm.subscribeToTopic(topic);
      _followed.add(topic);
    } catch (error) {
      debugPrint('Could not join $topic: $error');
    }
  }

  /// Called after the Weekly Pulse is submitted: no reminder this week.
  Future<void> markPulseSubmitted() async {
    if (!supported) return;
    try {
      await _fm.unsubscribeFromTopic(
        pendingTopic(PulseService.currentWeekId()),
      );
    } catch (error) {
      debugPrint('Could not leave the pending group: $error');
    }
  }

  /// Called on sign-out, so the next person to use this phone does not
  /// receive the previous person's notifications.
  ///
  /// Not awaited by sign-out: the person goes to the login screen at once
  /// and this finishes in the background (about a second).
  Future<void> stop() {
    if (!supported) return Future<void>.value();
    _startedFor = null;
    _token = null;
    _employee = null;
    ScheduleService.changed.removeListener(_onScheduleChanged);
    final followed = _followed.toList();
    _followed.clear();
    return _stopping = _cleanUp(followed).whenComplete(() => _stopping = null);
  }

  /// Deleting this phone's address (token) removes it from every group at
  /// once, so that is the only step normally needed. If it fails (for
  /// example no internet), leave the groups instead, all at the same time.
  Future<void> _cleanUp(List<String> followed) async {
    try {
      await _fm.deleteToken().timeout(const Duration(seconds: 10));
      return;
    } catch (error) {
      debugPrint('Could not clear the address, leaving the groups: $error');
    }
    try {
      await Future.wait([
        _fm.unsubscribeFromTopic(topicManagement),
        _fm.unsubscribeFromTopic(topicEmployees),
        _leavePendingTopics(),
        ...followed.map(_fm.unsubscribeFromTopic),
      ]);
    } catch (error) {
      debugPrint('Could not leave the groups: $error');
    }
  }

  /// A notification that arrives while the app is open: a white card
  /// slides down from the top, with an icon and a button for its type.
  void _showInApp(RemoteMessage message) {
    final n = message.notification;
    if (n == null) return;
    final title = (n.title ?? '').trim();
    final body = (n.body ?? '').trim();
    if (title.isEmpty && body.isEmpty) return;
    final type = message.data['type'] as String?;

    // Only notifications meant for this person's role. One phone used
    // with a management and an employee account can still be in the other
    // role's group for a while; never show the other side's messages.
    if (!_isForMe(type)) {
      debugPrint('[Notify] ignored "$type": not for this role');
      return;
    }

    // App is open: show only our banner. Use the phone's notification
    // bar only if the banner cannot be shown, so nothing is lost.
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) {
      _showInBar(message, title, body);
      return;
    }

    var icon = Icons.notifications_none;
    var color = AppColors.blue;
    var tint = AppColors.blueTint;
    String? action;

    switch (type) {
      case PushSender.typeFeedbackNew:
        final fromPulse = message.data['source'] == 'pulse' ||
            title.contains('Weekly Pulse');
        icon = fromPulse ? Icons.chat_bubble_outline : Icons.lightbulb_outline;
        color = fromPulse ? const Color(0xFFE2583E) : const Color(0xFFD08A00);
        tint = fromPulse ? const Color(0xFFFCE8E4) : const Color(0xFFFDF3DF);
        action = 'View';
      case PushSender.typeFeedbackReply:
        final done = title.toLowerCase().contains('implemented');
        icon = done ? Icons.check_circle_outline : Icons.update;
        color = done ? const Color(0xFF16A34A) : AppColors.blue;
        tint = done ? const Color(0xFFE3F6EA) : AppColors.blueTint;
        action = 'View';
      case PushSender.typePulseOpen:
        icon = Icons.favorite;
        action = 'Answer now';
      case PushSender.typePulseReminder:
        icon = Icons.alarm;
        color = const Color(0xFFD08A00);
        tint = const Color(0xFFFDF3DF);
        action = 'Answer now';
      case PushSender.typePulseResponse:
        icon = Icons.monitor_heart_outlined;
    }

    TopBanner.show(
      overlay: overlay,
      icon: icon,
      iconColor: color,
      tint: tint,
      title: title.isEmpty ? 'Haystek Pulse' : title,
      body: body,
      actionLabel: action,
      onAction: action == null ? null : () => _open(message),
    );
  }

  /// Whether a notification of this type is meant for the person signed
  /// in: new feedback and pulse responses for management; replies and
  /// Weekly Pulse reminders for employees. Unknown types are shown.
  bool _isForMe(String? type) {
    final e = _employee;
    if (e == null) return false;
    switch (type) {
      case PushSender.typeFeedbackNew:
      case PushSender.typePulseResponse:
        return e.isManagement;
      case PushSender.typeFeedbackReply:
      case PushSender.typePulseOpen:
      case PushSender.typePulseReminder:
      case 'pulse_soon':
        return !e.isManagement;
      default:
        return true;
    }
  }

  /// Android: shows the notification in the phone's notification bar.
  void _showInBar(RemoteMessage message, String title, String body) {
    if (_localReady && defaultTargetPlatform == TargetPlatform.android) {
      unawaited(
        _local.show(
          (message.messageId ?? '${DateTime.now().millisecondsSinceEpoch}')
              .hashCode,
          title.isEmpty ? 'Haystek Pulse' : title,
          body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              importance: Importance.high,
              priority: Priority.high,
              icon: 'ic_notification',
              color: AppColors.blue,
            ),
          ),
          payload: jsonEncode(message.data),
        ),
      );
    }
  }

  /// Opens the screen a notification is about:
  /// - new feedback   -> that entry's details (management)
  /// - reply          -> My Feedback (employee)
  /// - pulse open / reminder -> Weekly Pulse (employee)
  Future<void> _open(RemoteMessage message) async {
    final employee = _employee;
    final navigator = navigatorKey.currentState;
    if (employee == null || navigator == null) {
      // Not signed in yet. Open it once the person's record has loaded.
      _waitingToOpen = message;
      return;
    }

    final type = message.data['type'] as String?;
    final feedbackId = message.data['feedbackId'] as String?;

    if (type == PushSender.typeFeedbackNew) {
      if (!employee.isManagement) return;
      FeedbackItem? found;
      if (feedbackId != null && feedbackId.isNotEmpty) {
        try {
          found = await FeedbackService.instance.fetchById(feedbackId);
        } catch (_) {
          found = null;
        }
      }
      final item = found;
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => item != null
              ? FeedbackDetailScreen(item: item)
              : const FeedbackListScreen(),
        ),
      );
    } else if (type == PushSender.typeFeedbackReply) {
      if (employee.isManagement) return;
      // Open the right tab: 0 = Suggestions, 1 = Weekly Pulse.
      var tab = 0;
      if (feedbackId != null && feedbackId.isNotEmpty) {
        try {
          final item = await FeedbackService.instance.fetchById(feedbackId);
          if (item != null && !item.isFromBox) tab = 1;
        } catch (_) {
          // Could not check. Open Suggestions.
        }
      }
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => MyFeedbackScreen(employee: employee, initialTab: tab),
        ),
      );
    } else if (type == PushSender.typePulseOpen ||
        type == PushSender.typePulseReminder) {
      if (employee.isManagement) return;
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => WeeklyPulseScreen(employee: employee),
        ),
      );
    }
  }
}