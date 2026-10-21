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

  Stream<User?> get authChanges => _auth.authStateChanges();

  Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
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
        case 'user-disabled':
          return 'This account has been disabled. Please contact management.';
        case 'too-many-requests':
          return 'Too many attempts. Please try again after some time.';
        case 'network-request-failed':
          return 'No internet connection. Please check and try again.';
        case 'weak-password':
          return 'This password is too weak. Please choose a stronger one.';
        case 'requires-recent-login':
          return 'Please sign out, sign in again, and then change your password.';
      }
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
