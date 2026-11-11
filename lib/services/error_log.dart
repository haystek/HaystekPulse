import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// When something breaks in the app, keeps a short note so we can fix it.
///
/// Saved in Firestore `errors`: the error text, where in the code (first
/// lines of the stack), the app version and "android" or "ios".
/// Never saved: who, which phone, phone model, account, messages.
/// Only real builds send notes (not while running from the Mac), at most
/// 5 per app start, each different error once.
class ErrorLog {
  ErrorLog._();

  static String _version = '';
  static int _sent = 0;
  static final Set<String> _seen = <String>{};

  static Future<void> start() async {
    try {
      final i = await PackageInfo.fromPlatform();
      _version = '${i.version.replaceAll('-dev', '')}+${i.buildNumber}';
    } catch (_) {}

    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details); // still printed while debugging
      record(details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack);
      return true;
    };
  }

  /// Saves one note. Safe to call anywhere; never throws.
  static void record(Object error, StackTrace? stack) {
    if (kDebugMode || _sent >= 5) return;
    final text = _cut(error.toString(), 1000);
    if (!_seen.add(text)) return;
    _sent++;
    final where = _cut(
      (stack?.toString() ?? '').split('\n').take(12).join('\n'),
      3000,
    );
    unawaited(
      _save(<String, Object>{
        'error': text,
        'where': where,
        'version': _version,
        'platform': defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
        'at': FieldValue.serverTimestamp(),
        // Firestore deletes the note by itself after 30 days (TTL policy).
        'expireAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 30)),
        ),
      }),
    );
  }

  static Future<void> _save(Map<String, Object> note) async {
    try {
      await FirebaseFirestore.instance.collection('errors').add(note);
    } catch (_) {
      // Offline or not signed in: nothing to do.
    }
  }

  static String _cut(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);
}
