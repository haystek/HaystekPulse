import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/employee.dart';
import 'notification_service.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Only office emails can sign up.
  static const officeDomain = '@haystek.com';

  /// Name typed on the sign-up form. Kept here until the email is
  /// verified, then saved to `employees`.
  String? pendingName;

  Stream<User?> get authChanges => _auth.authStateChanges();

  /// Like [authChanges], but also fires when the user is reloaded, so the
  /// app notices at once when the email has been verified.
  Stream<User?> get userChanges => _auth.userChanges();

  Future<void> signIn(String email, String password) async {
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
  }) async {
    final address = email.trim().toLowerCase();
    if (!address.endsWith(officeDomain)) {
      throw FirebaseAuthException(code: 'not-office-email');
    }
    pendingName = name.trim();
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
  /// does not ask for it). They become management
  /// only if their email is in the `management_emails` list. The database
  /// rules check this too, so nobody can make themselves management.
  Future<void> createMyProfile({required String name}) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw FirebaseAuthException(code: 'no-current-user');
    }
    // Fresh login token first, so the database sees "email verified".
    // (The screen can move on a moment before the token is refreshed.)
    await user.getIdToken(true);
    final email = user.email!.toLowerCase();
    final isManagement =
        (await _db.collection('management_emails').doc(email).get()).exists;
    await _db.collection('employees').doc(user.uid).set({
      'employeeId': '',
      'name': name.trim(),
      'type': isManagement ? 'm' : 'e',
      'mustChangePassword': false,
      'active': true,
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
    });
    pendingName = null;
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
    unawaited(NotificationService.instance.stop());
    await _auth.signOut();
  }

  /// Turns a Firebase error code into a message an employee can understand.
  static String messageFor(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-credential':
        case 'wrong-password':
        case 'user-not-found':
          return 'Email or password is incorrect.';
        case 'invalid-email':
          return 'Please enter a valid email address.';
        case 'not-office-email':
          return 'Please use your $officeDomain office email.';
        case 'email-already-in-use':
          return 'An account with this email already exists. Please sign in, '
              'or use Reset password.';
        case 'user-disabled':
          return 'This account has been disabled. Please contact management.';
        case 'too-many-requests':
          return 'Too many attempts. Please try again after some time.';
        case 'network-request-failed':
          return 'No internet connection. Please check and try again.';
        case 'weak-password':
        case 'password-does-not-meet-requirements':
          return 'Please use at least 8 characters for your password.';
        case 'requires-recent-login':
          return 'Please sign out, sign in again, and then change your password.';
      }
    }
    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'Your account could not be set up. Please use your '
          '$officeDomain email, or contact management.';
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
  }
}