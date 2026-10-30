import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/employee.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import 'change_password_screen.dart';
import 'intro_screen.dart';
import 'login_screen.dart';
import 'management_home_screen.dart';
import 'vault_screens.dart';
import 'verify_email_screen.dart';

/// Decides which screen to show:
/// not signed in        -> Login (also Create account)
/// email not verified   -> Check your email
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
        if (!user.emailVerified) {
          return VerifyEmailScreen(email: user.email ?? '');
        }

        return StreamBuilder<Employee?>(
          key: ValueKey(user.uid),
          stream: auth.employeeStream(user.uid),
          builder: (context, empSnap) {
            if (empSnap.hasError) {
              return const _Problem(
                message: 'Could not load your profile. Please try again.',
              );
            }
            if (empSnap.connectionState == ConnectionState.waiting) {
              return const _Loading();
            }
            final employee = empSnap.data;
            if (employee == null) {
              // Signed up and verified, but not saved yet.
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
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: AppColors.blue,
          ),
        ),
      ),
    );
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
