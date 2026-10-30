import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/employee.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/vault_service.dart';
import '../theme/app_theme.dart';
import 'employee_home_screen.dart';

TextStyle _t(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.ink,
  double? height,
  double? letterSpacing,
}) =>
    GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );

const Color _soft = Color(0xFF8E97AB);
const Color _line = Color(0xFFE3E8F1);

enum _Step { checking, askPassword, working, showCode, needBackup, error, ready }

/// Employees only: opens the locked history before the home screen.
///
/// 1. Key saved on this phone       -> home at once.
/// 2. Password just typed (sign in)  -> open with it. First time: make
///    the vault and show the backup code once.
/// 3. Otherwise                      -> ask the password.
/// 4. Password was reset             -> ask the backup code.
class VaultGate extends StatefulWidget {
  const VaultGate({super.key, required this.employee});

  final Employee employee;

  @override
  State<VaultGate> createState() => _VaultGateState();
}

class _VaultGateState extends State<VaultGate> {
  final _vault = VaultService.instance;
  _Step _step = _Step.checking;
  String? _password;
  String? _code;
  String? _error;

  String get _uid => widget.employee.uid;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (_vault.isReady || await _vault.openSaved(_uid)) {
      _ready();
      return;
    }
    final pending = AuthService.instance.pendingPassword;
    if (pending != null) {
      await _openWith(pending);
    } else if (mounted) {
      setState(() => _step = _Step.askPassword);
    }
  }

  Future<void> _openWith(String password) async {
    setState(() {
      _step = _Step.working;
      _error = null;
      _password = password;
    });
    try {
      final r = await _vault.openWithPassword(_uid, password);
      if (!mounted) return;
      if (r == VaultOpen.needsBackup) {
        setState(() => _step = _Step.needBackup);
        return;
      }
      final code = _vault.lastNewCode;
      if (code != null) {
        _vault.lastNewCode = null;
        setState(() {
          _code = code;
          _step = _Step.showCode;
        });
        return;
      }
      _ready();
    } catch (e) {
      debugPrint('[VaultGate] $e');
      if (mounted) setState(() => _step = _Step.error);
    }
  }

  void _ready() {
    AuthService.instance.pendingPassword = null;
    _password = null;
    NotificationService.instance.start(widget.employee);
    if (mounted) setState(() => _step = _Step.ready);
  }

  /// Asked password: check it with Firebase first, so a typo is not
  /// mistaken for "password was reset".
  Future<void> _submitPassword(String password) async {
    setState(() {
      _step = _Step.working;
      _error = null;
    });
    try {
      await AuthService.instance.checkPassword(password);
    } catch (e) {
      if (!mounted) return;
      final wrong = e is FirebaseAuthException &&
          (e.code == 'wrong-password' || e.code == 'invalid-credential');
      setState(() {
        _step = _Step.askPassword;
        _error = wrong ? 'This password is not correct.' : AuthService.messageFor(e);
      });
      return;
    }
    await _openWith(password);
  }

  Future<void> _submitBackup(String code) async {
    final password = _password;
    if (password == null) {
      setState(() => _step = _Step.askPassword);
      return;
    }
    setState(() {
      _step = _Step.working;
      _error = null;
    });
    try {
      final ok = await _vault.openWithBackup(_uid, code, password);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _step = _Step.needBackup;
          _error = 'This backup code is not correct.';
        });
        return;
      }
      _ready();
    } catch (e) {
      debugPrint('[VaultGate] $e');
      if (mounted) setState(() => _step = _Step.error);
    }
  }

  Future<void> _startFresh() async {
    final password = _password;
    if (password == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text('Start a new history?'),
        content: const Text(
          'Your old posts stay with admin, but they will not show in '
          'My Feedback any more. This can’t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.blue),
            child: const Text('Start new'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _step = _Step.working);
    try {
      await _vault.startFresh(_uid, password);
      final code = _vault.lastNewCode;
      _vault.lastNewCode = null;
      if (!mounted) return;
      setState(() {
        _code = code;
        _step = _Step.showCode;
      });
    } catch (e) {
      debugPrint('[VaultGate] $e');
      if (mounted) setState(() => _step = _Step.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _Step.ready:
        return EmployeeHomeScreen(employee: widget.employee);
      case _Step.checking:
      case _Step.working:
        return const _Busy();
      case _Step.showCode:
        return BackupCodeScreen(
          code: _code ?? '',
          firstTime: true,
          onDone: _ready,
        );
      case _Step.askPassword:
        return _AskScreen(
          key: const ValueKey('ask-password'),
          icon: Icons.lock_outline_rounded,
          title: 'Unlock your history',
          text: 'Your posts are locked with your password. Enter it to '
              'open them on this phone.',
          label: 'Password',
          obscure: true,
          button: 'Unlock',
          error: _error,
          onSubmit: _submitPassword,
        );
      case _Step.needBackup:
        return _AskScreen(
          key: const ValueKey('ask-backup'),
          icon: Icons.key_outlined,
          title: 'Enter your backup code',
          text: 'Your password was reset, so your history needs your '
              'backup code (the one you saved at sign-up).',
          label: 'Backup code',
          hint: 'XXXX-XXXX-XXXX-XXXX',
          obscure: false,
          button: 'Unlock',
          error: _error,
          onSubmit: _submitBackup,
          secondary: 'I don’t have it. Start a new history',
          onSecondary: _startFresh,
        );
      case _Step.error:
        return _AskScreen(
          key: const ValueKey('ask-error'),
          icon: Icons.wifi_off_rounded,
          title: 'Could not open your history',
          text: 'Please check your internet connection and try again.',
          button: 'Try again',
          onSubmit: (_) {
            final p = _password ?? AuthService.instance.pendingPassword;
            if (p != null) {
              _openWith(p);
            } else {
              setState(() => _step = _Step.askPassword);
            }
          },
        );
    }
  }
}

class _Busy extends StatelessWidget {
  const _Busy();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.blue,
              ),
            ),
            const SizedBox(height: 14),
            Text('Opening your history…', style: _t(14, color: _soft)),
          ],
        ),
      ),
    );
  }
}

/// A simple screen with one field (or none) and one button.
class _AskScreen extends StatefulWidget {
  const _AskScreen({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    required this.button,
    required this.onSubmit,
    this.label,
    this.hint,
    this.obscure = false,
    this.error,
    this.secondary,
    this.onSecondary,
    this.onCancel,
  });

  final IconData icon;
  final String title;
  final String text;
  final String button;
  final ValueChanged<String> onSubmit;

  /// Null: no field, just the button.
  final String? label;
  final String? hint;
  final bool obscure;
  final String? error;
  final String? secondary;
  final VoidCallback? onSecondary;

  /// Set: shows "Cancel" instead of "Sign out" at the bottom.
  final VoidCallback? onCancel;

  @override
  State<_AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<_AskScreen> {
  final _field = TextEditingController();
  bool _hide = true;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _go() {
    if (widget.label != null && _field.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    widget.onSubmit(_field.text);
  }

  @override
  Widget build(BuildContext context) {
    final hasField = widget.label != null;
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
                      child: Icon(widget.icon, size: 32, color: AppColors.blue),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: _t(22, weight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.text,
                    textAlign: TextAlign.center,
                    style: _t(14.5, color: AppColors.muted, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  if (hasField)
                    TextField(
                      controller: _field,
                      obscureText: widget.obscure && _hide,
                      autocorrect: false,
                      textCapitalization: widget.obscure
                          ? TextCapitalization.none
                          : TextCapitalization.characters,
                      onSubmitted: (_) => _go(),
                      style: _t(16, letterSpacing: widget.obscure ? null : 1.5),
                      decoration: InputDecoration(
                        labelText: widget.label,
                        hintText: widget.hint,
                        suffixIcon: widget.obscure
                            ? IconButton(
                                icon: Icon(
                                  _hide
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  size: 20,
                                  color: _soft,
                                ),
                                onPressed: () => setState(() => _hide = !_hide),
                              )
                            : null,
                      ),
                    ),
                  if (widget.error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      widget.error!,
                      textAlign: TextAlign.center,
                      style: _t(13.5, color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _go,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.blue,
                      minimumSize: const Size.fromHeight(54),
                      shape: const StadiumBorder(),
                      textStyle: _t(16, weight: FontWeight.w500),
                    ),
                    child: Text(widget.button),
                  ),
                  if (widget.secondary != null) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: widget.onSecondary,
                      child: Text(widget.secondary!, textAlign: TextAlign.center),
                    ),
                  ],
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: widget.onCancel ?? AuthService.instance.signOut,
                    style: TextButton.styleFrom(foregroundColor: _soft),
                    child: Text(widget.onCancel != null ? 'Cancel' : 'Sign out'),
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

/// Shows the backup code once, with Copy, and asks the last 4 letters
/// to make sure it was saved.
class BackupCodeScreen extends StatefulWidget {
  const BackupCodeScreen({
    super.key,
    required this.code,
    required this.onDone,
    this.firstTime = false,
  });

  final String code;
  final VoidCallback onDone;

  /// True right after sign-up (also explains what it is for).
  final bool firstTime;

  @override
  State<BackupCodeScreen> createState() => _BackupCodeScreenState();
}

class _BackupCodeScreenState extends State<BackupCodeScreen> {
  final _last4 = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _last4.dispose();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Backup code copied')),
    );
  }

  void _done() {
    final want = VaultService.normalizeCode(widget.code);
    final typed = VaultService.normalizeCode(_last4.text);
    if (typed != want.substring(want.length - 4)) {
      setState(() => _error = 'That doesn’t match. Please check the code.');
      return;
    }
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
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
                          Icons.key_outlined,
                          size: 32,
                          color: AppColors.blue,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Your backup code',
                      textAlign: TextAlign.center,
                      style: _t(22, weight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.firstTime
                          ? 'Your history is locked with your password. If you '
                              'ever forget your password, this code is the only '
                              'way to get your history back.'
                          : 'Your old code no longer works. Save this new one.',
                      textAlign: TextAlign.center,
                      style: _t(14.5, color: AppColors.muted, height: 1.5),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F8FB),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: _line, width: 1.5),
                      ),
                      child: SelectableText(
                        widget.code,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.robotoMono(
                          fontSize: 20,
                          letterSpacing: 1.5,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _copy,
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copy'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.blue,
                        minimumSize: const Size.fromHeight(46),
                        side: const BorderSide(color: _line, width: 1.5),
                        shape: const StadiumBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF6E5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        'Save it somewhere safe: a screenshot, your notes, or '
                        'paper. We can’t recover your history without it — '
                        'not admin, not the developer.',
                        style: _t(13, color: const Color(0xFF8A5A00), height: 1.45),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _last4,
                      maxLength: 4,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      onSubmitted: (_) => _done(),
                      style: _t(16, letterSpacing: 2),
                      decoration: const InputDecoration(
                        labelText: 'Type the last 4 letters to confirm',
                        counterText: '',
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _error!,
                        style: _t(13.5, color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _done,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        minimumSize: const Size.fromHeight(54),
                        shape: const StadiumBorder(),
                        textStyle: _t(16, weight: FontWeight.w500),
                      ),
                      child: const Text('I saved it'),
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

/// Profile -> Backup code: check the password, make a new code, show it.
class NewBackupCodeScreen extends StatefulWidget {
  const NewBackupCodeScreen({super.key});

  @override
  State<NewBackupCodeScreen> createState() => _NewBackupCodeScreenState();
}

class _NewBackupCodeScreenState extends State<NewBackupCodeScreen> {
  bool _busy = false;
  String? _error;
  String? _code;

  Future<void> _make(String password) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.checkPassword(password);
      final code = await VaultService.instance.newBackupCode();
      if (mounted) setState(() => _code = code);
    } catch (e) {
      if (!mounted) return;
      final wrong = e is FirebaseAuthException &&
          (e.code == 'wrong-password' || e.code == 'invalid-credential');
      setState(() => _error = wrong
          ? 'This password is not correct.'
          : 'Could not make a new code. Please check your internet.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    if (code != null) {
      return BackupCodeScreen(
        code: code,
        onDone: () => Navigator.of(context).pop(),
      );
    }
    if (_busy) return const _Busy();
    return _AskScreen(
      icon: Icons.key_outlined,
      title: 'New backup code',
      text: 'Enter your password. You’ll get a new code, and the old one '
          'stops working.',
      label: 'Password',
      obscure: true,
      button: 'Make new code',
      error: _error,
      onSubmit: _make,
      onCancel: () => Navigator.of(context).pop(),
    );
  }
}
