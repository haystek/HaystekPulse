import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/employee.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../widgets/pulse_loading.dart';
import 'change_password_screen.dart';
import 'intro_screen.dart';
import 'login_screen.dart';
import 'management_home_screen.dart';
import 'vault_screens.dart';
import 'verify_email_screen.dart';

/// Decides which screen to show:
/// not signed in        -> Welcome: join with entry code, personal code,
///                         or admin sign in
/// email not verified   -> Check your email (admins only; personal-code
///                         accounts have no email)
/// no employee record   -> Finish your profile (after sign-up)
/// first login          -> Change password
/// type 'm'             -> Admin home
/// type 'e'             -> open the locked history, then Employee home
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  /// The login already checked, so the check runs once per sign-in.
  static String? _checkedUid;

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;

    return StreamBuilder<User?>(
      // userChanges also fires after a reload, so the app moves on by
      // itself once the email is verified.
      stream: auth.userChanges,
      builder: (context, userSnap) {
        if (userSnap.connectionState == ConnectionState.waiting) {
          return const _Loading();
        }
        final user = userSnap.data;
        if (user == null) {
          _checkedUid = null;
          // First time on this phone: the short intro, then sign in.
          return const IntroGate(child: LoginScreen());
        }
        // Once per login: sign out if it was deleted in the console.
        if (_checkedUid != user.uid) {
          _checkedUid = user.uid;
          auth.stillValid();
        }
        final codeAccount = AuthService.isCodeEmail(user.email);
        if (!codeAccount && !user.emailVerified) {
          return VerifyEmailScreen(email: user.email ?? '');
        }

        final gate = StreamBuilder<Employee?>(
          key: ValueKey(user.uid),
          stream: auth.employeeStream(user.uid),
          builder: (context, empSnap) {
            if (empSnap.hasError) {
              // The login is no longer valid (account deleted, or an old
              // sign-in left on this phone): sign out by itself and show
              // the start screen, instead of a "Sign out" screen.
              final e = empSnap.error;
              if (e is FirebaseException && e.code == 'permission-denied') {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (FirebaseAuth.instance.currentUser?.uid == user.uid) {
                    auth.signOut();
                  }
                });
                return const _Loading();
              }
              return const _Problem(
                message: 'Could not load your profile. Please try again.',
              );
            }
            if (empSnap.connectionState == ConnectionState.waiting) {
              return const _Loading();
            }
            final employee = empSnap.data;
            if (employee == null) {
              // Just joined with an entry code: save the account record.
              if (codeAccount) return const CodeFinishScreen();
              // Admin signed up and verified, but not saved yet.
              return const FinishProfileScreen();
            }
            if (!employee.active) {
              return const _Problem(
                message:
                    'This account is no longer active. Please contact your admin.',
              );
            }
            if (employee.mustChangePassword) {
              return ChangePasswordScreen(employee: employee);
            }
            if (employee.isManagement) {
              // Ask for permission and join the admin notification group.
              NotificationService.instance.start(employee);
              return ManagementHomeScreen(employee: employee);
            }
            // Employees: open the locked history first. It starts the
            // notifications once the history is open.
            return VaultGate(
              key: ValueKey('vault-${employee.uid}'),
              employee: employee,
            );
          },
        );
        // Personal-code accounts: one phone at a time. If the code is used
        // on another phone, this one signs out by itself.
        if (!codeAccount) return gate;
        return _MoveGuard(
          key: ValueKey('move-${user.uid}'),
          uid: user.uid,
          child: gate,
        );
      },
    );
  }
}

/// Watches which phone the account is on. If another phone took it, this
/// phone is freed and signed out ("Your account moved to another phone").
class _MoveGuard extends StatefulWidget {
  const _MoveGuard({super.key, required this.uid, required this.child});

  final String uid;
  final Widget child;

  @override
  State<_MoveGuard> createState() => _MoveGuardState();
}

class _MoveGuardState extends State<_MoveGuard> {
  StreamSubscription<Object?>? _sub;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _sub = AuthService.instance.watchMove(widget.uid, _moved);
  }

  Future<void> _moved() async {
    if (_leaving || !mounted) return;
    setState(() => _leaving = true);
    // Close any open screens, then sign out. The sign-in screen shows
    // "Your account moved to another phone".
    Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
    await AuthService.instance.leaveMovedAccount();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_leaving) return const _Loading();
    return widget.child;
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const PulseLoadingScreen();
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: AuthService.instance.signOut,
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
