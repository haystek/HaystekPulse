import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// HR/Ops phone: Admin + Employee on the same phone (admin first).
///
/// Kept ONLY on this phone, in the Keychain (iPhone) / Keystore (Android):
/// which admin uses this phone, and (after the first "Switch to Admin")
/// the admin password, so switching needs no typing. Nothing about this is
/// saved in Firebase, so nobody can link the anonymous employee account to
/// the admin.
class DualRole {
  DualRole._();

  static const FlutterSecureStorage _store = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  static const String _emailKey = 'dual_admin_email_v1';
  static const String _passKey = 'dual_admin_pass_v1';
  static const String _uidKey = 'dual_admin_uid_v1';

  /// Private notification group of the admin on this phone. The admin's
  /// own broadcast skips phones in it.
  static String meTopic(String adminUid) => 'me_$adminUid';

  /// True when this phone is an HR/Ops phone.
  static Future<bool> isOn() async => (await adminLogin()) != null;

  /// The admin on this phone, or null. [password] is null until the first
  /// "Switch to Admin".
  static Future<({String email, String? password, String uid})?>
  adminLogin() async {
    try {
      final email = await _store.read(key: _emailKey);
      final uid = await _store.read(key: _uidKey);
      if (email == null || uid == null || email.isEmpty || uid.isEmpty) {
        return null;
      }
      final pass = await _store.read(key: _passKey);
      return (
        email: email,
        password: (pass == null || pass.isEmpty) ? null : pass,
        uid: uid,
      );
    } catch (_) {
      return null;
    }
  }

  /// Marks this phone as the admin's HR/Ops phone. [password] is kept too
  /// when given.
  static Future<void> save({
    required String email,
    String? password,
    required String uid,
  }) async {
    await _store.write(key: _emailKey, value: email.trim().toLowerCase());
    await _store.write(key: _uidKey, value: uid);
    if (password != null && password.isNotEmpty) {
      await _store.write(key: _passKey, value: password);
    }
  }

  /// The saved password no longer works (changed elsewhere).
  static Future<void> forgetPassword() async {
    try {
      await _store.delete(key: _passKey);
    } catch (_) {}
  }

  /// Removes everything about the admin from this phone.
  static Future<void> clear() async {
    try {
      await _store.delete(key: _emailKey);
      await _store.delete(key: _passKey);
      await _store.delete(key: _uidKey);
    } catch (e) {
      debugPrint('[DualRole] could not clear: $e');
    }
  }
}
