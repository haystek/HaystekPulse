import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';

/// The Weekly Pulse schedule, from Firebase instead of the code.
///
/// It lives in one Firestore document: `settings/pulse`
///   openDay:     1 = Monday … 5 = Friday … 7 = Sunday
///   openHour:    0 – 23   (17 = 5 PM)
///   openMinute:  0 – 59
///   openDays:    1 – 7    (how many days it stays open)
///
/// Change it in the Firebase console and every phone picks it up within
/// a few seconds. No new build, no run again.
/// If the document is missing or cannot be read, the values in
/// config.dart are used.
class ScheduleService {
  ScheduleService._();

  static final DocumentReference<Map<String, dynamic>> _doc =
  FirebaseFirestore.instance.collection('settings').doc('pulse');

  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  /// Goes up by one each time the schedule changes. Screens can listen
  /// to it to redraw at once.
  static final ValueNotifier<int> changed = ValueNotifier<int>(0);

  /// Call once at start, after Firebase.initializeApp().
  /// Waits at most 4 seconds for the first value, then keeps listening.
  static Future<void> start() async {
    try {
      final snap = await _doc.get().timeout(const Duration(seconds: 4));
      if (!snap.exists) {
        debugPrint('[Schedule] settings/pulse NOT FOUND. Using config.dart.');
      }
      _apply(snap.data());
    } catch (e) {
      // Offline, slow, or the rules block it: use config.dart for now.
      debugPrint('[Schedule] could not read settings/pulse: $e');
    }
    _sub ??= _doc.snapshots().listen(
          (snap) => _apply(snap.data()),
      onError: (Object e) =>
          debugPrint('[Schedule] listen error: $e'),
    );
  }

  static void _apply(Map<String, dynamic>? data) {
    if (data == null) return;
    // Accepts numbers, and also text like "15" (easy to type by mistake
    // in the Firebase console).
    int? read(String key, int min, int max) {
      final v = data[key];
      final n = v is num ? v.toInt() : int.tryParse('${v ?? ''}'.trim());
      if (n == null || n < min || n > max) {
        debugPrint('[Schedule] $key is missing or wrong: $v');
        return null;
      }
      return n;
    }

    final day = read('openDay', 1, 7);
    final hour = read('openHour', 0, 23);
    final minute = read('openMinute', 0, 59);
    final days = read('openDays', 1, 7);

    var changedNow = false;
    if (day != null && day != AppConfig.pulseOpenDay) {
      AppConfig.pulseOpenDay = day;
      changedNow = true;
    }
    if (hour != null && hour != AppConfig.pulseOpenHour) {
      AppConfig.pulseOpenHour = hour;
      changedNow = true;
    }
    if (minute != null && minute != AppConfig.pulseOpenMinute) {
      AppConfig.pulseOpenMinute = minute;
      changedNow = true;
    }
    if (days != null && days != AppConfig.pulseOpenDays) {
      AppConfig.pulseOpenDays = days;
      changedNow = true;
    }
    debugPrint('[Schedule] day ${AppConfig.pulseOpenDay}, '
        '${AppConfig.pulseOpenHour}:${AppConfig.pulseOpenMinute}, '
        '${AppConfig.pulseOpenDays} day(s)');
    if (changedNow) changed.value++;
  }
}