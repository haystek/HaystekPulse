import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/employee.dart';
import 'device_id.dart';
import 'notification_service.dart';
import 'personal_code.dart';
import 'vault_service.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Only office emails can sign up (admins).
  static const officeDomain = '@haystek.com';

  // ---------------------------------------------------------------------
  // Employees: entry code + personal code (no email, no name, no password)
  // ---------------------------------------------------------------------
  //
  // How it works:
  // - HR mails one **entry code** to all employees. The app checks it by
  //   looking up `entry_codes/{SHA-256 of the code}` (the code itself is
  //   never stored).
  // - The app makes a random **personal code**: three words and a number,
  //   like river-tiger-mango-42 ([PersonalCode]). It becomes a hidden
  //   Firebase login:
  //     email    = slow hash of the code + "@code.haystekpulse.app"
  //     password = the code
  //   No mail is ever sent to that address. The same code always gives the
  //   same login, so it works on a new phone too.
  // - The history (vault) is locked with a key made from the personal code.
  // - One account per phone: `devices/{SHA-256 of the phone ID}`.

  /// The hidden login of a personal-code account ends with this.
  static const codeDomain = 'code.haystekpulse.app';

  /// Secure storage for the personal code on this phone. On iPhone this is
  /// the Keychain, which keeps it after the app is deleted, so a reinstall
  /// signs in by itself. "This device only": never copied to a new phone.
  static const FlutterSecureStorage _codeStore = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  static const String _codeKey = 'personal_code_v1';

  /// The personal code just typed or made. Used once to open the history,
  /// then cleared. Never saved in Firebase.
  String? pendingCode;

  /// A personal code made by [joinWithEntryCode]. Shown once on the
  /// "Save your personal code" screen, then cleared.
  String? newPersonalCode;

  /// The entry code just used. Kept in memory until the account record is
  /// saved ([finishCodeAccount]).
  String? pendingEntryCode;

  /// True if the signed-in account is a personal-code account.
  bool get isCodeAccount => isCodeEmail(_auth.currentUser?.email);

  static bool isCodeEmail(String? email) =>
      email != null && email.toLowerCase().endsWith('@$codeDomain');

  /// "hstlgn " -> "HSTLGN". Entry codes are checked in capital letters.
  static String normalizeEntryCode(String code) =>
      code.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

  /// The hidden login email for a personal code.
  static Future<String> codeEmail(String personalCode) =>
      PersonalCode.loginEmail(personalCode, codeDomain);

  /// Scrambled phone ID, the only form that is ever sent to Firebase.
  static Future<String> _deviceHash() async =>
      VaultService.sha256Hex('device:${await DeviceId.get()}');

  /// True if this is a valid employee entry code.
  Future<bool> isEntryCode(String code) async {
    final c = normalizeEntryCode(code);
    if (c.isEmpty) return false;
    final hash = VaultService.sha256Hex(c);
    final doc = await _db
        .collection('entry_codes')
        .doc(hash)
        .get(const GetOptions(source: Source.server));
    debugPrint('[Auth] entry code check: "$c" -> $hash -> found: ${doc.exists}');
    return doc.exists;
  }

  /// True if an account was already made on this phone.
  Future<bool> phoneHasAccount() async {
    final doc = await _db
        .collection('devices')
        .doc(await _deviceHash())
        .get(const GetOptions(source: Source.server));
    return doc.exists;
  }

  /// "Join with entry code": checks the code and the phone, then makes the
  /// hidden login with a new personal code. The account record is saved
  /// right after by [finishCodeAccount] (AuthGate calls it).
  Future<void> joinWithEntryCode(String entryCode) async {
    final entry = normalizeEntryCode(entryCode);
    if (!await isEntryCode(entry)) {
      throw FirebaseAuthException(code: 'entry-code-wrong');
    }
    if (await phoneHasAccount()) {
      throw FirebaseAuthException(code: 'device-has-account');
    }
    pendingEntryCode = entry;
    String? code;
    // A new code is almost never taken, but if it is, try another one.
    for (var tries = 0; tries < 3 && code == null; tries++) {
      final c = PersonalCode.generate();
      try {
        await _auth.createUserWithEmailAndPassword(
          email: await codeEmail(c),
          password: PersonalCode.password(c),
        );
        code = c;
      } on FirebaseAuthException catch (e) {
        if (e.code != 'email-already-in-use' || tries == 2) {
          pendingEntryCode = null;
          rethrow;
        }
      }
    }
    pendingCode = code;
    newPersonalCode = code;
    await _saveCodeOnPhone(code!);
  }

  /// Saves the account record of a new personal-code account, and marks
  /// this phone as used. Runs right after [joinWithEntryCode]. If the app
  /// was closed in between, the person types the entry code again.
  Future<void> finishCodeAccount([String? entryCode]) async {
    final user = _auth.currentUser;
    if (user == null || !isCodeEmail(user.email)) {
      throw FirebaseAuthException(code: 'no-current-user');
    }
    final entry = normalizeEntryCode(entryCode ?? pendingEntryCode ?? '');
    if (entry.isEmpty) throw FirebaseAuthException(code: 'entry-code-wrong');
    final ref = _db.collection('employees').doc(user.uid);
    final existing = await ref.get(const GetOptions(source: Source.server));
    if (!existing.exists) {
      try {
        await ref.set({
          'employeeId': '',
          'name': '',
          'type': 'e',
          'entryProof': VaultService.sha256Hex(entry),
          'mustChangePassword': false,
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          throw FirebaseAuthException(code: 'entry-code-wrong');
        }
        rethrow;
      }
    }
    pendingEntryCode = null;
    await _markPhoneUsed();
  }

  /// "I have my personal code": signs in on any phone. Never blocked by
  /// the phone check; it only marks this phone as used too.
  Future<void> signInWithPersonalCode(String personalCode) async {
    final n = PersonalCode.normalize(personalCode);
    if (!PersonalCode.looksValid(n)) {
      throw FirebaseAuthException(code: 'personal-code-wrong');
    }
    pendingCode = n;
    try {
      await _auth.signInWithEmailAndPassword(
        email: await codeEmail(n),
        password: PersonalCode.password(n),
      );
    } on FirebaseAuthException catch (e) {
      pendingCode = null;
      const wrong = [
        'invalid-credential',
        'user-not-found',
        'wrong-password',
        'invalid-email',
      ];
      if (wrong.contains(e.code)) {
        throw FirebaseAuthException(code: 'personal-code-wrong');
      }
      rethrow;
    }
    await _saveCodeOnPhone(n);
    unawaited(_markPhoneUsed());
  }

  /// App start with nobody signed in: if this phone still has the personal
  /// code (iPhone after a reinstall), sign in with it. True if it did.
  Future<bool> autoSignIn() async {
    if (_auth.currentUser != null) return false;
    final code = await savedCode();
    if (code == null) return false;
    try {
      await signInWithPersonalCode(code);
      return true;
    } catch (e) {
      debugPrint('[Auth] auto sign-in failed: $e');
      // A wrong saved code (e.g. the account was deleted): forget it.
      if (e is FirebaseAuthException && e.code == 'personal-code-wrong') {
        await _forgetCodeOnPhone();
      }
      return false;
    }
  }

  /// The personal code kept on this phone, or null.
  Future<String?> savedCode() async {
    try {
      final c = await _codeStore.read(key: _codeKey);
      return (c == null || c.isEmpty) ? null : c;
    } catch (_) {
      return null; // Not readable (e.g. Android after reinstall).
    }
  }

  Future<void> _saveCodeOnPhone(String code) async {
    try {
      await _codeStore.write(key: _codeKey, value: PersonalCode.normalize(code));
    } catch (e) {
      debugPrint('[Auth] could not keep the personal code: $e');
    }
  }

  Future<void> _forgetCodeOnPhone() async {
    try {
      await _codeStore.delete(key: _codeKey);
    } catch (_) {}
  }

  /// Marks this phone as used, so it can't make a second account. The
  /// record has only a time: no user ID, nothing that says who.
  Future<void> _markPhoneUsed() async {
    try {
      final ref = _db.collection('devices').doc(await _deviceHash());
      final doc = await ref.get();
      if (doc.exists) return;
      await ref.set({'at': FieldValue.serverTimestamp()});
    } catch (e) {
      debugPrint('[Auth] could not mark this phone: $e');
    }
  }

  /// Name typed on the sign-up form. Kept here until the email is
  /// verified, then saved to `employees`.
  String? pendingName;

  /// Admin or Employee, and the admin code, from the sign-up form.
  /// Kept only in memory until the profile is saved.
  bool? pendingAdmin;
  String? pendingAdminCode;

  /// The password just typed (sign in, sign up, change). Used once to
  /// open the locked history, then cleared. Never saved.
  String? pendingPassword;

  Stream<User?> get authChanges => _auth.authStateChanges();

  /// Like [authChanges], but also fires when the user is reloaded, so the
  /// app notices at once when the email has been verified.
  Stream<User?> get userChanges => _auth.userChanges();

  Future<void> signIn(String email, String password) async {
    pendingPassword = password;
    await _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
  }

  /// Set by [startOver]: the login screen opens on "Create account" with
  /// the name and email filled in, instead of on "Sign in".
  bool openSignUp = false;
  String? signUpEmail;
  String? signUpName;

  /// Creates the login and sends the verification email. The `employees`
  /// record is made after the email is verified ([createMyProfile]).
  ///
  /// If this email already signed up but never clicked the link, and the
  /// same password is typed, it simply carries on: a new link is sent.
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
    bool admin = false,
    String adminCode = '',
  }) async {
    final address = email.trim().toLowerCase();
    if (!address.endsWith(officeDomain)) {
      throw FirebaseAuthException(code: 'not-office-email');
    }
    // Admin: check the code first, so no account (and no email) is made
    // with a wrong code.
    if (admin && !await isAdminCode(adminCode)) {
      throw FirebaseAuthException(code: 'admin-code-wrong');
    }
    pendingName = name.trim();
    pendingAdmin = admin;
    pendingAdminCode = admin ? adminCode.trim() : null;
    pendingPassword = password;
    User? user;
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: address,
        password: password,
      );
      user = cred.user;
    } on FirebaseAuthException catch (e) {
      if (e.code != 'email-already-in-use') rethrow;
      // Maybe an earlier sign-up that was never verified: try to carry on.
      try {
        final cred = await _auth.signInWithEmailAndPassword(
          email: address,
          password: password,
        );
        user = cred.user;
      } on FirebaseAuthException {
        throw FirebaseAuthException(code: 'email-already-in-use');
      }
      if (user != null && user.emailVerified) {
        // A real, finished account: just signed in, which is fine too.
        return;
      }
    }
    await user?.updateDisplayName(pendingName);
    await user?.sendEmailVerification();
  }

  /// "Wrong email? Start over": removes the unverified login, so the email
  /// can be used again, and goes back to "Create account".
  Future<void> startOver() async {
    final user = _auth.currentUser;
    signUpName = pendingName ?? user?.displayName;
    signUpEmail = user?.email;
    if (user != null && !user.emailVerified) {
      try {
        await user.delete();
      } catch (_) {
        // Could not delete (e.g. signed in long ago). Sign out anyway.
      }
    }
    openSignUp = true;
    await signOut();
  }

  /// Checks the login still exists. If it was deleted or disabled in the
  /// Firebase console, signs out (the phone would otherwise keep using it
  /// for up to an hour). Returns false when signed out.
  Future<bool> stillValid() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      await user.reload();
      return _auth.currentUser != null;
    } on FirebaseAuthException catch (e) {
      const gone = [
        'user-not-found',
        'user-disabled',
        'user-token-expired',
        'invalid-user-token',
      ];
      if (gone.contains(e.code)) {
        await signOut();
        return false;
      }
      return true; // e.g. no internet: keep going
    }
  }

  /// Sends the verification email again.
  Future<void> resendVerification() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  /// Checks with Firebase whether the email is verified now. When it is,
  /// the login is refreshed so the database also knows.
  Future<bool> checkVerified() async {
    if (!await stillValid()) return false;
    final fresh = _auth.currentUser;
    if (fresh == null || !fresh.emailVerified) return false;
    await fresh.getIdToken(true);
    return true;
  }

  /// Saves the signed-in person to `employees` (no employee ID: sign-up
  /// does not ask for it).
  ///
  /// Admin: only with the right admin code. The app sends a SHA-256 of
  /// the code, and the database rules check that `admin_codes/{that}`
  /// exists. So nobody can make themselves admin.
  Future<void> createMyProfile({
    required String name,
    bool admin = false,
    String adminCode = '',
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw FirebaseAuthException(code: 'no-current-user');
    }
    // Fresh login token first, so the database sees "email verified".
    await user.getIdToken(true);
    final email = user.email!.toLowerCase();
    final code = adminCode.trim();
    if (admin && code.isEmpty) {
      throw FirebaseAuthException(code: 'admin-code-wrong');
    }
    try {
      await _db.collection('employees').doc(user.uid).set({
        'employeeId': '',
        'name': name.trim(),
        'type': admin ? 'm' : 'e',
        if (admin) 'adminProof': VaultService.sha256Hex(code),
        'mustChangePassword': false,
        'active': true,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      if (admin && e.code == 'permission-denied') {
        throw FirebaseAuthException(code: 'admin-code-wrong');
      }
      rethrow;
    }
    pendingName = null;
    pendingAdmin = null;
    pendingAdminCode = null;
  }

  /// True if this is a valid admin code. The app looks up
  /// `admin_codes/{SHA-256 of the code}`: it exists only for the right
  /// code. Nobody can list the codes, and the code itself is never stored.
  Future<bool> isAdminCode(String code) async {
    final c = code.trim();
    if (c.isEmpty) return false;
    final doc = await _db
        .collection('admin_codes')
        .doc(VaultService.sha256Hex(c))
        .get(const GetOptions(source: Source.server));
    return doc.exists;
  }

  /// Passwords that are too easy to guess. The history is locked with
  /// the password, so it must not be one of these.
  static bool isEasyPassword(String password, {String name = '', String email = ''}) {
    final p = password.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    const easy = [
      'password', 'password1', 'password12', 'password123', 'welcome',
      'welcome1', 'welcome12', 'welcome123', 'haystek', 'haystek1',
      'haystek12', 'haystek123', 'haystek2026', 'qwerty', 'qwerty123',
      'admin', 'admin123', 'abc123', 'abcd1234', 'iloveyou', 'letmein',
      '12345678', '123456789', '1234567890', '11111111', '00000000',
      'india123', 'test1234',
    ];
    if (easy.contains(p)) return true;
    if (RegExp(r'^(.)\1+$').hasMatch(p)) return true; // aaaaaaaa
    final first = name.trim().split(RegExp(r'\s+')).first.toLowerCase();
    if (first.length >= 3 &&
        p.replaceAll(RegExp(r'[0-9]'), '') == first) {
      return true; // shiva123, Shiva@2026
    }
    final user = email.split('@').first.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (user.length >= 3 && p.startsWith(user)) return true;
    return false;
  }

  /// Firebase emails a reset link to this address if it belongs to a user.
  Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
  }

  Stream<Employee?> employeeStream(String uid) {
    return _db
        .collection('employees')
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? Employee.fromDoc(doc) : null);
  }

  /// Sets the new password, then clears the "must change password" flag.
  Future<void> changePassword(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: 'no-current-user');
    }
    await user.updatePassword(newPassword);
    pendingPassword = newPassword;
    await _db
        .collection('employees')
        .doc(user.uid)
        .update({'mustChangePassword': false});
  }

  /// Signs out at once. The notification cleanup (leaving this phone's
  /// groups) runs in the background, so the login screen shows straight
  /// away. A new sign-in waits for that cleanup to finish.
  Future<void> signOut() async {
    pendingName = null;
    pendingAdmin = null;
    pendingAdminCode = null;
    pendingPassword = null;
    pendingCode = null;
    newPersonalCode = null;
    pendingEntryCode = null;
    // Personal-code account: forget the code on this phone, so the next
    // person can't get in. Signing in again needs the code.
    if (isCodeAccount) await _forgetCodeOnPhone();
    unawaited(NotificationService.instance.stop());
    // Forget the history key on this phone, so the next person sees nothing.
    await VaultService.instance.close();
    await _auth.signOut();
  }

  /// Checks the password with Firebase (used before opening the history
  /// or making a new backup code). Throws if it is wrong.
  Future<void> checkPassword(String password) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw FirebaseAuthException(code: 'no-current-user');
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: user.email!, password: password),
    );
  }

  /// Shown when the email or password is wrong. The sign-in screen adds
  /// "Create account" and "Reset password" buttons under it.
  static const String wrongLogin = 'Wrong email or password';

  /// No account with this email (only when Firebase tells us).
  static const String noAccount = 'No account with this email';

  /// The email is right, the password is not (only when Firebase tells us).
  static const String wrongPassword = 'Wrong password';

  /// Turns a Firebase error code into a message an employee can understand.
  static String messageFor(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        // With "Email enumeration protection" ON in Firebase, both cases
        // come as 'invalid-credential' (Firebase doesn't say which).
        // With it OFF, the two cases below come separately.
        case 'invalid-credential':
          return wrongLogin;
        case 'user-not-found':
          return noAccount;
        case 'wrong-password':
          return wrongPassword;
        case 'invalid-email':
          return 'Please enter a valid email address.';
        case 'not-office-email':
          return 'Please use your $officeDomain office email.';
        case 'email-already-in-use':
          return 'An account with this email already exists. Please sign in, '
              'or use Reset password.';
        case 'user-disabled':
          return 'This account has been disabled. Please contact your admin.';
        case 'too-many-requests':
          return 'Too many attempts. Please try again after some time.';
        case 'network-request-failed':
          return 'No internet connection. Please check and try again.';
        case 'weak-password':
        case 'password-does-not-meet-requirements':
          return 'Please use at least 8 characters for your password.';
        case 'requires-recent-login':
          return 'Please sign out, sign in again, and then change your password.';
        case 'vault-not-updated':
          return 'Your password was changed, but your history lock could '
              'not be updated (no internet?). Keep your backup code: you '
              'may need it next time you sign in.';
        case 'admin-code-wrong':
          return 'The admin entry code is not correct. Please check the '
              'mail from HR.';
        case 'entry-code-wrong':
          return 'This entry code is not correct. Please check the mail '
              'from HR.';
        case 'device-has-account':
          return 'This phone already has an account. Please sign in with '
              'your personal code.';
        case 'personal-code-wrong':
          return 'This personal code is not correct. It looks like '
              'river-tiger-mango-42. Please check it and try again.';
      }
    }
    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'Your account could not be set up. Please check your code, '
          'or contact your admin.';
    }
    if (error is FirebaseException && error.code == 'unavailable') {
      return 'No internet connection. Please check and try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  /// Change password from Profile. Firebase asks for the current
  /// password first, for safety.
  Future<void> changeMyPassword(String current, String newPassword) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw FirebaseAuthException(code: 'no-current-user');
    }
    final credential = EmailAuthProvider.credential(
      email: user.email!,
      password: current,
    );
    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(newPassword);
    // Lock the history with the new password too, so nothing is lost.
    try {
      await VaultService.instance.rewrapPassword(newPassword);
    } catch (_) {
      throw FirebaseAuthException(code: 'vault-not-updated');
    }
  }
}
