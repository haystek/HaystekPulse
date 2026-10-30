import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../config.dart';
import '../models/employee.dart';
import '../models/feedback_item.dart';
import '../models/pulse_rating.dart';
import '../models/pulse_totals.dart';
import 'notification_feed.dart';
import 'feedback_service.dart' show SendError, sendLimit;
import 'notification_service.dart';
import 'push_sender.dart';
import 'text_crypto.dart';
import 'vault_service.dart';

class PulseService {
  PulseService._();
  static final PulseService instance = PulseService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// One document per employee per week: `{weekId}_{uid}`.
  /// It only says "answered this week" (no rating, no time), so nobody
  /// can see what a person chose. Only that employee can read it.
  CollectionReference<Map<String, dynamic>> get _responses =>
      _db.collection('pulse_responses');

  /// One document per week holding only the totals for the dashboard.
  CollectionReference<Map<String, dynamic>> get _weeks =>
      _db.collection('pulse_weeks');

  // ---------------------------------------------------------------
  // The weekly window. Day, time and length all come from config.dart.
  // ---------------------------------------------------------------

  /// Monday of the work week for a date. Saturday and Sunday still
  /// belong to the Monday–Friday week that just ended.
  static DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));

  /// The day this work week's window opens (for example Friday).
  static DateTime _openDateOf(DateTime d) {
    final monday = _mondayOf(d);
    return DateTime(
      monday.year,
      monday.month,
      monday.day + (AppConfig.pulseOpenDay - DateTime.monday),
    );
  }

  /// A week is named after the date its window opens, for example
  /// `2026-10-09` for the week 5 Oct – 9 Oct. It is always the
  /// Monday–Friday week we are in now, also before the window opens.
  static String currentWeekId([DateTime? now]) =>
      _idFor(_openDateOf(now ?? DateTime.now()));

  /// The work week we are in now. Same as [currentWeekId].
  static String thisWeekId() => currentWeekId();

  /// Moves a week id by whole weeks: -1 is one week back.
  static String shiftWeek(String weekId, int weeks) {
    final d = _dateOf(weekId);
    return _idFor(DateTime(d.year, d.month, d.day + 7 * weeks));
  }

  /// "This week", "Last week", or empty for older weeks.
  static String weekName(String weekId) {
    final thisWeek = thisWeekId();
    if (weekId == thisWeek) return 'This week';
    if (weekId == shiftWeek(thisWeek, -1)) return 'Last week';
    return '';
  }

  /// Whether employees can answer right now: from the open day and
  /// time, for [AppConfig.pulseOpenDays] days.
  static bool isOpen([DateTime? now]) {
    if (AppConfig.pulseOpenEveryDay) return true;
    final n = now ?? DateTime.now();
    final day = _openDateOf(n);
    final opens = DateTime(day.year, day.month, day.day,
        AppConfig.pulseOpenHour, AppConfig.pulseOpenMinute);
    final closes =
    DateTime(day.year, day.month, day.day + AppConfig.pulseOpenDays);
    return !n.isBefore(opens) && n.isBefore(closes);
  }

  /// The opening time as text, for example "5:00 PM" or "1:02 PM".
  static String openTimeLabel() {
    final h = AppConfig.pulseOpenHour;
    final m = AppConfig.pulseOpenMinute;
    final hour12 = h % 12 == 0 ? 12 : h % 12;
    final minute = m.toString().padLeft(2, '0');
    return '$hour12:$minute ${h < 12 ? 'AM' : 'PM'}';
  }

  static const List<String> _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  /// The day it opens, for example "Friday".
  static String openDayLabel() => _dayNames[AppConfig.pulseOpenDay - 1];

  /// The last day it is open, for example "Sunday".
  static String closeDayLabel() => _dayNames[
  (AppConfig.pulseOpenDay - 1 + AppConfig.pulseOpenDays - 1) % 7];

  // ---------------------------------------------------------------
  // Before, during and after this week's window.
  // ---------------------------------------------------------------

  /// When this week's window opens (open day at the open time).
  static DateTime opensAt([DateTime? now]) {
    final day = _openDateOf(now ?? DateTime.now());
    return DateTime(day.year, day.month, day.day,
        AppConfig.pulseOpenHour, AppConfig.pulseOpenMinute);
  }

  /// When this week's window closes (midnight after the last open day).
  static DateTime closesAt([DateTime? now]) {
    final day = _openDateOf(now ?? DateTime.now());
    return DateTime(day.year, day.month, day.day + AppConfig.pulseOpenDays);
  }

  /// True before this week's window opens.
  static bool notOpenYet([DateTime? now]) {
    if (AppConfig.pulseOpenEveryDay) return false;
    final n = now ?? DateTime.now();
    return n.isBefore(opensAt(n));
  }

  /// True after this week's window has closed (and the week is not over).
  static bool closedForThisWeek([DateTime? now]) {
    if (AppConfig.pulseOpenEveryDay) return false;
    final n = now ?? DateTime.now();
    return !n.isBefore(closesAt(n));
  }

  /// When the next window opens: this week's if it has not opened yet,
  /// otherwise next week's.
  static DateTime nextOpensAt([DateTime? now]) {
    final n = now ?? DateTime.now();
    if (n.isBefore(opensAt(n))) return opensAt(n);
    return opensAt(DateTime(n.year, n.month, n.day + 7));
  }

  /// The week the next window belongs to.
  static String nextWeekId([DateTime? now]) => currentWeekId(nextOpensAt(now));

  /// A date and time as text, for example "Fri 16 Oct, 5:00 PM".
  static String dateTimeLabel(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}, '
        '$hour12:$minute ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  /// A work week in one short line: "19–23 Oct" or "28 Sep–2 Oct".
  static String shortWeekLabel(String weekId) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final d = _dateOf(weekId);
    final mon = DateTime(d.year, d.month, d.day - (d.weekday - 1));
    final fri = DateTime(mon.year, mon.month, mon.day + 4);
    return mon.month == fri.month
        ? '${mon.day}–${fri.day} ${months[fri.month - 1]}'
        : '${mon.day} ${months[mon.month - 1]}–${fri.day} '
        '${months[fri.month - 1]}';
  }

  /// The work week as text, Monday to Friday, for example "5 Oct – 9 Oct".
  static String weekLabel(String weekId) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final d = _dateOf(weekId);
    final monday = DateTime(d.year, d.month, d.day - (d.weekday - 1));
    final friday = DateTime(monday.year, monday.month, monday.day + 4);
    return '${monday.day} ${months[monday.month - 1]} – '
        '${friday.day} ${months[friday.month - 1]}';
  }

  static DateTime _dateOf(String weekId) {
    final p = weekId.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  static String _idFor(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  // ---------------------------------------------------------------
  // Reading and saving.
  // ---------------------------------------------------------------

  /// Live totals for one week. Management only.
  Stream<PulseTotals> watchWeek(String weekId) {
    return _weeks
        .doc(weekId)
        .snapshots()
        .map((doc) => PulseTotals.fromMap(doc.data()));
  }

  /// How many active employees (type 'e') there are. Management only.
  Future<int> countEmployees() async {
    final result = await _db
        .collection('employees')
        .where('type', isEqualTo: 'e')
        .where('active', isEqualTo: true)
        .count()
        .get();
    return result.count ?? 0;
  }

  /// The rating this employee already gave this week, or null if not
  /// answered yet. The rating itself is in the locked history; if it is
  /// not there (for example a new history), '' means "answered".
  Future<String?> myRatingThisWeek(String uid) async {
    final weekId = currentWeekId();
    final doc = await _responses.doc('${weekId}_$uid').get();
    if (!doc.exists) return null;
    return VaultService.instance.pulseRating(weekId) ?? '';
  }

  /// Saves this week's answer straight on the server, in one go:
  /// - "answered this week" for the employee (no rating),
  /// - +1 on the week's totals (no name),
  /// - for Okay or Difficult, the written feedback (no user ID).
  /// The rating and the comment's ID go into the employee's locked
  /// history, so only they can see what they chose.
  ///
  /// It first checks on the server that this week is not answered yet
  /// (from any phone), so the totals are never counted twice, also when
  /// Send is tapped again after an error.
  ///
  /// It is either saved on the server, or it throws a [SendError] with a
  /// clear message within [sendLimit]. Nothing is kept on the phone to be
  /// sent later.
  Future<void> submit({
    required Employee employee,
    required String rating,
    String text = '',
    bool anonymous = false,
  }) async {
    final weekId = currentWeekId();
    final responseRef = _responses.doc('${weekId}_${employee.uid}');
    final feedbackRef =
    PulseRating.needsText(rating) ? _db.collection('feedback').doc() : null;
    final String? feedbackId = feedbackRef?.id;
    // Into the locked history first, so a retry can't lose it.
    if (feedbackId != null) await VaultService.instance.addPost(feedbackId);

    try {
      await _db.runTransaction<void>(
            (tx) async {
          final existing = await tx.get(responseRef);
          if (existing.exists) {
            throw const SendError(
              'You have already answered this week. Thank you.',
              alreadyAnswered: true,
            );
          }

          tx.set(responseRef, <String, dynamic>{
            'uid': employee.uid,
            'weekId': weekId,
          });

          tx.set(
            _weeks.doc(weekId),
            <String, dynamic>{
              rating: FieldValue.increment(1),
              'submitted': FieldValue.increment(1),
            },
            SetOptions(merge: true),
          );

          if (feedbackRef != null) {
            tx.set(feedbackRef, <String, dynamic>{
              'source': 'pulse',
              'rating': rating,
              'weekId': weekId,
              'text': TextCrypto.encrypt(text.trim()),
              'anonymous': anonymous,
              if (!anonymous) 'authorName': employee.name,
              if (!anonymous) 'authorEmployeeId': employee.employeeId,
              'status': FeedbackStatus.newItem,
              'managementMessage': '',
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        },
        timeout: sendLimit,
        maxAttempts: 3,
      ).timeout(sendLimit + const Duration(seconds: 2));
    } catch (error) {
      throw SendError.from(
        error,
        notAllowed: 'This could not be sent. The Weekly Pulse may have '
            'just closed. Please go back and check.',
      );
    }

    // Only the employee can see what they chose (locked history).
    unawaited(VaultService.instance.setPulse(weekId, rating));

    // The author's phone joins the group for this comment, so only they
    // hear about replies. Admin never learns which phone.
    if (feedbackId != null) {
      unawaited(NotificationService.instance.followFeedback(feedbackId));
    }

    // No reminder for this phone this week.
    unawaited(NotificationService.instance.markPulseSubmitted());

    // Tell management. The employee's name is never included.
    if (PulseRating.needsText(rating) &&
        AppConfig.notifyManagementOnPulseComments) {
      unawaited(
        PushSender.toTopic(
          NotificationService.topicManagement,
          title: 'New Weekly Pulse comment · ${PulseRating.label(rating)}',
          body: PushSender.shorten(text),
          data: {
            'type': PushSender.typeFeedbackNew,
            'feedbackId': feedbackId ?? '',
            'source': 'pulse',
          },
        ),
      );
    } else if (AppConfig.notifyManagementOnEveryPulse) {
      unawaited(
        PushSender.toTopic(
          NotificationService.topicManagement,
          title: 'Weekly Pulse response',
          body: 'An employee rated this week: ${PulseRating.label(rating)}',
          data: {'type': PushSender.typePulseResponse},
        ),
      );
    }
  }

  /// Management: "Weekly Pulse is open" to the phones that have not
  /// answered yet.
  Future<bool> notifyAllEmployees() async {
    const title = 'Weekly Pulse is open 💙';
    final body = 'How was your week? It takes 10 seconds. '
        'Open until ${closeDayLabel()} night.';
    final sent = await PushSender.toTopic(
      NotificationService.pendingTopic(currentWeekId()),
      title: title,
      body: body,
      data: {'type': PushSender.typePulseOpen},
    );
    if (sent) await _record(PushSender.typePulseOpen, title, body);
    return sent;
  }

  /// Keeps a sent message so it also shows in the Notifications screen.
  Future<void> _record(String type, String title, String body) async {
    try {
      await NotificationFeed.instance.recordBroadcast(
        type: type,
        title: title,
        body: body,
      );
    } catch (_) {
      // The push was sent. A missing history row is not an error.
    }
  }

  /// Management: a reminder to the phones that have not answered yet.
  Future<bool> remindPending() async {
    final title = 'Reminder: Weekly Pulse closes ${closeDayLabel()} ⏰';
    const body = 'You have not answered yet. It takes 10 seconds.';
    final sent = await PushSender.toTopic(
      NotificationService.pendingTopic(currentWeekId()),
      title: title,
      body: body,
      data: {'type': PushSender.typePulseReminder},
    );
    if (sent) await _record(PushSender.typePulseReminder, title, body);
    return sent;
  }
}