import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/employee.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import 'change_password_screen.dart';
import 'employee_home_screen.dart';
import 'login_screen.dart';
import 'management_home_screen.dart';

/// Decides which screen to show:
/// not signed in -> Login
/// first login   -> Change password
/// type 'm'      -> Management home
/// type 'e'      -> Employee home
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;

    return StreamBuilder<User?>(
      stream: auth.authChanges,
      builder: (context, userSnap) {
        if (userSnap.connectionState == ConnectionState.waiting) {
          return const _Loading();
        }
        final user = userSnap.data;
        if (user == null) {
          return const LoginScreen();
        }

        return StreamBuilder<Employee?>(
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
              return const _Problem(
                message:
                    'Your account is not set up yet. Please contact management.',
              );
            }
            if (!employee.active) {
              return const _Problem(
                message:
                    'This account is no longer active. Please contact management.',
              );
            }
            if (employee.mustChangePassword) {
              return ChangePasswordScreen(employee: employee);
            }
            // Ask for permission and join the right notification groups.
            NotificationService.instance.start(employee);
            return employee.isManagement
                ? ManagementHomeScreen(employee: employee)
                : EmployeeHomeScreen(employee: employee);
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
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
