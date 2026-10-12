import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/heartbeat_monitor.dart';
import '../widgets/ui.dart';

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
      FontWeight weight = FontWeight.w800,
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

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  /// True on the "Reset password" step, where only the email shows.
  bool _resetMode = false;

  /// True after the reset link was sent.
  bool _resetSent = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _looksLikeEmail(String? v) =>
      v != null && v.trim().contains('@') && v.trim().contains('.');

  Future<void> _signIn() async {
    FocusScope.of(context).unfocus(); // closes the keyboard
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

  /// Opens the "Reset password" step. Only the email field shows.
  void _openReset() {
    FocusScope.of(context).unfocus();
    setState(() {
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

  /// The form under the blue block: sign in, or reset password.
  Widget _form(ThemeData theme) {
    final error = _error == null
        ? const <Widget>[]
        : [
      const SizedBox(height: 12),
      Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
    ];

    final emailField = TextFormField(
      controller: _email,
      keyboardType: TextInputType.emailAddress,
      textInputAction:
      _resetMode ? TextInputAction.done : TextInputAction.next,
      autocorrect: false,
      autofillHints: const [AutofillHints.email],
      onFieldSubmitted: _resetMode ? (_) => _sendReset() : null,
      decoration: const InputDecoration(labelText: 'Office email'),
      validator: (v) => _looksLikeEmail(v) ? null : 'Enter your office email',
    );

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
          Text(
            'Check your email',
            textAlign: TextAlign.center,
            style: _h(24),
          ),
          const SizedBox(height: 10),
          Text(
            'If ${_email.text.trim()} is registered, we have sent a link to '
                'set a new password. Please check your inbox and spam folder.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 15,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 26),
          FilledButton(
            onPressed: _closeReset,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            child: const Text('Back to sign in'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : _sendReset,
            child: const Text('Send the link again'),
          ),
        ],
      );
    }

    // Step 1 of reset: email only.
    if (_resetMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Reset password', style: _h(26)),
          const SizedBox(height: 8),
          const Text(
            'Enter your office email. We will send you a link to set a new '
                'password.',
            style: TextStyle(color: AppColors.muted, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 18),
          emailField,
          ...error,
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _sendReset,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            child: _busy ? _busyDot() : const Text('Send reset link'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : _closeReset,
            child: const Text('Back to sign in'),
          ),
        ],
      );
    }

    // Normal sign in.
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Sign in', style: _h(26)),
          const SizedBox(height: 18),
          emailField,
          const SizedBox(height: 16),
          TextFormField(
            controller: _password,
            obscureText: _hidePassword,
            autofillHints: const [AutofillHints.password],
            onFieldSubmitted: (_) => _signIn(),
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                icon: Icon(
                  _hidePassword ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () =>
                    setState(() => _hidePassword = !_hidePassword),
              ),
            ),
            validator: (v) =>
            (v == null || v.isEmpty) ? 'Enter your password' : null,
          ),
          ...error,
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _signIn,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            child: _busy ? _busyDot() : const Text('Sign in'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : _openReset,
            child: const Text('Forgot password?'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Dark clock and battery icons on the light top.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: _withInter(context, Scaffold(
        // Tap anywhere outside the fields to close the keyboard.
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.translucent,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Light top: a soft blue fade, a faint pulse line, and
                    // the real logo in the middle.
                    Container(
                      height: 300,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFFF2F6FF), Colors.white],
                        ),
                      ),
                      child: Stack(
                        children: [
                          const Positioned(
                            left: 0,
                            right: 0,
                            top: 40,
                            height: 120,
                            child: HeartbeatMonitor(),
                          ),
                          Positioned(
                            left: 28,
                            right: 28,
                            bottom: 36,
                            child: Column(
                              children: [
                                Image.asset(
                                  'assets/haystek_pulse_logo.png',
                                  height: 52,
                                  fit: BoxFit.contain,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Your week, heard.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _form(theme),
                          const SizedBox(height: 24),
                          const Text(
                            'Haystek Technologies',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      )),
    );
  }
}