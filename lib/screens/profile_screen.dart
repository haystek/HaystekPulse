import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/employee.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'delete_account_screen.dart';
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
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    // Joined with an entry code: no email, no name, no password.
    final codeAccount = AuthService.isCodeEmail(email);
    // Employees with a personal code: their own privacy-first profile.
    if (codeAccount) return _inter(context, const _CodeProfile());
    // Admins (and older email accounts): picture on top, name, settings.
    return _inter(context, _AdminProfile(employee: employee, email: email));
  }
}

// ---------------------------------------------------------------------------
// Profile for admins and older email accounts: the same picture card as the
// entry-code screen (shield badge, role pill, tilted chips), name and email,
// "Your promise to the team" card, settings, then the Sign out button.
// ---------------------------------------------------------------------------

class _AdminProfile extends StatelessWidget {
  const _AdminProfile({required this.employee, required this.email});

  final Employee employee;
  final String email;

  @override
  Widget build(BuildContext context) {
    final name = employee.name.trim();
    final isAdmin = employee.isManagement;

    Widget divider() => const Divider(height: 1, color: Color(0xFFEEF1F6));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        leadingWidth: 68,
        leading: const AppBackButton(),
        title: const SizedBox.shrink(),
        actions: const [_TitlePill('Profile', icon: Icons.person_outline)],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
              children: [
                _ProfilePicture(
                  initial: name.isEmpty ? null : name[0].toUpperCase(),
                  isAdmin: isAdmin,
                ),
                const SizedBox(height: 16),

                // Name and email.
                Text(
                  name.isEmpty ? 'No name' : name,
                  textAlign: TextAlign.center,
                  style: _s(23, w: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  email.isEmpty ? '—' : email,
                  textAlign: TextAlign.center,
                  style: _s(13.5, c: AppColors.muted),
                ),

                // Admins: the promise that keeps people speaking openly.
                if (isAdmin) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    decoration: BoxDecoration(
                      color: AppColors.blueTint,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.shield_outlined,
                                size: 18, color: AppColors.blue),
                            const SizedBox(width: 8),
                            Text('Your promise to the team',
                                style: _s(14.5, w: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(text: 'You see every message, but '),
                              TextSpan(
                                text: 'never who wrote it',
                                style: _s(13, w: FontWeight.w500),
                              ),
                              const TextSpan(
                                text: ', unless they choose “With my name”. '
                                    'This is what makes people speak openly.',
                              ),
                            ],
                          ),
                          style: _s(13, c: AppColors.muted, h: 1.45),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),

                // Settings. The border is on the Material itself, so the
                // rows and the tap ripple stay inside the rounded corners.
                Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: _line),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _ListRow(
                        icon: Icons.lock_outline,
                        title: 'Change password',
                        sub: 'Use at least 8 characters',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ChangeMyPasswordScreen(),
                          ),
                        ),
                      ),
                      divider(),
                      // Backup code (older email employee accounts only).
                      if (!isAdmin) ...[
                        _ListRow(
                          icon: Icons.key_outlined,
                          title: 'Backup code',
                          sub: 'Make a new code if you lost yours',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const NewBackupCodeScreen(),
                            ),
                          ),
                        ),
                        divider(),
                      ],
                      _ListRow(
                        icon: Icons.shield_outlined,
                        title: 'Help & Privacy',
                        sub: 'Questions and answers about the app',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const HelpScreen(),
                          ),
                        ),
                      ),
                      // Delete my account (older email employee accounts only).
                      if (!isAdmin) ...[
                        divider(),
                        _ListRow(
                          icon: Icons.delete_outline_rounded,
                          title: 'Delete my account',
                          sub: 'Only when you leave Haystek',
                          danger: true,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const DeleteAccountScreen(),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Sign out.
                OutlinedButton.icon(
                  onPressed: () => confirmSignOut(context),
                  icon: const Icon(Icons.logout_rounded, size: 20),
                  label: const Text('Sign out'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    foregroundColor: _red,
                    side: const BorderSide(color: Color(0xFFF1C9C2), width: 1.5),
                    shape: const StadiumBorder(),
                    textStyle: _s(15.5, w: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 14),
                const _VersionLine(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The picture card on top of the admin profile (same style as the
/// entry-code screen): soft blue card, big shield badge (letter for older
/// email accounts), role pill and small tilted chips.
class _ProfilePicture extends StatelessWidget {
  const _ProfilePicture({required this.initial, required this.isAdmin});

  final String? initial;
  final bool isAdmin;

  static const _shadow = [
    BoxShadow(
      color: Color(0x7314286E),
      blurRadius: 30,
      offset: Offset(0, 14),
      spreadRadius: -16,
    ),
  ];

  Widget _chip(String emoji, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _line),
      boxShadow: _shadow,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 6),
        Text(text, style: _s(11.5)),
      ],
    ),
  );

  Widget _tilt(double deg, Widget child) =>
      Transform.rotate(angle: deg * 3.1415926 / 180, child: child);

  Widget _circle(double size) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      color: Color(0x122453D6),
      shape: BoxShape.circle,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 240,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.blueTint, Color(0xFFF7F9FE)],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Soft circles in the corners.
          Positioned(left: -60, top: -70, child: _circle(200)),
          Positioned(right: -30, bottom: -40, child: _circle(140)),

          // Small tilted chips.
          if (isAdmin) ...[
            Positioned(
              left: 14,
              top: 30,
              child: _tilt(-6, _chip('💬', 'Read & reply')),
            ),
            Positioned(
              right: -8,
              top: 118,
              child: _tilt(6, _chip('🙈', 'No names')),
            ),
          ],

          // Big badge in the middle: shield for admins.
          Positioned(
            left: 0,
            right: 0,
            top: 40,
            child: Center(
              child: Container(
                width: 116,
                height: 116,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(36),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF0B1B4D),
                      Color(0xFF14328F),
                      AppColors.blue,
                    ],
                    stops: [0, 0.55, 1],
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0xD92453D6),
                      blurRadius: 40,
                      offset: Offset(0, 22),
                      spreadRadius: -18,
                    ),
                  ],
                ),
                child: isAdmin
                    ? const Icon(Icons.shield_outlined,
                    color: Colors.white, size: 54)
                    : initial == null
                    ? const Icon(Icons.person_outline_rounded,
                    color: Colors.white, size: 52)
                    : Text(
                  initial!,
                  style: _s(50, w: FontWeight.w600, c: Colors.white),
                ),
              ),
            ),
          ),

          // Role pill under the badge.
          Positioned(
            left: 0,
            right: 0,
            top: 180,
            child: Center(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 7, 14, 7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _line),
                  boxShadow: _shadow,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shield_outlined,
                        size: 15, color: AppColors.blue),
                    const SizedBox(width: 6),
                    Text(
                      isAdmin ? 'Admin · Haystek Pulse' : 'Employee',
                      style: _s(13, w: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row in the admin profile list: icon square, title, small text, arrow.
class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.icon,
    required this.title,
    required this.sub,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: danger ? const Color(0xFFFDEFEC) : AppColors.blueTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child:
              Icon(icon, size: 20, color: danger ? _red : AppColors.blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: _s(15,
                        w: FontWeight.w500, c: danger ? _red : AppColors.ink),
                  ),
                  const SizedBox(height: 1),
                  Text(sub, style: _s(12.5, c: AppColors.muted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: _soft),
          ],
        ),
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

// ---------------------------------------------------------------------------
// Profile for personal-code employees: "Anonymous", what admin can and
// can't see, how to get credit for an idea, the personal code (hidden
// until Show), Help & Privacy and Delete my account.
// ---------------------------------------------------------------------------

const Color _line = Color(0xFFE3E8F1);
const Color _soft = Color(0xFF8E97AB);
const Color _red = Color(0xFFC0392B);
const Color _green = Color(0xFF16A34A);

TextStyle _s(double size, {FontWeight w = FontWeight.w400, Color c = AppColors.ink, double? h}) =>
    GoogleFonts.inter(fontSize: size, fontWeight: w, color: c, height: h);

class _CodeProfile extends StatefulWidget {
  const _CodeProfile();

  @override
  State<_CodeProfile> createState() => _CodeProfileState();
}

class _CodeProfileState extends State<_CodeProfile> {
  String? _code;
  bool _loaded = false;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    AuthService.instance.savedCode().then((c) {
      if (mounted) setState(() {
        _code = c;
        _loaded = true;
      });
    });
  }

  void _copy() {
    final c = _code;
    if (c == null) return;
    Clipboard.setData(ClipboardData(text: c));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Personal code copied')),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: _s(11.5, c: _soft).copyWith(letterSpacing: 0.7)),
  );

  Widget _item(bool hidden, String t) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: hidden ? Colors.white : const Color(0xFFE7F6EC),
            shape: BoxShape.circle,
            border: hidden ? Border.all(color: const Color(0xFFD7E1FB)) : null,
          ),
          child: Icon(
            hidden ? Icons.lock_outline_rounded : Icons.check_rounded,
            size: 13,
            color: hidden ? AppColors.blue : _green,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(t, style: _s(14))),
      ],
    ),
  );

  Widget _smallButton(IconData icon, String t, VoidCallback? onTap) => Material(
    color: Colors.white,
    shape: const StadiumBorder(side: BorderSide(color: _line, width: 1.5)),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppColors.blue),
            const SizedBox(width: 5),
            Text(t, style: _s(13, w: FontWeight.w500, c: AppColors.blue)),
          ],
        ),
      ),
    ),
  );

  Widget _row({
    required IconData icon,
    required String title,
    required String sub,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: danger ? const Color(0xFFFDEFEC) : AppColors.blueTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: danger ? _red : AppColors.blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: _s(15, w: FontWeight.w500, c: danger ? _red : AppColors.ink)),
                  const SizedBox(height: 1),
                  Text(sub, style: _s(12.5, c: AppColors.muted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: _soft),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        leadingWidth: 68,
        leading: const AppBackButton(),
        title: const SizedBox.shrink(),
        actions: const [_TitlePill('Profile', icon: Icons.person_outline)],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
              children: [
                // Who you are here: nobody.
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF0B1B4D), Color(0xFF14328F), AppColors.blue],
                          stops: [0, 0.55, 1],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x662453D6),
                            blurRadius: 22,
                            offset: Offset(0, 10),
                            spreadRadius: -10,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.person_outline_rounded,
                          color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Anonymous', style: _s(21, w: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('Employee · No email · No name',
                              style: _s(12.5, c: AppColors.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Your privacy: hidden from admin / admin sees.
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.blueTint, Color(0xFFF7F9FE)],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.shield_outlined, size: 19, color: AppColors.blue),
                          const SizedBox(width: 8),
                          Text('Your privacy', style: _s(15, w: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _label('HIDDEN FROM ADMIN'),
                      _item(true, 'Your name'),
                      _item(true, 'Your email and phone number'),
                      _item(true, 'Who wrote which message'),
                      const Divider(height: 12, color: Color(0xFFDCE5FA)),
                      const SizedBox(height: 6),
                      _label('ADMIN SEES'),
                      _item(false, 'Your message, without your name'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Want credit? Name on one message only.
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFC9D6FF), width: 1.5),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('💡', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Want credit for a good idea?',
                                style: _s(14, w: FontWeight.w500)),
                            const SizedBox(height: 3),
                            Text.rich(
                              TextSpan(
                                children: [
                                  const TextSpan(text: 'When you send, choose '),
                                  TextSpan(
                                    text: '👤 With my name',
                                    style: _s(12.5, w: FontWeight.w500, c: AppColors.blue),
                                  ),
                                  const TextSpan(
                                    text: '. Your name shows only on that one '
                                        'message. Everything else stays anonymous.',
                                  ),
                                ],
                              ),
                              style: _s(12.5, c: AppColors.muted, h: 1.45),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // My personal code: hidden until Show.
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: AppColors.blueTint,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: const Icon(Icons.key_outlined,
                                size: 18, color: AppColors.blue),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('My personal code', style: _s(15, w: FontWeight.w500)),
                                Text('Needed only when you change your phone',
                                    style: _s(12, c: AppColors.muted)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (!_loaded)
                        const SizedBox(height: 40)
                      else if (code == null)
                        Text(
                          'Your code is not saved on this phone. Use the code '
                              'you saved when you joined.',
                          style: _s(13, c: AppColors.muted, h: 1.45),
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF6F8FB),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    child: Text(
                                      _show ? code : '•••••–•••••',
                                      maxLines: 1,
                                      style: GoogleFonts.robotoMono(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 2,
                                        color: AppColors.blue,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _smallButton(
                              _show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              _show ? 'Hide' : 'Show',
                                  () => setState(() => _show = !_show),
                            ),
                            const SizedBox(width: 6),
                            _smallButton(Icons.copy_rounded, 'Copy', _copy),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Help & Privacy, Delete my account.
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _line),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Material(
                    color: Colors.white,
                    child: Column(
                      children: [
                        _row(
                          icon: Icons.shield_outlined,
                          title: 'Help & Privacy',
                          sub: 'Questions and answers about the app',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => const HelpScreen()),
                          ),
                        ),
                        const Divider(height: 1, color: Color(0xFFEEF1F6)),
                        _row(
                          icon: Icons.delete_outline_rounded,
                          title: 'Delete my account',
                          sub: 'Only when you leave Haystek',
                          danger: true,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const DeleteAccountScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const _VersionLine(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom of Profile: "Haystek Pulse · Version 1.0.0 (5) · DEV" (or PROD),
/// so testers can say exactly which build they have.
class _VersionLine extends StatelessWidget {
  const _VersionLine();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snap) {
        final info = snap.data;
        final build = appFlavor == 'dev' ? 'DEV' : 'PROD';
        final text = info == null
            ? 'Haystek Pulse'
            : 'Haystek Pulse · Version '
                '${info.version.replaceAll('-dev', '')} '
                '(${info.buildNumber}) · $build';
        return Text(
          text,
          textAlign: TextAlign.center,
          style: _s(12, c: _soft),
        );
      },
    );
  }
}