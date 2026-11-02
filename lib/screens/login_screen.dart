import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:firebase_auth/firebase_auth.dart';

import '../services/auth_service.dart';
import '../services/personal_code.dart';
import '../theme/app_theme.dart';
import '../widgets/pulse_loading.dart';

/// Which part of the sign-in screen shows.
/// welcome:  Join with entry code / I have my personal code / Admin
/// join:     enter the entry code shared with the team (employees)
/// personal: sign in with the personal code (new phone, reinstall)
/// admin:    office email + password (sign in, create account, reset)
/// found:    this phone is already registered: "Welcome back, Continue"
/// moved:    this phone was signed out: the account is on another phone
enum _Entry { welcome, join, personal, admin, found, moved }

/// Inter font for everything on these screens, sheets and dialogs
/// (same as the employee screens).
Widget _withInter(BuildContext context, Widget child) {
  final t = Theme.of(context);
  return Theme(
    data: t.copyWith(textTheme: GoogleFonts.interTextTheme(t.textTheme)),
    child: child,
  );
}

/// Titles and big numbers in Inter.
TextStyle _h(
    double size, {
      FontWeight weight = FontWeight.w700,
      Color color = AppColors.ink,
      double? height,
    }) =>
    GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: size >= 22 ? -0.5 : -0.2,
    );

/// The small blue text buttons.
final ButtonStyle _linkButton = TextButton.styleFrom(
  textStyle: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w500),
);

/// The small grey line under a title.
const TextStyle _sub = TextStyle(
  color: AppColors.muted,
  fontSize: 12,
  height: 1.4,
);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  _Entry _entry = _Entry.welcome;
  final _entryCode = TextEditingController();
  final _personalCode = TextEditingController();

  /// The Firebase code of the last error (to offer the right button).
  String? _errorCode;

  /// True while checking this phone (signing in by itself if it can).
  bool _autoTrying = false;

  /// This phone is registered: its personal code (opened with the phone ID).
  String? _found;

  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _adminCode = TextEditingController();
  bool _busy = false;

  /// Email accounts are only for admins now: always true.
  final bool _admin = true;
  bool _hideCode = true;

  /// True after Sign in / Create account was tapped once. From then on
  /// each field checks itself while typing, so an error goes away as
  /// soon as it is fixed.
  bool _tried = false;

  /// True on the "Create account" step.
  bool _signUpMode = false;
  bool _hidePassword = true;
  String? _error;

  /// True on the "Reset password" step, where only the email shows.
  bool _resetMode = false;

  /// True after the reset link was sent.
  bool _resetSent = false;

  @override
  void initState() {
    super.initState();
    // Back from "Wrong email? Start over": open Create account again,
    // with the name and email filled in.
    final auth = AuthService.instance;
    if (auth.openSignUp) {
      _entry = _Entry.admin;
      _signUpMode = true;
      _name.text = auth.signUpName ?? '';
      _email.text = auth.signUpEmail ?? '';
      auth.openSignUp = false;
      auth.signUpEmail = null;
      auth.signUpName = null;
    }
    // Signed out because the account moved to another phone: say so.
    if (auth.movedNotice) {
      auth.movedNotice = false;
      _entry = _Entry.moved;
    }
    if (_entry == _Entry.welcome) _checkThisPhone();
  }

  /// Is this phone already registered?
  /// - iPhone: the personal code is still in the Keychain: sign in at once.
  /// - Android after a reinstall: the code is kept with the phone's record,
  ///   locked with the phone ID: show "Welcome back" with Continue.
  Future<void> _checkThisPhone() async {
    final auth = AuthService.instance;
    _autoTrying = true; // Called from initState: no setState needed.
    if (await auth.savedCode() != null && await auth.autoSignIn()) {
      return; // Signed in: AuthGate shows the home screen.
    }
    final found = await auth.codeOnThisPhone();
    if (!mounted) return;
    setState(() {
      _autoTrying = false;
      // The account moved to another phone while this one was away.
      if (auth.movedNotice) {
        auth.movedNotice = false;
        _entry = _Entry.moved;
        return;
      }
      // Registered phone: "Welcome back" with Continue.
      if (found != null && _entry == _Entry.welcome) {
        _found = found;
        _entry = _Entry.found;
      }
    });
  }

  /// "Continue" on Welcome back.
  Future<void> _continueFound() async {
    final code = _found;
    if (code == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _errorCode = null;
    });
    try {
      // Signs in by itself: if the account moved to another phone, this
      // phone is freed instead.
      await AuthService.instance.signInWithPersonalCode(code, claim: false);
    } catch (e) {
      if (!mounted) return;
      if (e is FirebaseAuthException && e.code == 'account-moved') {
        AuthService.instance.movedNotice = false;
        setState(() {
          _found = null;
          _entry = _Entry.moved;
        });
        return;
      }
      setState(() {
        _error = AuthService.messageFor(e);
        _errorCode = e is FirebaseAuthException ? e.code : null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "This phone has another account. Switch?"
  Future<bool?> _askSwitch() {
    return showDialog<bool>(
      context: context,
      builder: (c) => _withInter(
        c,
        AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          icon: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: AppColors.blueTint,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.swap_horiz_rounded, color: AppColors.blue, size: 28),
          ),
          title: Text(
            'Switch account?',
            textAlign: TextAlign.center,
            style: _h(20, weight: FontWeight.w600),
          ),
          content: Text(
            'This phone already has another account. If you switch, you’ll '
                'need that account’s personal code to open it again.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 14.5, height: 1.45, color: AppColors.muted),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          actions: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  onPressed: () => Navigator.pop(c, false),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    minimumSize: const Size.fromHeight(50),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('No, keep it'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(c, true),
                  style: TextButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  child: const Text('Yes, switch'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Shows another part of the screen (welcome, join, personal, admin).
  /// A registered phone always shows "Welcome back" instead of Welcome.
  void _go(_Entry to) {
    FocusScope.of(context).unfocus();
    if (to == _Entry.welcome && _found != null) to = _Entry.found;
    setState(() {
      _entry = to;
      _signUpMode = false;
      _resetMode = false;
      _error = null;
      _errorCode = null;
      _tried = false;
    });
  }

  /// "Join": checks the entry code and the phone, then makes the account.
  Future<void> _join() async {
    FocusScope.of(context).unfocus();
    if (_entryCode.text.trim().isEmpty) {
      setState(() => _error = 'Enter the entry code shared with your team.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _errorCode = null;
    });
    try {
      await AuthService.instance.joinWithEntryCode(_entryCode.text);
      // AuthGate shows the next screen by itself.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AuthService.messageFor(e);
        _errorCode = e is FirebaseAuthException ? e.code : null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Sign in" with the personal code.
  Future<void> _signInWithCode() async {
    FocusScope.of(context).unfocus();
    if (_personalCode.text.trim().isEmpty) {
      setState(() => _error = 'Enter your personal code.');
      return;
    }
    // This phone has a different account: ask before switching.
    final auth = AuthService.instance;
    final other = await auth.savedCode() ?? await auth.codeOnThisPhone();
    if (!mounted) return;
    if (other != null &&
        PersonalCode.normalize(other) != PersonalCode.normalize(_personalCode.text)) {
      if (await _askSwitch() != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _errorCode = null;
    });
    try {
      await AuthService.instance.signInWithPersonalCode(_personalCode.text);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AuthService.messageFor(e);
        _errorCode = e is FirebaseAuthException ? e.code : null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _adminCode.dispose();
    _entryCode.dispose();
    _personalCode.dispose();
    super.dispose();
  }

  bool _looksLikeEmail(String? v) =>
      v != null && v.trim().contains('@') && v.trim().contains('.');

  Future<void> _signIn() async {
    FocusScope.of(context).unfocus(); // closes the keyboard
    setState(() => _tried = true);
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.signIn(_email.text, _password.text);
      // AuthGate shows the next screen automatically.
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AuthService.messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// When back was last pressed on Sign in.
  DateTime? _lastBack;

  /// First back shows "Press back again to close the app", a second back
  /// within 2 seconds closes it.
  void _backOnSignIn() {
    final now = DateTime.now();
    if (_lastBack != null &&
        now.difference(_lastBack!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBack = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Press back again to close the app'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  /// Opens or closes the "Create account" step.
  void _toggleSignUp(bool on) {
    FocusScope.of(context).unfocus();
    setState(() {
      _signUpMode = on;
      _resetMode = false;
      _error = null;
      _tried = false;
    });
  }

  Future<void> _signUp() async {
    FocusScope.of(context).unfocus();
    setState(() => _tried = true);
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.signUp(
        name: _name.text,
        email: _email.text,
        password: _password.text,
        admin: _admin,
        adminCode: _adminCode.text,
      );
      // AuthGate shows "Check your email" by itself.
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AuthService.messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Typing again: hide the red message from the last try.
  void _clearError() {
    if (_error != null) {
      setState(() {
        _error = null;
        _errorCode = null;
      });
    }
  }

  /// Opens the "Reset password" step. Only the email field shows.
  void _openReset() {
    FocusScope.of(context).unfocus();
    setState(() {
      _signUpMode = false;
      _resetMode = true;
      _resetSent = false;
      _error = null;
    });
  }

  /// Back to the normal sign in.
  void _closeReset() {
    FocusScope.of(context).unfocus();
    setState(() {
      _resetMode = false;
      _resetSent = false;
      _error = null;
    });
  }

  Future<void> _sendReset() async {
    FocusScope.of(context).unfocus(); // closes the keyboard
    if (!_looksLikeEmail(_email.text)) {
      setState(() => _error = 'Enter your office email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.sendPasswordReset(_email.text);
      if (!mounted) return;
      setState(() => _resetSent = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AuthService.messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _busyDot() => const SizedBox(
    height: 20,
    width: 20,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: Colors.white,
    ),
  );

  /// One row of the grouped card: an icon and a field without a box.
  Widget _row({
    required IconData icon,
    required Widget field,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF8E97AB)),
          const SizedBox(width: 12),
          Expanded(child: field),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  /// The grouped card around the fields: one border, a thin line between.
  Widget _card(List<Widget> rows) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE3E8F1), width: 1.5),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1.5,
                thickness: 1.5,
                indent: 48,
                color: Color(0xFFEDF0F6),
              ),
            rows[i],
          ],
        ],
      ),
    );
  }

  /// A field with no box of its own (the card is the box).
  static InputDecoration _plain(String label) => InputDecoration(
    labelText: label,
    labelStyle: GoogleFonts.inter(color: const Color(0xFF8E97AB)),
    floatingLabelStyle: GoogleFonts.inter(color: const Color(0xFF8E97AB)),
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
    filled: false,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(vertical: 12),
    // Long errors wrap instead of being cut off.
    errorMaxLines: 3,
    errorStyle: GoogleFonts.inter(fontSize: 12.5, height: 1.3),
  );

  /// The small grey line with a blue link: "Trouble signing in? Reset".
  Widget _helpLine(String text, String link, VoidCallback? onTap) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(text, style: _sub),
        TextButton(
          onPressed: onTap,
          style: _linkButton.copyWith(
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 6),
            ),
          ),
          child: Text(link),
        ),
      ],
    );
  }

  /// One code field (entry code or personal code) in the grouped card.
  Widget _codeField({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    String? hint,
    bool capitals = true,
    required VoidCallback onDone,
  }) {
    return _card([
      _row(
        icon: icon,
        field: TextField(
          controller: controller,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: capitals
              ? TextCapitalization.characters
              : TextCapitalization.none,
          keyboardType:
          capitals ? TextInputType.text : TextInputType.visiblePassword,
          textInputAction: TextInputAction.done,
          onChanged: (_) => _clearError(),
          onSubmitted: (_) => onDone(),
          style: GoogleFonts.inter(
            fontSize: 16,
            color: AppColors.ink,
            letterSpacing: capitals ? 1.2 : 0.3,
          ),
          decoration: _plain(label).copyWith(
            hintText: hint,
            hintStyle: GoogleFonts.inter(
              color: const Color(0xFFC3C9D6),
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    ]);
  }

  /// A white button with a light border (the second choice).
  Widget _lightButton(String label, VoidCallback? onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.blue,
        minimumSize: const Size.fromHeight(54),
        side: const BorderSide(color: Color(0xFFE3E8F1), width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }

  /// Welcome, Join and Personal code (employees, no email).
  Widget _codeForm() {
    final error = _error == null
        ? const <Widget>[]
        : [
      const SizedBox(height: 12),
      _ErrorBox(
        message: _error!,
        actions: _errorCode == 'device-has-account'
            ? [('Use personal code', () => _go(_Entry.personal))]
            : const [],
      ),
    ];

    switch (_entry) {
      case _Entry.found:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: _FoundBadge()),
            const SizedBox(height: 16),
            Text('Welcome back', textAlign: TextAlign.center, style: _h(24)),
            const SizedBox(height: 6),
            Text(
              'Your account is on this phone.\nNo code needed.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14.5,
                height: 1.5,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.blueTint,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline_rounded,
                        size: 14, color: AppColors.blue),
                    const SizedBox(width: 6),
                    Text(
                      'Anonymous account',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: AppColors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ...error,
            const SizedBox(height: 24),
            _GradientButton(
              onPressed: _busy ? null : _continueFound,
              child: _busy ? _busyDot() : const Text('Continue'),
            ),
          ],
        );
      case _Entry.join:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Join', style: _h(24)),
            const SizedBox(height: 4),
            const Text(
              'Enter the entry code shared with your team. It only shows you are '
                  'from Haystek, not who you are.',
              style: _sub,
            ),
            const SizedBox(height: 18),
            _codeField(
              controller: _entryCode,
              icon: Icons.mark_email_read_outlined,
              label: 'Entry code',
              onDone: _join,
            ),
            ...error,
            const SizedBox(height: 20),
            _GradientButton(
              onPressed: _busy ? null : _join,
              child: _busy ? _busyDot() : const Text('Join'),
            ),
            const SizedBox(height: 8),
            _helpLine(
              'Already joined?',
              'Use personal code',
              _busy ? null : () => _go(_Entry.personal),
            ),
          ],
        );
      case _Entry.personal:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Sign in', style: _h(24)),
            const SizedBox(height: 4),
            const Text(
              'New phone? Enter the personal code you saved when you joined.',
              style: _sub,
            ),
            const SizedBox(height: 18),
            _codeField(
              controller: _personalCode,
              icon: Icons.key_outlined,
              label: 'Personal code',
              hint: 'XXXXX-XXXXX',
              capitals: false,
              onDone: _signInWithCode,
            ),
            ...error,
            const SizedBox(height: 20),
            _GradientButton(
              onPressed: _busy ? null : _signInWithCode,
              child: _busy ? _busyDot() : const Text('Sign in'),
            ),
            const SizedBox(height: 8),
            _helpLine(
              'New here?',
              'Join with entry code',
              _busy ? null : () => _go(_Entry.join),
            ),
          ],
        );
      case _Entry.welcome:
      case _Entry.admin:
      case _Entry.moved: // Has its own screen; never shown here.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Welcome', style: _h(24)),
            const SizedBox(height: 4),
            const Text(
              'No email, no name. Nobody can tell who wrote what.',
              style: _sub,
            ),
            const SizedBox(height: 22),
            _GradientButton(
              onPressed: () => _go(_Entry.join),
              child: const Text('Join with entry code'),
            ),
            const SizedBox(height: 12),
            _lightButton(
              'I have my personal code',
                  () => _go(_Entry.personal),
            ),
            const SizedBox(height: 14),
            _helpLine('Admin?', 'Sign in with email', () => _go(_Entry.admin)),
          ],
        );
    }
  }

  /// The form under the blue block: sign in, or reset password.
  Widget _form(ThemeData theme) {
    if (_entry != _Entry.admin) return _codeForm();
    final error = _error == null
        ? const <Widget>[]
        : [
      const SizedBox(height: 12),
      _ErrorBox(
        message: _error!,
        // Wrong email or password on Sign in: offer the two ways out.
        actions: _signUpMode || _resetMode
            ? const []
            : _error == AuthService.noAccount
            ? [('Create account', () => _toggleSignUp(true))]
            : _error == AuthService.wrongPassword
            ? [('Reset password', _openReset)]
            : _error == AuthService.wrongLogin
            ? [
          ('Create account', () => _toggleSignUp(true)),
          ('Reset password', _openReset),
        ]
            : const [],
      ),
    ];

    final emailField = TextFormField(
      controller: _email,
      keyboardType: TextInputType.emailAddress,
      textInputAction:
      _resetMode ? TextInputAction.done : TextInputAction.next,
      autocorrect: false,
      autofillHints: const [AutofillHints.email],
      onFieldSubmitted: _resetMode ? (_) => _sendReset() : null,
      onChanged: _resetMode ? (_) => _clearError() : null,
      style: GoogleFonts.inter(fontSize: 15.5, color: AppColors.ink),
      decoration: _plain('Office email'),
      validator: (v) {
        if (!_looksLikeEmail(v)) return 'Enter your office email';
        if (_signUpMode &&
            !v!.trim().toLowerCase().endsWith(AuthService.officeDomain)) {
          return 'Use your ${AuthService.officeDomain} email';
        }
        return null;
      },
    );
    final emailRow = _row(icon: Icons.mail_outline, field: emailField);

    // Step 2 of reset: the link was sent.
    if (_resetMode && _resetSent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.mark_email_read_outlined,
            size: 48,
            color: AppColors.blue,
          ),
          const SizedBox(height: 14),
          Text('Check your email', textAlign: TextAlign.center, style: _h(22)),
          const SizedBox(height: 8),
          Text(
            'If ${_email.text.trim()} is registered, we have sent a link to '
                'set a new password. Please check your inbox and spam folder.',
            textAlign: TextAlign.center,
            style: _sub,
          ),
          const SizedBox(height: 26),
          _GradientButton(onPressed: _closeReset, child: const Text('Back to sign in')),
          const SizedBox(height: 8),
          _helpLine('No email?', 'Send it again', _busy ? null : _sendReset),
        ],
      );
    }

    // Step 1 of reset: email only.
    if (_resetMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Reset password', style: _h(24)),
          const SizedBox(height: 4),
          const Text(
            'Enter your office email. We will send you a link to set a new '
                'password.',
            style: _sub,
          ),
          const SizedBox(height: 18),
          _card([emailRow]),
          ...error,
          const SizedBox(height: 20),
          _GradientButton(
            onPressed: _busy ? null : _sendReset,
            child: _busy ? _busyDot() : const Text('Send reset link'),
          ),
          const SizedBox(height: 8),
          _helpLine(
            'Remembered it?',
            'Back to sign in',
            _busy ? null : _closeReset,
          ),
        ],
      );
    }

    final passwordRow = _row(
      icon: Icons.lock_outline,
      field: TextFormField(
        controller: _password,
        obscureText: _hidePassword,
        autofillHints: [
          _signUpMode ? AutofillHints.newPassword : AutofillHints.password,
        ],
        onFieldSubmitted: (_) => _signUpMode ? _signUp() : _signIn(),
        style: GoogleFonts.inter(fontSize: 15.5, color: AppColors.ink),
        decoration: _plain('Password'),
        validator: (v) {
          if (v == null || v.isEmpty) return 'Enter your password';
          if (_signUpMode && v.length < 8) return 'Use at least 8 characters';
          return null;
        },
      ),
      trailing: TextButton(
        onPressed: () => setState(() => _hidePassword = !_hidePassword),
        style: _linkButton,
        child: Text(_hidePassword ? 'Show' : 'Hide'),
      ),
    );

    // Create account.
    if (_signUpMode) {
      return Form(
        key: _formKey,
        autovalidateMode: _tried
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        onChanged: _clearError,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Create admin account', style: _h(24)),
            const SizedBox(height: 2),
            Text(
              'Only for admins. Use your office email '
                  '(${AuthService.officeDomain}).',
              style: _sub,
            ),
            const SizedBox(height: 18),
            _card([
              _row(
                icon: Icons.person_outline,
                field: TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  style: GoogleFonts.inter(fontSize: 15.5, color: AppColors.ink),
                  decoration: _plain('Full name'),
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? 'Enter your name'
                      : null,
                ),
              ),
              emailRow,
              passwordRow,
            ]),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(
                'At least 8 characters. It also locks your history, '
                    'so pick one only you know.',
                style: _sub,
              ),
            ),
            if (_admin) ...[
              const SizedBox(height: 12),
              _card([
                _row(
                  icon: Icons.key_outlined,
                  field: TextFormField(
                    controller: _adminCode,
                    obscureText: _hideCode,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.characters,
                    // Admin codes are 6 letters or numbers, like HSTADM.
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                      LengthLimitingTextInputFormatter(6),
                      TextInputFormatter.withFunction(
                            (old, now) => now.copyWith(text: now.text.toUpperCase()),
                      ),
                    ],
                    style: GoogleFonts.inter(fontSize: 15.5, color: AppColors.ink),
                    decoration: _plain('Admin entry code'),
                    validator: (v) => (_admin && (v == null || v.trim().isEmpty))
                        ? 'Enter the admin entry code'
                        : null,
                  ),
                  trailing: TextButton(
                    onPressed: () => setState(() => _hideCode = !_hideCode),
                    style: _linkButton,
                    child: Text(_hideCode ? 'Show' : 'Hide'),
                  ),
                ),
              ]),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
                child: Text(
                  'From the HR mail. Only admins get this code.',
                  style: _sub,
                ),
              ),
            ],
            ...error,
            const SizedBox(height: 20),
            _GradientButton(
              onPressed: _busy ? null : _signUp,
              child: _busy ? _busyDot() : const Text('Create account'),
            ),
            const SizedBox(height: 8),
            _helpLine(
              'Already have an account?',
              'Sign in',
              _busy ? null : () => _toggleSignUp(false),
            ),
          ],
        ),
      );
    }

    // Normal sign in.
    return Form(
      key: _formKey,
      autovalidateMode: _tried
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      onChanged: _clearError,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Admin sign in', style: _h(24)),
          const SizedBox(height: 2),
          const Text('Use your office email.', style: _sub),
          const SizedBox(height: 18),
          _card([
            emailRow,
            passwordRow,
          ]),
          ...error,
          const SizedBox(height: 20),
          _GradientButton(
            onPressed: _busy ? null : _signIn,
            child: _busy ? _busyDot() : const Text('Sign in'),
          ),
          const SizedBox(height: 10),
          _helpLine(
            'Trouble signing in?',
            'Reset password',
            _busy ? null : _openReset,
          ),
          _helpLine(
            'New admin?',
            'Create account',
            _busy ? null : () => _toggleSignUp(true),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Checking this phone / signing in by itself: one calm loading screen.
    if (_autoTrying) return const PulseLoadingScreen();
    // First screen for new people: its own clean design.
    if (_entry == _Entry.welcome) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _backOnSignIn();
        },
        child: _WelcomeView(
          onJoin: () => _go(_Entry.join),
          onPersonal: () => _go(_Entry.personal),
          onAdmin: () => _go(_Entry.admin),
        ),
      );
    }
    // Signed out: the account is on another phone now.
    if (_entry == _Entry.moved) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _go(_Entry.welcome);
        },
        child: _withInter(
          context,
          _MovedView(
            onOk: () => _go(_Entry.welcome),
            onPersonal: () => _go(_Entry.personal),
          ),
        ),
      );
    }
    // This phone already has an account: its own clean design.
    if (_entry == _Entry.found) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _backOnSignIn();
        },
        child: _withInter(
          context,
          _FoundView(
            busy: _busy,
            error: _error,
            onContinue: _continueFound,
          ),
        ),
      );
    }
    // Join with the entry code: its own design too.
    if (_entry == _Entry.join || _entry == _Entry.personal) {
      final personal = _entry == _Entry.personal;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !_busy) _go(_Entry.welcome);
        },
        child: _withInter(
          context,
          _JoinView(
            // A new key so the screen starts fresh when switching.
            key: ValueKey(personal),
            personal: personal,
            controller: personal ? _personalCode : _entryCode,
            busy: _busy,
            error: _error == null
                ? const []
                : [
              const SizedBox(height: 12),
              _ErrorBox(
                message: _error!,
                actions: _errorCode == 'device-has-account'
                    ? [('Use personal code', () => _go(_Entry.personal))]
                    : const [],
              ),
            ],
            onJoin: personal ? _signInWithCode : _join,
            onBack: () => _go(_Entry.welcome),
            onPersonal: () => _go(personal ? _Entry.join : _Entry.personal),
            onChanged: _clearError,
          ),
        ),
      );
    }
    final theme = Theme.of(context);
    // Small picture hidden while typing and on Create account, so the
    // form fits on the screen.
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    final compact = typing || _signUpMode;
    void back() {
      if (_busy) return;
      if (_resetMode) {
        _closeReset();
      } else if (_signUpMode) {
        _toggleSignUp(false);
      } else {
        _go(_Entry.welcome);
      }
    }

    // Admin: white, back button and "Admin" pill on top, a small soft blue
    // card, then the form (sign in, create account or reset password).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) back();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: _withInter(
          context,
          Scaffold(
            backgroundColor: Colors.white,
            body: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.translucent,
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TopBar(
                      label: 'Admin',
                      icon: Icons.shield_outlined,
                      onBack: _busy ? null : back,
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) => SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: box.maxHeight),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Align(
                                  alignment: Alignment.topCenter,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 480),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          AnimatedSize(
                                            duration: const Duration(milliseconds: 220),
                                            curve: Curves.easeOutCubic,
                                            alignment: Alignment.topCenter,
                                            child: compact
                                                ? const SizedBox(width: double.infinity)
                                                : const Padding(
                                              padding: EdgeInsets.only(bottom: 22),
                                              child: _AdminPicture(),
                                            ),
                                          ),
                                          _form(theme),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                if (!typing)
                                  const Padding(
                                    padding: EdgeInsets.fromLTRB(24, 20, 24, 16),
                                    child: _Footer(),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
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

/// Back button on the left, a rounded title pill on the right.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.label, required this.icon, required this.onBack});

  final String label;
  final IconData icon;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Material(
            color: Colors.white,
            shape: const CircleBorder(side: BorderSide(color: Color(0xFFE3E8F1))),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onBack,
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.chevron_left_rounded, color: AppColors.ink, size: 26),
              ),
            ),
          ),
          const Spacer(),
          Container(
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
                Text(label, style: GoogleFonts.inter(fontSize: 16, color: AppColors.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small soft blue card on the admin screen: a shield and two tags.
class _AdminPicture extends StatelessWidget {
  const _AdminPicture();

  @override
  Widget build(BuildContext context) {
    const line = Color(0xFFE3E8F1);
    const shadow = [
      BoxShadow(
        color: Color(0x332453D6),
        blurRadius: 24,
        offset: Offset(0, 12),
        spreadRadius: -12,
      ),
    ];
    Widget tag(String emoji, String text, double angle) => Transform.rotate(
      angle: angle,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: line),
          boxShadow: shadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            Text(text, style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink)),
          ],
        ),
      ),
    );
    Widget blob(double size) => Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0x122453D6),
        shape: BoxShape.circle,
      ),
    );
    return Container(
      height: 170,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.blueTint, Color(0xFFF7F9FE)],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(left: -50, top: -60, child: blob(170)),
          Positioned(right: -30, bottom: -40, child: blob(120)),
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0B1B4D), Color(0xFF14328F), AppColors.blue],
                stops: [0, 0.55, 1],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x662453D6),
                  blurRadius: 30,
                  offset: Offset(0, 14),
                  spreadRadius: -12,
                ),
              ],
            ),
            child: const Icon(Icons.shield_outlined, color: Colors.white, size: 36),
          ),
          Positioned(left: 14, top: 22, child: tag('🏢', 'Office email', -0.1)),
          Positioned(right: 10, bottom: 26, child: tag('💬', 'Reply to your team', 0.08)),
        ],
      ),
    );
  }
}

/// The big blue pill button (same as Welcome and Join).
/// Faded while it cannot be pressed.
class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.onPressed, required this.child});

  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.blue,
          disabledBackgroundColor: AppColors.blue.withValues(alpha: 0.6),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          shape: const StadiumBorder(),
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        child: child,
      ),
    );
  }
}

/// "Powered by Haystek Technologies" and "© 2026" at the bottom.
class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final small = GoogleFonts.inter(
      fontSize: 12.5,
      color: const Color(0xFF8E97AB),
    );
    return Column(
      children: [
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Powered by '),
              TextSpan(
                text: 'Haystek Technologies',
                style: small.copyWith(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF69728A),
                ),
              ),
            ],
          ),
          style: small,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          '© ${DateTime.now().year} Haystek Technologies. All rights reserved.',
          textAlign: TextAlign.center,
          style: small.copyWith(fontSize: 11.5),
        ),
      ],
    );
  }
}

/// A calm error: light red box, small icon, short text, and optional
/// buttons under it.
class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, this.actions = const []});

  final String message;
  final List<(String, VoidCallback)> actions;

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFC0392B);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFDEFEC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.error_outline_rounded, size: 18, color: red),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.inter(fontSize: 13.5, color: red, height: 1.4),
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final a in actions)
                  Material(
                    color: Colors.white,
                    shape: const StadiumBorder(
                      side: BorderSide(color: Color(0xFFF1C9C2)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: a.$2,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Text(
                          a.$1,
                          style: GoogleFonts.inter(fontSize: 13, color: AppColors.blue),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}


/// Person in a blue circle with a green tick: "your account is here".
class _FoundBadge extends StatelessWidget {
  const _FoundBadge();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        children: [
          Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.blueTint,
              shape: BoxShape.circle,
            ),
            child: Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppColors.blue,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_outline_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 14),
            ),
          ),
        ],
      ),
    );
  }
}


/// First screen for a new phone: white, a soft blue card with a small
/// preview of the app (an anonymous message, admin's reply, the Weekly
/// Pulse faces), a short promise, and the buttons at the bottom.
/// The example message and reply change every few seconds.
class _WelcomeView extends StatefulWidget {
  const _WelcomeView({
    required this.onJoin,
    required this.onPersonal,
    required this.onAdmin,
  });

  final VoidCallback onJoin;
  final VoidCallback onPersonal;
  final VoidCallback onAdmin;

  @override
  State<_WelcomeView> createState() => _WelcomeViewState();
}

class _WelcomeViewState extends State<_WelcomeView> {
  /// Example message and admin's reply. Real-life, simple office things.
  static const _examples = [
    ('Please keep the pantry stocked with snacks.', 'Done, it’s refilled every week now ☕'),
    ('The washroom needs cleaning more often.', 'Cleaning is now twice a day. Thanks!'),
    ('Can we have flexible timings on Fridays?', 'Yes, from this month you can leave at 5.'),
    ('New joiners need a proper onboarding guide.', 'Good point! HR is writing one now 📘'),
    ('The parking area is full by 12 pm.', 'We booked 10 more spots nearby 🚗'),
    ('Can we have a short learning session weekly?', 'Starting Thursdays at 4 pm, 30 minutes.'),
  ];

  int _i = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) setState(() => _i = (_i + 1) % _examples.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static const _ink = AppColors.ink;
  static const _soft = Color(0xFF8E97AB);
  static const _line = Color(0xFFE3E8F1);

  TextStyle _s(double size, {FontWeight w = FontWeight.w400, Color c = _ink, double? h}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: c, height: h);

  Widget _card({required Widget child, double angle = 0}) => Transform.rotate(
    angle: angle,
    child: Container(
      width: 236,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x332453D6),
            blurRadius: 24,
            offset: Offset(0, 12),
            spreadRadius: -12,
          ),
        ],
      ),
      child: child,
    ),
  );

  Widget _msg({required bool admin, required String who, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: admin ? AppColors.blue : AppColors.blueTint,
            borderRadius: BorderRadius.circular(9),
          ),
          child: admin
              ? Text('A', style: _s(12, w: FontWeight.w600, c: Colors.white))
              : const Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.blue),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(who, style: _s(12.5, w: FontWeight.w500)),
              const SizedBox(height: 1),
              Text(text, style: _s(12, c: _soft, h: 1.35)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ex = _examples[_i];
    // Fades and slides a little when the example changes.
    Widget swap(Widget child, String key) => AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      transitionBuilder: (c, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(a),
          child: c,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(key), child: child),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  Center(child: Image.asset('assets/haystek_pulse_logo.png', height: 28)),
                  const SizedBox(height: 12),
                  // The preview card.
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.blueTint, Color(0xFFF7F9FE)],
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: LayoutBuilder(
                          builder: (context, box) {
                            final h = box.maxHeight;
                            return Stack(
                              children: [
                                Positioned(
                                  left: -60,
                                  top: -70,
                                  child: _blob(220),
                                ),
                                Positioned(
                                  right: -40,
                                  bottom: -50,
                                  child: _blob(160),
                                ),
                                Positioned(
                                  right: 18,
                                  top: 20,
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: AppColors.blue,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: const Icon(Icons.lock_outline_rounded,
                                        color: Colors.white, size: 20),
                                  ),
                                ),
                                Positioned(
                                  left: 22,
                                  top: h * 0.09,
                                  child: swap(
                                    _card(
                                      angle: -0.05,
                                      child: _msg(admin: false, who: 'Name hidden', text: ex.$1),
                                    ),
                                    'q$_i',
                                  ),
                                ),
                                Positioned(
                                  right: 18,
                                  top: h * 0.38,
                                  child: swap(
                                    _card(
                                      angle: 0.035,
                                      child: _msg(admin: true, who: 'Admin', text: ex.$2),
                                    ),
                                    'a$_i',
                                  ),
                                ),
                                Positioned(
                                  left: 30,
                                  bottom: h * 0.08,
                                  child: _card(
                                    angle: -0.015,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('How was your week?', style: _s(12, c: _soft)),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            for (final e in ['😄', '🙂', '😐', '😟'])
                                              Expanded(
                                                child: Container(
                                                  height: 32,
                                                  margin: const EdgeInsets.symmetric(horizontal: 2),
                                                  alignment: Alignment.center,
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFF6F8FB),
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                  child: Text(e, style: const TextStyle(fontSize: 16)),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Say it honestly.\nStay anonymous.',
                    textAlign: TextAlign.center,
                    style: _s(26, w: FontWeight.w600, h: 1.2),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No email. No name. Just your voice.',
                    textAlign: TextAlign.center,
                    style: _s(14.5, c: AppColors.muted),
                  ),
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 56,
                          child: FilledButton(
                            onPressed: widget.onJoin,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.blue,
                              shape: const StadiumBorder(),
                              textStyle: _s(16, w: FontWeight.w600),
                            ),
                            child: const Text('Join with entry code'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 56,
                          child: OutlinedButton(
                            onPressed: widget.onPersonal,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.blue,
                              side: const BorderSide(color: _line, width: 1.5),
                              shape: const StadiumBorder(),
                              textStyle: _s(16, w: FontWeight.w600),
                            ),
                            child: const Text('I have my personal code'),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Admin?', style: _s(13, c: _soft)),
                            TextButton(
                              onPressed: widget.onAdmin,
                              child: Text('Sign in with email',
                                  style: _s(13, c: AppColors.blue)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
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

  Widget _blob(double size) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      color: Color(0x122453D6),
      shape: BoxShape.circle,
    ),
  );
}


/// Join screen (design G, "Unlock"): white, back button and "Join" pill
/// on top, a soft blue card with a big lock that opens when the code is
/// complete, dots that fill while typing, two small tags, then the title,
/// the letter boxes and the Join button at the bottom.
/// Always 6 boxes: entry codes are 6 letters or numbers.
class _JoinView extends StatefulWidget {
  const _JoinView({
    super.key,
    required this.controller,
    required this.busy,
    required this.error,
    required this.onJoin,
    required this.onBack,
    required this.onPersonal,
    required this.onChanged,
    this.personal = false,
  });

  /// True: the same screen for "I have my personal code" (new phone).
  final bool personal;
  final TextEditingController controller;
  final bool busy;
  final List<Widget> error;
  final VoidCallback onJoin;
  final VoidCallback onBack;
  final VoidCallback onPersonal;
  final VoidCallback onChanged;

  @override
  State<_JoinView> createState() => _JoinViewState();
}

class _JoinViewState extends State<_JoinView> {
  final _focus = FocusNode();

  static const _ink = AppColors.ink;
  static const _soft = Color(0xFF8E97AB);
  static const _line = Color(0xFFE3E8F1);
  /// Entry codes are always 6 letters or numbers (like HSTEMP).
  static const _min = 6;
  static const _max = 6;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _focus.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  TextStyle _s(double size, {FontWeight w = FontWeight.w400, Color c = _ink, double? h}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: c, height: h);

  String get _code => widget.controller.text;

  /// Always 6 boxes.
  int get _boxes => _max;

  /// Personal code: letters and numbers typed so far (10 in a code).
  int get _typed => _code.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length;

  /// Personal code: how many of the 2 groups of 5 are complete.
  int get _parts => (_typed ~/ 5).clamp(0, 2);

  bool get _full => widget.personal ? _typed >= 10 : _code.length >= _min;

  @override
  Widget build(BuildContext context) {
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.translucent,
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _topBar(),
                    const SizedBox(height: 8),
                    // The picture. It gets smaller while typing and hides
                    // when there is no room.
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) => box.maxHeight < 130
                            ? const SizedBox.shrink()
                            : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _picture(box.maxHeight > 300 ? 300 : box.maxHeight),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      widget.personal ? 'Use your personal code' : 'Unlock Haystek Pulse',
                      textAlign: TextAlign.center,
                      style: _s(24, w: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        widget.personal
                            ? 'Enter your personal code to get your account back on this phone.\n'
                            'Don’t have it? Find it on your old phone in Profile → My personal code.'
                            : 'Enter the entry code shared with your team.\n'
                            'It’s the same for everyone.',
                        textAlign: TextAlign.center,
                        style: _s(14, c: AppColors.muted, h: 1.45),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: widget.personal ? _wordField() : _codeBoxes(),
                    ),
                    if (widget.error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: widget.error,
                        ),
                      ),
                    SizedBox(height: typing ? 14 : 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: SizedBox(
                        height: 56,
                        child: FilledButton(
                          onPressed: widget.busy ? null : widget.onJoin,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.blue,
                            disabledBackgroundColor: AppColors.blue.withValues(alpha: 0.6),
                            shape: const StadiumBorder(),
                            textStyle: _s(16, w: FontWeight.w600),
                          ),
                          child: widget.busy
                              ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                              : Text(widget.personal ? 'Sign in' : 'Join'),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(widget.personal ? 'New here?' : 'Already joined?',
                            style: _s(13.5, c: AppColors.muted)),
                        TextButton(
                          onPressed: widget.busy ? null : widget.onPersonal,
                          child: Text(
                              widget.personal ? 'Join with entry code' : 'Use personal code',
                              style: _s(13.5, c: AppColors.blue)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Back button on the left, "Join" pill on the right.
  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Material(
            color: Colors.white,
            shape: const CircleBorder(side: BorderSide(color: _line)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.busy ? null : widget.onBack,
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.chevron_left_rounded, color: _ink, size: 26),
              ),
            ),
          ),
          const Spacer(),
          Container(
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
                  child: Icon(
                      widget.personal ? Icons.phone_iphone_rounded : Icons.key_outlined,
                      size: 17,
                      color: Colors.white),
                ),
                const SizedBox(width: 9),
                Text(widget.personal ? 'Sign in' : 'Join', style: _s(16)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Soft blue card: big lock, dots under it, two small tags.
  Widget _picture(double h) {
    final filled = _code.length;
    return Container(
      height: h,
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
        alignment: Alignment.center,
        children: [
          Positioned(left: -60, top: -70, child: _blob(200)),
          Positioned(right: -30, bottom: -40, child: _blob(140)),
          // The lock and the dots, in the middle.
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: _full ? 1.06 : 1,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                child: Container(
                  width: h * 0.4,
                  height: h * 0.4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(h * 0.12),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0B1B4D), Color(0xFF14328F), AppColors.blue],
                      stops: [0, 0.55, 1],
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x662453D6),
                        blurRadius: 36,
                        offset: Offset(0, 18),
                        spreadRadius: -14,
                      ),
                    ],
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      widget.personal
                          ? (_full ? Icons.check_rounded : Icons.key_rounded)
                          : (_full ? Icons.lock_open_rounded : Icons.lock_outline_rounded),
                      key: ValueKey(_full),
                      color: Colors.white,
                      size: h * 0.18,
                    ),
                  ),
                ),
              ),
              SizedBox(height: h * 0.08),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _line),
                  boxShadow: _shadow,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < (widget.personal ? 2 : _boxes); i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        // Personal code: 2 long bars, one per group of 5.
                        width: widget.personal ? 44 : 10,
                        height: 10,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          color: i < (widget.personal ? _parts : filled)
                              ? AppColors.blue
                              : const Color(0xFFD5DEF7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            left: 14,
            top: h * 0.11,
            child: widget.personal
                ? _tag('📱', 'New phone', -0.1)
                : _tag('🏢', 'Haystek only', -0.1),
          ),
          Positioned(
            right: 0,
            top: h * 0.46,
            child: widget.personal
                ? _tag('🔁', 'Same account', 0.1)
                : _tag('🙈', 'No name', 0.1),
          ),
        ],
      ),
    );
  }

  static const _shadow = [
    BoxShadow(
      color: Color(0x332453D6),
      blurRadius: 24,
      offset: Offset(0, 12),
      spreadRadius: -12,
    ),
  ];

  Widget _tag(String emoji, String text, double angle) => Transform.rotate(
    angle: angle,
    child: Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
        boxShadow: _shadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(text, style: _s(12)),
        ],
      ),
    ),
  );

  Widget _blob(double size) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      color: Color(0x122453D6),
      shape: BoxShape.circle,
    ),
  );

  /// The letter boxes. A see-through text field lies on top, so tapping
  /// anywhere opens the keyboard and paste works.
  Widget _codeBoxes() {
    final code = _code;
    final n = _boxes;
    final focused = _focus.hasFocus;
    final gap = n > 8 ? 5.0 : 8.0;
    return SizedBox(
      height: 58,
      child: Stack(
        children: [
          Row(
            children: [
              for (var i = 0; i < n; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(child: _box(i < code.length ? code[i] : '', focused && i == code.length.clamp(0, n - 1) && code.length < _max)),
              ],
            ],
          ),
          Positioned.fill(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              autocorrect: false,
              enableSuggestions: false,
              enableInteractiveSelection: false,
              showCursor: false,
              maxLength: _max,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                // Letters and numbers only (codes like HSTEMP), 6 at most.
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                LengthLimitingTextInputFormatter(_max),
                TextInputFormatter.withFunction(
                      (old, now) => now.copyWith(text: now.text.toUpperCase()),
                ),
              ],
              onChanged: (_) => widget.onChanged(),
              onSubmitted: (_) => widget.onJoin(),
              style: const TextStyle(color: Colors.transparent, fontSize: 1),
              cursorColor: Colors.transparent,
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Personal code: one big rounded field (words are too long for boxes).
  Widget _wordField() {
    final focused = _focus.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 58,
      padding: const EdgeInsets.only(left: 16, right: 6),
      decoration: BoxDecoration(
        color: focused || _code.isNotEmpty ? Colors.white : const Color(0xFFF6F8FB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          width: 2,
          color: focused ? AppColors.blue : _line,
        ),
      ),
      alignment: Alignment.center,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              // Always in capitals, like the code on the screen.
              inputFormatters: [
                TextInputFormatter.withFunction(
                      (old, now) => now.copyWith(text: now.text.toUpperCase()),
                ),
              ],
              onChanged: (_) => widget.onChanged(),
              onSubmitted: (_) => widget.onJoin(),
              style: _s(19, w: FontWeight.w600).copyWith(letterSpacing: 1.5),
              cursorColor: AppColors.blue,
              decoration: InputDecoration(
                hintText: 'XXXXX-XXXXX',
                hintStyle: _s(19, c: const Color(0xFFC3C9D6)).copyWith(letterSpacing: 1.5),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: widget.busy ? null : _paste,
            icon: const Icon(Icons.content_paste_rounded, size: 18),
            label: const Text('Paste'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.blue,
              textStyle: _s(14, w: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  /// Paste the personal code from the clipboard.
  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim().toUpperCase();
    if (text == null || text.isEmpty) return;
    widget.controller.text = text;
    widget.controller.selection = TextSelection.collapsed(offset: text.length);
    widget.onChanged();
  }

  Widget _box(String ch, bool active) {
    final empty = ch.isEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: empty && !active ? const Color(0xFFF6F8FB) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          width: 2,
          color: active
              ? AppColors.blue
              : empty
              ? _line
              : const Color(0xFFC9D6FF),
        ),
      ),
      alignment: Alignment.center,
      child: active && empty
          ? const _BlinkCursor()
          : Text(ch, style: _s(_boxes > 8 ? 18 : 22, w: FontWeight.w600)),
    );
  }
}

/// The small blinking blue line in the active box.
class _BlinkCursor extends StatefulWidget {
  const _BlinkCursor();

  @override
  State<_BlinkCursor> createState() => _BlinkCursorState();
}

class _BlinkCursorState extends State<_BlinkCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c,
      child: Container(width: 2, height: 24, color: AppColors.blue),
    );
  }
}


/// "Welcome back": this phone already has an account. White, the logo on
/// top, a soft blue card with the person and a green tick, a short line,
/// the "Anonymous account" chip and Continue at the bottom.
class _FoundView extends StatelessWidget {
  const _FoundView({
    required this.busy,
    required this.error,
    required this.onContinue,
  });

  final bool busy;
  final String? error;
  final VoidCallback onContinue;

  static const _line = Color(0xFFE3E8F1);

  TextStyle _s(double size, {FontWeight w = FontWeight.w400, Color c = AppColors.ink, double? h}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: c, height: h);

  Widget _tag(String emoji, String text, double angle) => Transform.rotate(
    angle: angle,
    child: Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x332453D6),
            blurRadius: 24,
            offset: Offset(0, 12),
            spreadRadius: -12,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(text, style: _s(12)),
        ],
      ),
    ),
  );

  Widget _blob(double size) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      color: Color(0x122453D6),
      shape: BoxShape.circle,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  Center(child: Image.asset('assets/haystek_pulse_logo.png', height: 28)),
                  const SizedBox(height: 12),
                  // The picture card.
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 320),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.blueTint, Color(0xFFF7F9FE)],
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: LayoutBuilder(
                          builder: (context, box) {
                            final h = box.maxHeight;
                            return Stack(
                              alignment: Alignment.center,
                              children: [
                                Positioned(left: -60, top: -70, child: _blob(220)),
                                Positioned(right: -40, bottom: -50, child: _blob(160)),
                                Transform.scale(
                                  scale: (h / 220).clamp(0.8, 1.4),
                                  child: const _FoundBadge(),
                                ),
                                Positioned(
                                  left: 16,
                                  top: h * 0.12,
                                  child: _tag('📱', 'This phone', -0.1),
                                ),
                                Positioned(
                                  right: 12,
                                  bottom: h * 0.14,
                                  child: _tag('🙈', 'No name', 0.08),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Welcome back',
                    textAlign: TextAlign.center,
                    style: _s(26, w: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your account is on this phone.\nNo code needed.',
                    textAlign: TextAlign.center,
                    style: _s(14.5, c: AppColors.muted, h: 1.5),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.blueTint,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.blue),
                          const SizedBox(width: 6),
                          Text('Anonymous account', style: _s(12.5, c: AppColors.blue)),
                        ],
                      ),
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                      child: _ErrorBox(message: error!),
                    ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
                    child: SizedBox(
                      height: 56,
                      child: FilledButton(
                        onPressed: busy ? null : onContinue,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.blue,
                          disabledBackgroundColor: AppColors.blue.withValues(alpha: 0.6),
                          shape: const StadiumBorder(),
                          textStyle: _s(16, w: FontWeight.w600),
                        ),
                        child: busy
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : const Text('Continue'),
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


/// "Your account moved to another phone": shown on the old phone after
/// the personal code was used on a new one. This phone is signed out and
/// freed.
class _MovedView extends StatelessWidget {
  const _MovedView({required this.onOk, required this.onPersonal});

  final VoidCallback onOk;
  final VoidCallback onPersonal;

  static const _line = Color(0xFFE3E8F1);

  TextStyle _s(double size, {FontWeight w = FontWeight.w400, Color c = AppColors.ink, double? h}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: c, height: h);

  Widget _phone(String label, bool isNew) => Opacity(
    opacity: isNew ? 1 : 0.55,
    child: Container(
      width: 92,
      height: 140,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isNew ? const Color(0xFFC9D6FF) : _line, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x332453D6),
            blurRadius: 24,
            offset: Offset(0, 12),
            spreadRadius: -12,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isNew ? AppColors.blue : AppColors.blueTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isNew ? Icons.person_outline_rounded : Icons.logout_rounded,
              size: 22,
              color: isNew ? Colors.white : AppColors.blue,
            ),
          ),
          const SizedBox(height: 8),
          Text(label, style: _s(11.5, c: const Color(0xFF8E97AB))),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: Image.asset('assets/haystek_pulse_logo.png', height: 28)),
                    const SizedBox(height: 16),
                    Container(
                      height: 230,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppColors.blueTint, Color(0xFFF7F9FE)],
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _phone('This phone', false),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 14),
                            child: Icon(Icons.arrow_forward_rounded,
                                color: AppColors.blue, size: 28),
                          ),
                          _phone('Other phone', true),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Your account moved\nto another phone',
                      textAlign: TextAlign.center,
                      style: _s(24, w: FontWeight.w600, h: 1.25),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your personal code was used on another phone, so this '
                          'phone was signed out. One account works on one phone '
                          'at a time.',
                      textAlign: TextAlign.center,
                      style: _s(14.5, c: AppColors.muted, h: 1.5),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F8FB),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'Wasn’t you? Sign in again with your personal code to '
                            'bring it back here, and keep the code private.',
                        textAlign: TextAlign.center,
                        style: _s(13, c: AppColors.muted, h: 1.45),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 56,
                      child: FilledButton(
                        onPressed: onOk,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.blue,
                          shape: const StadiumBorder(),
                          textStyle: _s(16, w: FontWeight.w600),
                        ),
                        child: const Text('OK'),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: onPersonal,
                      child: Text('Sign in with personal code',
                          style: _s(14, c: AppColors.blue)),
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