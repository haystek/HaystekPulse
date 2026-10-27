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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: AppColors.blueTint,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.mark_email_unread_outlined,
                        size: 32,
                        color: AppColors.blue,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Check your email',
                    textAlign: TextAlign.center,
                    style: _t(22, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'We sent a link to '),
                        TextSpan(
                          text: widget.email,
                          style: _t(14.5, weight: FontWeight.w500),
                        ),
                        const TextSpan(
                          text: '.\nTap the link, then come back here.',
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    style: _t(14.5, color: AppColors.muted, height: 1.5),
                  ),
                  const SizedBox(height: 26),
                  FilledButton(
                    onPressed: _busy ? null : () => _check(),
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
                        : const Text("I've verified"),
                  ),
                  if (_note != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _note!,
                      textAlign: TextAlign.center,
                      style: _t(13.5, color: AppColors.muted, height: 1.4),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _resend,
                    child: const Text('Send the email again'),
                  ),
                  TextButton(
                    onPressed: AuthService.instance.startOver,
                    child: const Text('Wrong email? Start over'),
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

/// After the email is verified: saves the person to `employees`.
/// Right after sign-up this happens by itself (the details are still in
/// memory). If the app was closed in between, it asks for the name.
class FinishProfileScreen extends StatefulWidget {
  const FinishProfileScreen({super.key});

  @override
  State<FinishProfileScreen> createState() => _FinishProfileScreenState();
}

class _FinishProfileScreenState extends State<FinishProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
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
    if (known.length >= 2) {
      _auto = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _save());
    }
  }

  @override
  void dispose() {
    _name.dispose();
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
      await AuthService.instance.createMyProfile(name: _name.text);
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
                      'Your email is verified. Check your name and '
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