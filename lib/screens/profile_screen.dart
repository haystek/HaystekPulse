import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/employee.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'help_screen.dart';
import 'vault_screens.dart';

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
/// Asks "Sign out?" and signs out only after the dialog has closed.
Future<void> confirmSignOut(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      title: Text(
        'Sign out?',
        style: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
      content: Text(
        AuthService.instance.isCodeAccount
            ? 'You’ll need your personal code to sign in again. Make sure '
                'you saved it.'
            : 'You’ll need your email and password to sign in again.',
        style: GoogleFonts.inter(
          fontSize: 15,
          height: 1.45,
          color: AppColors.muted,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.muted,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            textStyle: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          child: const Text('Cancel'),
        ),
        FilledButton(
          // Only close the dialog here. Signing out happens after it.
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.blue,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            shape: const StadiumBorder(),
            textStyle: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  // Close every screen above home, then sign out.
  Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
  await AuthService.instance.signOut();
}
/// The signed-in person's details, change password and sign out.
/// Works for admins and employees.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.employee});

  final Employee employee;

  @override
  Widget build(BuildContext context) {
    final name = employee.name.trim();
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final role = employee.isManagement ? 'Admin' : 'Employee';
    // Joined with an entry code: no email, no name, no password.
    final codeAccount = AuthService.isCodeEmail(email);

    return _inter(
      context,
      Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          leadingWidth: 68,
          leading: const AppBackButton(),
          // No title on the left: the name sits on the right in a pill.
          title: const SizedBox.shrink(),
          actions: const [
            _TitlePill('Profile', icon: Icons.person_outline),
          ],
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
                          name.isEmpty
                              ? (codeAccount ? 'Anonymous' : 'No name')
                              : name,
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
                      children: codeAccount
                          ? const [
                              _InfoRow(
                                icon: Icons.visibility_off_outlined,
                                label: 'Account',
                                value: 'Anonymous · no email, no name',
                              ),
                            ]
                          : [
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

                  // Personal-code accounts: see the code again.
                  if (codeAccount)
                    _Tile(
                      icon: Icons.key_outlined,
                      title: 'My personal code',
                      subtitle: 'You need it on a new phone',
                      onTap: () => _showPersonalCode(context),
                    ),
                  // Change password (email accounts only).
                  if (!codeAccount)
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
                  // Backup code (older email employee accounts).
                  if (!employee.isManagement && !codeAccount) ...[
                    const SizedBox(height: 12),
                    Material(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: const BorderSide(color: Color(0xFFE6EBF4)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(18, 6, 12, 6),
                        leading: const Icon(Icons.key_outlined,
                            color: AppColors.blue),
                        title: const Text(
                          'Backup code',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: const Text(
                          'Make a new code if you lost yours',
                          style: TextStyle(fontSize: 13, color: AppColors.muted),
                        ),
                        trailing: const Icon(Icons.chevron_right,
                            color: AppColors.muted),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const NewBackupCodeScreen(),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Help & Privacy: questions and answers, who sees what.
                  Material(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: const BorderSide(color: Color(0xFFE6EBF4)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(18, 6, 12, 6),
                      leading: const Icon(Icons.shield_outlined,
                          color: AppColors.blue),
                      title: const Text(
                        'Help & Privacy',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right,
                          color: AppColors.muted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const HelpScreen(),
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
  String? _error;

  /// Each box has its own eye button, so one tap shows only that box.
  bool _hideCurrent = true;
  bool _hideNew = true;
  bool _hideConfirm = true;

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
    InputDecoration field(
        String label, {
          String? helper,
          required bool hidden,
          required VoidCallback onEye,
        }) =>
        InputDecoration(
          labelText: label,
          helperText: helper,
          suffixIcon: IconButton(
            tooltip: hidden ? 'Show password' : 'Hide password',
            icon: Icon(
              hidden
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 20,
              color: const Color(0xFF8E97AB),
            ),
            onPressed: onEye,
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
          // No title on the left: the name sits on the right in a pill.
          title: const SizedBox.shrink(),
          actions: const [
            _TitlePill('Change password', icon: Icons.lock_outline),
          ],
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
                      obscureText: _hideCurrent,
                      textInputAction: TextInputAction.next,
                      decoration: field(
                        'Current password',
                        hidden: _hideCurrent,
                        onEye: () =>
                            setState(() => _hideCurrent = !_hideCurrent),
                      ),
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Enter your current password'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _newPassword,
                      obscureText: _hideNew,
                      textInputAction: TextInputAction.next,
                      decoration: field(
                        'New password',
                        helper: 'At least 8 characters',
                        hidden: _hideNew,
                        onEye: () => setState(() => _hideNew = !_hideNew),
                      ),
                      validator: (v) {
                        if (v == null || v.length < 8) {
                          return 'Use at least 8 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirm,
                      obscureText: _hideConfirm,
                      onFieldSubmitted: (_) => _save(),
                      decoration: field(
                        'Confirm new password',
                        hidden: _hideConfirm,
                        onEye: () =>
                            setState(() => _hideConfirm = !_hideConfirm),
                      ),
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
/// Screen name on the right of the AppBar: a rounded pill with a blue
/// icon circle (same as the other screens).
class _TitlePill extends StatelessWidget {
  const _TitlePill(this.text, {required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Container(
        height: 42,
        padding: const EdgeInsets.fromLTRB(5, 5, 16, 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(21),
          border: Border.all(color: AppColors.blue.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: AppColors.blue,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 17, color: Colors.white),
            ),
            const SizedBox(width: 9),
            Text(
              text,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: AppColors.ink,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Profile -> My personal code: shows the code kept on this phone.
Future<void> _showPersonalCode(BuildContext context) async {
  final code = await AuthService.instance.savedCode();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        'My personal code',
        style: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (code == null)
            Text(
              'Your code is not saved on this phone. Use the code you saved '
              'when you joined.',
              style: GoogleFonts.inter(
                fontSize: 15,
                height: 1.45,
                color: AppColors.muted,
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F8FB),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE3E8F1), width: 1.5),
              ),
              child: SelectableText(
                code,
                textAlign: TextAlign.center,
                style: GoogleFonts.robotoMono(
                  fontSize: 18,
                  letterSpacing: 1.2,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Keep it safe and don’t share it. Anyone with this code can '
              'open your account.',
              style: GoogleFonts.inter(
                fontSize: 13.5,
                height: 1.45,
                color: AppColors.muted,
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (code != null)
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Personal code copied')),
              );
            },
            child: const Text('Copy'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(c).pop(),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.blue,
            shape: const StadiumBorder(),
          ),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

/// One row button on the Profile screen.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE6EBF4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(18, 6, 12, 6),
        leading: Icon(icon, color: AppColors.blue),
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
        trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
        onTap: onTap,
      ),
    );
  }
}
