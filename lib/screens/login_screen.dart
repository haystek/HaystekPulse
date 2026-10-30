import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'verify_email_screen.dart' show RoleChoice;

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
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _adminCode = TextEditingController();
  bool _busy = false;

  /// Create account: Employee (false) or Admin (true).
  bool _admin = false;
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
      _signUpMode = true;
      _name.text = auth.signUpName ?? '';
      _email.text = auth.signUpEmail ?? '';
      auth.openSignUp = false;
      auth.signUpEmail = null;
      auth.signUpName = null;
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _adminCode.dispose();
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
    if (_error != null) setState(() => _error = null);
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

  /// The form under the blue block: sign in, or reset password.
  Widget _form(ThemeData theme) {
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
            Text('Create account', style: _h(24)),
            const SizedBox(height: 2),
            Text(
              'Use your Haystek office email (${AuthService.officeDomain}).',
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
            const SizedBox(height: 16),
            RoleChoice(
              admin: _admin,
              onChanged: _busy ? (_) {} : (v) => setState(() => _admin = v),
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
                    style: GoogleFonts.inter(fontSize: 15.5, color: AppColors.ink),
                    decoration: _plain('Admin code'),
                    validator: (v) => (_admin && (v == null || v.trim().isEmpty))
                        ? 'Enter the admin code'
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
                  'Only for admins. Ask your manager for the code.',
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
          Text('Sign in', style: _h(24)),
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
            'New here?',
            'Create account',
            _busy ? null : () => _toggleSignUp(true),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = MediaQuery.of(context).padding.top;
    // Small top while typing or on Create account, so everything fits.
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    final compact = typing || _signUpMode;
    // White clock and battery icons on the dark top.
    // Phone back button: from Create account or Reset password, go back to
    // Sign in instead of closing the app.
    // On Sign in: press back twice to close the app (same as the home
    // screens).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _busy) return;
        if (_resetMode) {
          _closeReset();
        } else if (_signUpMode) {
          _toggleSignUp(false);
        } else {
          _backOnSignIn();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: _withInter(context, Scaffold(
          backgroundColor: Colors.white,
          // Tap anywhere outside the fields to close the keyboard.
          body: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.translucent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Night-sky top. It stays in place: only the white part below
                // scrolls. On Create account and while typing, only the logo
                // shows, so the form fits on the screen.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.fromLTRB(
                    28,
                    top + (compact ? 16 : 36),
                    28,
                    compact ? 52 : 72,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF0B1B4D),
                        Color(0xFF14328F),
                        AppColors.blue,
                      ],
                      stops: [0, 0.55, 1],
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Image.asset(
                          'assets/haystek_pulse_logo.png',
                          height: 32,
                          fit: BoxFit.contain,
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: compact
                            ? const SizedBox(width: double.infinity)
                            : Column(
                          children: [
                            const SizedBox(height: 30),
                            const SizedBox(
                              width: 300,
                              height: 56,
                              child: _HeartbeatLine(),
                            ),
                            const SizedBox(height: 22),
                            Text(
                              'Your week, heard.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                color: const Color(0xFFC9D6FF),
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // The white sheet with round top corners, pulled up a little
                // over the dark top. Only this part scrolls.
                Expanded(
                  child: Transform.translate(
                    offset: const Offset(0, -32),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: LayoutBuilder(
                        builder: (context, box) => SingleChildScrollView(
                          child: ConstrainedBox(
                            // At least as tall as the space, so the footer
                            // sits at the bottom when there is room.
                            constraints: BoxConstraints(minHeight: box.maxHeight),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Align(
                                  alignment: Alignment.topCenter,
                                  child: ConstrainedBox(
                                    constraints:
                                    const BoxConstraints(maxWidth: 480),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          24, 28, 24, 0),
                                      child: _form(theme),
                                    ),
                                  ),
                                ),
                                // Hidden while typing, to give the fields
                                // more room.
                                if (!typing)
                                  Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      24,
                                      20,
                                      24,
                                      // The sheet is moved up 32, so add it
                                      // back here to stay above the home bar.
                                      48 + MediaQuery.of(context).padding.bottom,
                                    ),
                                    child: const _Footer(),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        )),
      ),
    );
  }
}

/// A heartbeat line like on a hospital monitor: a faint line with two
/// beats, and a bright trail with a glowing dot that runs along it again
/// and again. No heart at the end.
class _HeartbeatLine extends StatefulWidget {
  const _HeartbeatLine();

  @override
  State<_HeartbeatLine> createState() => _HeartbeatLineState();
}

class _HeartbeatLineState extends State<_HeartbeatLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _run,
        builder: (context, _) => CustomPaint(
          painter: _HeartbeatPainter(_run.value),
        ),
      ),
    );
  }
}

class _HeartbeatPainter extends CustomPainter {
  _HeartbeatPainter(this.t);

  /// 0.0 to 1.0: where the bright dot is along the line.
  final double t;

  /// One beat, as (x, y) from 0 to 1: flat, a small bump, the tall spike,
  /// a small wave, flat again.
  static const List<Offset> _beat = [
    Offset(0.00, 0.55),
    Offset(0.28, 0.55),
    Offset(0.34, 0.45),
    Offset(0.40, 0.55),
    Offset(0.46, 0.55),
    Offset(0.50, 0.68),
    Offset(0.55, 0.04),
    Offset(0.60, 0.96),
    Offset(0.64, 0.55),
    Offset(0.74, 0.55),
    Offset(0.81, 0.38),
    Offset(0.88, 0.55),
    Offset(1.00, 0.55),
  ];

  Path _path(Size size) {
    const beats = 2;
    final w = size.width / beats;
    final path = Path();
    for (var b = 0; b < beats; b++) {
      for (var i = 0; i < _beat.length; i++) {
        final p = Offset(b * w + _beat[i].dx * w, _beat[i].dy * size.height);
        if (b == 0 && i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _path(size);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // The whole line, faint.
    canvas.drawPath(path, line..color = Colors.white.withValues(alpha: 0.18));

    final metric = path.computeMetrics().first;
    final length = metric.length;
    final head = length * t;
    final trail = length * 0.35;

    // The bright trail behind the dot, fading out at its end.
    const pieces = 10;
    for (var i = 0; i < pieces; i++) {
      final from = head - trail * (1 - i / pieces);
      final to = head - trail * (1 - (i + 1) / pieces);
      if (to <= 0) continue;
      canvas.drawPath(
        metric.extractPath(from.clamp(0.0, length), to.clamp(0.0, length)),
        line
          ..strokeWidth = 2.4
          ..color = Colors.white.withValues(alpha: 0.15 + 0.85 * (i + 1) / pieces),
      );
    }

    // The dot, with a soft glow.
    final dot = metric.getTangentForOffset(head.clamp(0.0, length))?.position;
    if (dot != null) {
      canvas.drawCircle(
        dot,
        9,
        Paint()..color = const Color(0xFF7FA2FF).withValues(alpha: 0.35),
      );
      canvas.drawCircle(dot, 4, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_HeartbeatPainter old) => old.t != t;
}

/// The big Sign in button, in the same navy-to-blue as the top.
/// Faded while it cannot be pressed.
class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.onPressed, required this.child});

  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.6 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFF0B1B4D), Color(0xFF14328F), AppColors.blue],
            stops: [0, 0.5, 1],
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              height: 54,
              child: Center(
                child: DefaultTextStyle(
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
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