import 'package:flutter/foundation.dart';

import 'push_sender_stub.dart'
    if (dart.library.io) 'push_sender_io.dart' as impl;

/// Sends push notifications from the app.
///
/// A failure here never stops the action that caused it: the suggestion
/// is still saved and the status is still updated.
class PushSender {
  /// Sending works in the Android and iOS apps, not on web.
  static bool get available => !kIsWeb;

  static Future<bool> toTopic(
    String topic, {
    required String title,
    required String body,
    Map<String, String>? data,
  }) {
    return _safe(
      () => impl.sendPush(topic: topic, title: title, body: body, data: data),
    );
  }

  /// Returns true if at least one device accepted the notification.
  static Future<bool> toTokens(
    List<String> tokens, {
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    var delivered = false;
    for (final token in tokens) {
      final ok = await _safe(
        () => impl.sendPush(
          token: token,
          title: title,
          body: body,
          data: data,
        ),
      );
      delivered = delivered || ok;
    }
    return delivered;
  }

  static Future<bool> _safe(Future<bool> Function() send) async {
    if (!available) return false;
    try {
      return await send();
    } catch (error) {
      debugPrint('Notification not sent: $error');
      return false;
    }
  }

  // What a notification is about. The receiving phone uses this to open
  // the right screen when the notification is tapped.
  static const String typeFeedbackNew = 'feedback_new';
  static const String typeFeedbackReply = 'feedback_reply';
  static const String typePulseOpen = 'pulse_open';
  static const String typePulseReminder = 'pulse_reminder';
  static const String typePulseResponse = 'pulse_response';

  static String shorten(String text, [int max = 120]) {
    final t = text.trim().replaceAll('\n', ' ');
    return t.length <= max ? t : '${t.substring(0, max - 1)}…';
  }
}
