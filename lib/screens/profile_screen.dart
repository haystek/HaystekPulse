import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/employee.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/heartbeat_monitor.dart';
import '../widgets/ui.dart';

/// Inter font for everything on these screens and dialogs
/// (same as the home screen).
Widget _inter(BuildContext context, Widget child) {
  final t = Theme.of(context);
  return Theme(
    data: t.copyWith(textTheme: GoogleFonts.interTextTheme(t.textTheme)),
    child: child,
  );
}

/// Inter for titles that set their own style.
TextStyle _title(double size, {Color color = AppColors.ink}) =>
    GoogleFonts.inter(
      fontSize: size,
      fontWeight: FontWeight.w800,
      color: color,
      letterSpacing: -0.3,
    );

/// Asks "Sign out?", then shows "Signing out…" while it happens.
/// Used by the account menu and the Profile screen.
Future<void> confirmSignOut(BuildContext context) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => _inter(
      dialogContext,
      AlertDialog(
        title: Text('Sign out?', style: _title(20)),
        content: const Text('You will need your email and password to sign '
            'in again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    ),
  );
  if (yes != true || !context.mounted) return;

  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _inter(
      dialogContext,
      PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The same moving heartbeat as the sign-in screen.
                const SizedBox(
                  height: 70,
                  width: double.infinity,
                  child: HeartbeatMonitor(
                    duration: Duration(milliseconds: 1600),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Signing out Please wait ...', style: _title(18)),
                const SizedBox(height: 4),
                const Text(
                  'See you next week!',
                  style: TextStyle(color: AppColors.muted, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  // Wait at least a moment, so people see it happen.
  await Future.wait([
    AuthService.instance.signOut().catchError((_) {}),
    Future<void>.delayed(const Duration(milliseconds: 1600)),
  ]);

  // Close the "Signing out…" box and any open screens, so the sign-in
  // screen shows.
  nav.popUntil((route) => route.isFirst);
}

/// The signed-in person's details, change password and sign out.
/// Works for management and employees.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.employee});

  final Employee employee;

  @override
  Widget build(BuildContext context) {
    final name = employee.name.trim();
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final role = employee.isManagement ? 'Management' : 'Employee';

    return _inter(
      context,
      Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          leadingWidth: 68,
          leading: const AppBackButton(),
          titleSpacing: 4,
          centerTitle: false,
          title: Text('Profile', style: _title(22)),
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  // Name card.
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                    decoration: _card(),
                    child: Column(
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: AppColors.blue,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            initial,
                            style: _title(30, color: Colors.white),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          name.isEmpty ? 'No name' : name,
                          textAlign: TextAlign.center,
                          style: _title(22),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.blueTint,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            role,
                            style: const TextStyle(
                              color: AppColors.blueDeep,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Details.
                  Container(
                    decoration: _card(),
                    child: Column(
                      children: [
                        _InfoRow(
                          icon: Icons.badge_outlined,
                          label: 'Employee ID',
                          value: employee.employeeId.isEmpty
                              ? '—'
                              : employee.employeeId,
                        ),
                        const Divider(height: 1, color: Color(0xFFEEF1F6)),
                        _InfoRow(
                          icon: Icons.mail_outline,
                          label: 'Email',
                          value: email.isEmpty ? '—' : email,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Change password.
                  Material(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: const BorderSide(color: Color(0xFFE6EBF4)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(18, 6, 12, 6),
                      leading: const Icon(Icons.lock_outline,
                          color: AppColors.blue),
                      title: const Text(
                        'Change password',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right,
                          color: AppColors.muted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ChangeMyPasswordScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Sign out.
                  OutlinedButton.icon(
                    onPressed: () => confirmSignOut(context),
                    icon: const Icon(Icons.logout, size: 20),
                    label: const Text('Sign out'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      foregroundColor: const Color(0xFFC0392B),
                      side: const BorderSide(
                        color: Color(0xFFF1C9C2),
                        width: 1.5,
                      ),
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

BoxDecoration _card() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: const Color(0xFFE6EBF4)),
  boxShadow: const [
    BoxShadow(
      color: Color(0x0F0E1A3A),
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ],
);

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Row(
        children: [
          Icon(icon, color: AppColors.muted, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Change password from the Profile screen: the current password, then
/// the new one twice.
class ChangeMyPasswordScreen extends StatefulWidget {
  const ChangeMyPasswordScreen({super.key});

  @override
  State<ChangeMyPasswordScreen> createState() => _ChangeMyPasswordScreenState();
}

class _ChangeMyPasswordScreenState extends State<ChangeMyPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _newPassword.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.changeMyPassword(
        _current.text,
        _newPassword.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your password has been changed.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      final wrong = e is FirebaseAuthException &&
          (e.code == 'wrong-password' || e.code == 'invalid-credential');
      setState(() => _error = wrong
          ? 'Your current password is not correct.'
          : AuthService.messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration field(String label, {String? helper}) => InputDecoration(
      labelText: label,
      helperText: helper,
      suffixIcon: IconButton(
        icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
        onPressed: () => setState(() => _hide = !_hide),
      ),
    );

    return _inter(
      context,
      Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          leadingWidth: 68,
          leading: const AppBackButton(),
          titleSpacing: 4,
          centerTitle: false,
          title: Text('Change password', style: _title(22)),
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  children: [
                    TextFormField(
                      controller: _current,
                      obscureText: _hide,
                      textInputAction: TextInputAction.next,
                      decoration: field('Current password'),
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Enter your current password'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _newPassword,
                      obscureText: _hide,
                      textInputAction: TextInputAction.next,
                      decoration:
                      field('New password', helper: 'At least 8 characters'),
                      validator: (v) => (v == null || v.length < 8)
                          ? 'Use at least 8 characters'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirm,
                      obscureText: _hide,
                      onFieldSubmitted: (_) => _save(),
                      decoration: field('Confirm new password'),
                      validator: (v) => v != _newPassword.text
                          ? 'The two passwords do not match'
                          : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                      ),
                      child: _busy
                          ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : const Text('Save new password'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}