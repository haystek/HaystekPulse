import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

TextStyle _t(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.ink,
  double? height,
}) =>
    GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );

/// After sign-up: "Check your email". Checks by itself every few seconds,
/// so after tapping the link the app moves on without a tap here.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, required this.email});

  final String email;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen>
    with WidgetsBindingObserver {
  Timer? _poll;
  bool _busy = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _check(quiet: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from the email app: check straight away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check(quiet: true);
  }

  Future<void> _check({bool quiet = false}) async {
    if (_busy) return;
    if (!quiet) setState(() => _busy = true);
    try {
      final ok = await AuthService.instance.checkVerified();
      // When verified, AuthGate moves on by itself.
      if (!ok && !quiet && mounted) {
        setState(() => _note = 'Not verified yet. Please tap the link in the '
            'email first.');
      }
    } catch (e) {
      if (!quiet && mounted) {
        setState(() => _note = AuthService.messageFor(e));
      }
    } finally {
      if (!quiet && mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    try {
      await AuthService.instance.resendVerification();
      if (mounted) setState(() => _note = 'Sent again. Please check your inbox '
          'and spam folder.');
    } catch (e) {
      if (mounted) setState(() => _note = AuthService.messageFor(e));
    }
  }

  /// First name for "Almost there, Shiva."
  String get _firstName {
    final name = (AuthService.instance.pendingName ??
            FirebaseAuth.instance.currentUser?.displayName ??
            '')
        .trim();
    return name.isEmpty ? '' : name.split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) {
    final first = _firstName;
    final admin = AuthService.instance.pendingAdmin == true;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Step 2 of 3', style: _t(13, color: AppColors.blue)),
                        const SizedBox(height: 4),
                        Text(
                          'Check your email',
                          style: _t(24, weight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          first.isEmpty ? 'Almost there.' : 'Almost there, $first.',
                          style: _t(14.5, color: AppColors.muted),
                        ),
                        const SizedBox(height: 22),
                        // The three steps, the current one in blue.
                        Container(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F8FB),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Column(
                            children: [
                              _Step(
                                n: 1,
                                state: _StepState.done,
                                title: 'Account created',
                                sub: widget.email,
                              ),
                              const _Step(
                                n: 2,
                                state: _StepState.now,
                                title: 'Verify your email',
                                sub: 'Tap the link we sent. Check Spam too.',
                              ),
                              _Step(
                                n: 3,
                                state: _StepState.later,
                                title: 'You’re in',
                                sub: admin
                                    ? 'Then the admin home opens.'
                                    : 'Your backup code, then home.',
                                last: true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF6E5),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.lightbulb_outline,
                                  size: 17, color: Color(0xFF8A5A00)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'The app moves on by itself once you tap '
                                  'the link.',
                                  style: _t(13, color: const Color(0xFF8A5A00), height: 1.45),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Bottom: waiting line, the button, and the two links.
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // A short message (not verified yet, sent again…),
                      // just above the button where the person looks.
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _note == null
                            ? const SizedBox.shrink()
                            : Container(
                                key: ValueKey(_note),
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF6F8FB),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.info_outline_rounded,
                                        size: 17, color: AppColors.blue),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _note!,
                                        style: _t(13, color: const Color(0xFF344054), height: 1.4),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const _PulseDot(),
                          const SizedBox(width: 10),
                          Text('Waiting for you to tap the link…',
                              style: _t(13, color: const Color(0xFF5F6A84))),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _GradientButton(
                        onTap: _busy ? null : () => _check(),
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text("I've verified",
                                style: _t(16, weight: FontWeight.w500, color: Colors.white)),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          TextButton(
                            onPressed: _resend,
                            child: Text('Send again', style: _t(13.5, color: AppColors.blue)),
                          ),
                          const Spacer(),
                          Text('Wrong email?', style: _t(13.5, color: const Color(0xFF8E97AB))),
                          TextButton(
                            onPressed: AuthService.instance.startOver,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                            ),
                            child: Text('Start over', style: _t(13.5, color: AppColors.blue)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small green dot that gently grows and shrinks, like breathing,
/// to show the app is waiting.
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF16A34A);
    return SizedBox(
      width: 18,
      height: 18,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final v = Curves.easeInOut.transform(_c.value);
          return Stack(
            alignment: Alignment.center,
            children: [
              // Soft ring that grows and fades.
              Container(
                width: 8 + 10 * v,
                height: 8 + 10 * v,
                decoration: BoxDecoration(
                  color: green.withValues(alpha: 0.22 * (1 - v) + 0.06),
                  shape: BoxShape.circle,
                ),
              ),
              // The dot, zooming in and out a little.
              Transform.scale(
                scale: 0.85 + 0.25 * v,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: green,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _StepState { done, now, later }

/// One step: a round mark (✓, number in blue, or grey), a line down to
/// the next step, the title and a short line.
class _Step extends StatelessWidget {
  const _Step({
    required this.n,
    required this.state,
    required this.title,
    required this.sub,
    this.last = false,
  });

  final int n;
  final _StepState state;
  final String title;
  final String sub;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final done = state == _StepState.done;
    final now = state == _StepState.now;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done
                      ? const Color(0xFF16A34A)
                      : now
                          ? AppColors.blue
                          : const Color(0xFFEDF0F6),
                  shape: BoxShape.circle,
                  boxShadow: now
                      ? const [BoxShadow(color: AppColors.blueTint, spreadRadius: 5)]
                      : null,
                ),
                child: done
                    ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                    : Text(
                        '$n',
                        style: _t(13, color: now ? Colors.white : const Color(0xFF8E97AB)),
                      ),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    color: const Color(0xFFE3E8F1),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 3, bottom: last ? 16 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: _t(
                      15,
                      weight: now ? FontWeight.w500 : FontWeight.w400,
                      color: state == _StepState.later
                          ? const Color(0xFF8E97AB)
                          : AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(sub, style: _t(13, color: const Color(0xFF8E97AB), height: 1.4)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The big button in the same navy-to-blue as Sign in.
class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.7 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFF0B1B4D), Color(0xFF14328F), AppColors.blue],
            stops: [0, 0.5, 1],
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(height: 54, child: Center(child: child)),
          ),
        ),
      ),
    );
  }
}

/// After the email is verified: saves the person to `employees`.
/// Right after sign-up this happens by itself (the details are still in
/// memory). If the app was closed in between, it asks again for the
/// name and Employee / Admin (and the admin code).
class FinishProfileScreen extends StatefulWidget {
  const FinishProfileScreen({super.key});

  @override
  State<FinishProfileScreen> createState() => _FinishProfileScreenState();
}

class _FinishProfileScreenState extends State<FinishProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  final _code = TextEditingController();
  bool _admin = false;
  bool _hideCode = true;
  bool _busy = false;
  String? _error;

  /// True while saving by itself: shows a spinner, not the form.
  bool _auto = false;

  @override
  void initState() {
    super.initState();
    final auth = AuthService.instance;
    // The name from the sign-up form, or the one saved with the login
    // (still there after the app was closed).
    final known = (auth.pendingName ??
            FirebaseAuth.instance.currentUser?.displayName ??
            '')
        .trim();
    _name = TextEditingController(text: known);
    // Email sign-up is only for admins now (employees join with an entry
    // code), so this is always an admin account.
    _admin = true;
    _code.text = auth.pendingAdminCode ?? '';
    // Saves by itself only right after sign-up, when the choice
    // (Employee / Admin) is still known. Otherwise the person picks again.
    if (known.length >= 2 && auth.pendingAdmin != null) {
      _auto = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _save());
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() == false) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Login deleted in the console: signs out instead.
      if (!await AuthService.instance.stillValid()) return;
      await AuthService.instance.createMyProfile(
        name: _name.text,
        admin: _admin,
        adminCode: _code.text,
      );
      // AuthGate shows the home screen by itself.
    } catch (e) {
      // Show the form with the error, so they can try again.
      if (mounted) {
        setState(() {
          _auto = false;
          _error = AuthService.messageFor(e);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Saving by itself: just a spinner, the person sees no extra screen.
    if (_auto) {
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Almost done',
                      style: _t(22, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Your email is verified. Check your details and '
                      'continue.',
                      style: _t(14, color: AppColors.muted, height: 1.45),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Full name'),
                      validator: (v) => (v == null || v.trim().length < 2)
                          ? 'Enter your name'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    if (_admin) ...[
                      TextFormField(
                        controller: _code,
                        obscureText: _hideCode,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: 'Admin entry code',
                          helperText: 'From the HR mail (only for admins)',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _hideCode
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 20,
                            ),
                            onPressed: () =>
                                setState(() => _hideCode = !_hideCode),
                          ),
                        ),
                        validator: (v) => (_admin && (v == null || v.trim().isEmpty))
                            ? 'Enter the admin entry code'
                            : null,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: _t(13.5,
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        minimumSize: const Size.fromHeight(54),
                        shape: const StadiumBorder(),
                        textStyle: _t(16, weight: FontWeight.w500),
                      ),
                      child: _busy
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
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: AuthService.instance.signOut,
                      child: const Text('Sign out'),
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

/// "I am: Employee / Admin" as two rounded choices. Used on sign-up and
/// on "Almost done".
class RoleChoice extends StatelessWidget {
  const RoleChoice({super.key, required this.admin, required this.onChanged});

  final bool admin;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget option(String label, IconData icon, bool value) {
      final selected = admin == value;
      return Expanded(
        child: Material(
          color: selected ? AppColors.blueTint : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: selected ? AppColors.blue : const Color(0xFFE3E8F1),
              width: 1.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onChanged(value),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selected ? AppColors.blue : const Color(0xFF8E97AB),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: _t(
                      14.5,
                      weight: FontWeight.w500,
                      color: selected ? AppColors.blue : AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text('I am', style: _t(13, color: AppColors.muted)),
        ),
        Row(
          children: [
            option('Employee', Icons.person_outline, false),
            const SizedBox(width: 10),
            option('Admin', Icons.admin_panel_settings_outlined, true),
          ],
        ),
      ],
    );
  }
}
