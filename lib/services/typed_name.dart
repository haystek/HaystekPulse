import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/employee.dart';

/// "Show my name" for employees who joined with an entry code: they have
/// no name in the app, so they type one when they want to show it.
///
/// - The name is sent only with that one message (suggestion, Weekly Pulse
///   comment or broadcast comment). It is never saved on the account.
/// - The app remembers the last typed name on this phone only, so it is
///   filled in next time.
/// - There is no email, so the name can't be checked. Admin sees it as
///   "name typed by sender".
class TypedName {
  TypedName._();

  static const FlutterSecureStorage _store = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  static const String _key = 'typed_name_v1';

  /// True if this person has no name in the app, so they type it.
  static bool needed(Employee e) => e.name.trim().isEmpty;

  /// The name typed last time on this phone, or ''.
  static Future<String> load() async {
    try {
      return (await _store.read(key: _key)) ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Remembers the name on this phone only.
  static Future<void> save(String name) async {
    try {
      await _store.write(key: _key, value: name.trim());
    } catch (_) {}
  }

  /// Null if fine, else a short message.
  static String? check(String? value) {
    final t = (value ?? '').trim();
    if (t.length < 2) return 'Type your name, or keep it hidden';
    if (t.length > 60) return 'Please use a shorter name';
    return null;
  }

  /// Shown to admin under a typed name.
  static const String adminNote = 'Name typed by sender';
}
