import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/employee.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/personal_code.dart';
import '../services/vault_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pulse_loading.dart';
import 'employee_home_screen.dart';

TextStyle _t(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.ink,
  double? height,
  double? letterSpacing,
}) => GoogleFonts.figtree(
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
  letterSpacing: letterSpacing,
);

const Color _soft = Color(0xFF8E97AB);
const Color _line = Color(0xFFE3E8F1);

enum _Step {
  checking,
  askPassword,
  askCode,
  working,
  showCode,
  showPersonal,
  needBackup,
  error,
  ready,
}

/// Employees only: opens the locked history before the home screen.
///
/// Personal-code accounts (no email): the history opens with the personal
/// code (just typed, or kept on this phone). Right after joining, the new
/// personal code is shown once.
///
/// Older email accounts:
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

  /// The personal code being used (personal-code accounts), for "Try again".
  String? _personal;

  String get _uid => widget.employee.uid;

  @override
  void initState() {
    super.initState();
    // After initState, so setState in _start is always allowed.
    Future.microtask(_start);
  }

  Future<void> _start() async {
    if (_vault.isReady || await _vault.openSaved(_uid)) {
      _afterOpen();
      return;
    }
    final auth = AuthService.instance;
    if (auth.isCodeAccount) {
      final code = auth.pendingCode ?? await auth.savedCode();
      if (code != null) {
        await _openWithCode(code);
      } else if (mounted) {
        setState(() => _step = _Step.askCode);
      }
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

  /// Personal-code accounts: open the history with the code.
  Future<void> _openWithCode(String code) async {
    setState(() {
      _step = _Step.working;
      _error = null;
      _personal = code;
    });
    try {
      await _vault.openWithCode(_uid, code);
      if (!mounted) return;
      _afterOpen();
    } on FirebaseException catch (e) {
      debugPrint('[VaultGate] $e');
      if (mounted) setState(() => _step = _Step.error);
    } catch (e) {
      // The code doesn't open this history.
      debugPrint('[VaultGate] $e');
      if (!mounted) return;
      setState(() {
        _step = _Step.askCode;
        _error = 'This recovery code is not correct.';
      });
    }
  }

  /// Typed personal code: it must belong to this account.
  Future<void> _submitCode(String code) async {
    final email = FirebaseAuth.instance.currentUser?.email?.toLowerCase();
    if (email != await AuthService.codeEmail(code)) {
      if (mounted) {
        setState(() => _error = 'This recovery code is not correct.');
      }
      return;
    }
    await _openWithCode(code);
  }

  /// Opened. Right after joining, show the new personal code once.
  void _afterOpen() {
    final fresh = AuthService.instance.newPersonalCode;
    if (fresh != null && mounted) {
      setState(() {
        _code = fresh;
        _step = _Step.showPersonal;
      });
      return;
    }
    _ready();
  }

  void _ready() {
    AuthService.instance.newPersonalCode = null;
    AuthService.instance.pendingCode = null;
    _personal = null;
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
      final wrong =
          e is FirebaseAuthException &&
          (e.code == 'wrong-password' || e.code == 'invalid-credential');
      setState(() {
        _step = _Step.askPassword;
        _error = wrong
            ? 'This password is not correct.'
            : AuthService.messageFor(e);
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
      case _Step.showPersonal:
        return BackupCodeScreen(
          code: _code ?? '',
          personal: true,
          onDone: _ready,
        );
      case _Step.askCode:
        return _AskScreen(
          key: const ValueKey('ask-code'),
          icon: Icons.key_outlined,
          title: 'Enter your recovery code',
          text:
              'Your history is locked with your recovery code. Enter it '
              'to open it on this phone.',
          label: 'Recovery code',
          hint: 'XXXXX-XXXXX',
          obscure: false,
          button: 'Unlock',
          error: _error,
          onSubmit: _submitCode,
        );
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
          text:
              'Your posts are locked with your password. Enter it to '
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
          text:
              'Your password was reset, so your history needs your '
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
            if (AuthService.instance.isCodeAccount) {
              final c = _personal;
              if (c != null) {
                _openWithCode(c);
              } else {
                setState(() => _step = _Step.askCode);
              }
              return;
            }
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
  Widget build(BuildContext context) => const PulseLoadingScreen();
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
                      style: _t(
                        13.5,
                        color: Theme.of(context).colorScheme.error,
                      ),
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
                      child: Text(
                        widget.secondary!,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: widget.onCancel ?? AuthService.instance.signOut,
                    style: TextButton.styleFrom(foregroundColor: _soft),
                    child: Text(
                      widget.onCancel != null ? 'Cancel' : 'Sign out',
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

/// Shows the backup code once, with Copy, and asks the last 4 letters
/// to make sure it was saved.
class BackupCodeScreen extends StatefulWidget {
  const BackupCodeScreen({
    super.key,
    required this.code,
    required this.onDone,
    this.firstTime = false,
    this.personal = false,
  });

  final String code;
  final VoidCallback onDone;

  /// True right after joining with an entry code: the personal code.
  final bool personal;

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

  /// Personal code: the Copy button says "Copied" for 2 seconds.
  bool _copied = false;

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.code));
    if (widget.personal) {
      HapticFeedback.lightImpact();
      setState(() => _copied = true);
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.personal ? 'Recovery code copied' : 'Backup code copied',
        ),
      ),
    );
  }

  void _done() {
    // Personal code: type the whole code once (helps to remember it).
    if (widget.personal) {
      if (PersonalCode.normalize(_last4.text) !=
          PersonalCode.normalize(widget.code)) {
        setState(() => _error = 'That doesn’t match. Please check the code.');
        return;
      }
      widget.onDone();
      return;
    }
    final want = VaultService.normalizeCode(widget.code);
    final typed = VaultService.normalizeCode(_last4.text);
    if (typed != want.substring(want.length - 4)) {
      setState(() => _error = 'That doesn’t match. Please check the code.');
      return;
    }
    widget.onDone();
  }

  /// Paste the code from the clipboard into the confirm field.
  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim().toUpperCase();
    if (text == null || text.isEmpty) return;
    _last4.text = text;
    _last4.selection = TextSelection.collapsed(offset: text.length);
    setState(() => _error = null);
  }

  bool get _matches =>
      PersonalCode.normalize(_last4.text) ==
      PersonalCode.normalize(widget.code);

  @override
  Widget build(BuildContext context) {
    if (widget.personal) return _personalView(context);
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
                      widget.personal
                          ? 'Your recovery code'
                          : 'Your backup code',
                      textAlign: TextAlign.center,
                      style: _t(22, weight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.personal
                          ? 'You need this code only if you change to a new '
                                'phone. On this phone the app opens by itself, '
                                'even after reinstalling. Only you have it: we '
                                'can’t see it or send it again.'
                          : widget.firstTime
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
                          fontSize: widget.personal ? 18 : 20,
                          letterSpacing: widget.personal ? 0.5 : 1.5,
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
                        widget.personal
                            ? 'Save it now: take a screenshot, write it down, '
                                  'or save it in your notes. Without it, your '
                                  'account can’t move to a new phone. Not by '
                                  'admin, not by the developer.'
                            : 'Save it somewhere safe: a screenshot, your notes, or '
                                  'paper. We can’t recover your history without it — '
                                  'not admin, not the developer.',
                        style: _t(
                          13,
                          color: const Color(0xFF8A5A00),
                          height: 1.45,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _last4,
                      maxLength: widget.personal ? 60 : 4,
                      textCapitalization: widget.personal
                          ? TextCapitalization.none
                          : TextCapitalization.characters,
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: widget.personal
                          ? TextInputType.visiblePassword
                          : TextInputType.text,
                      onSubmitted: (_) => _done(),
                      style: _t(16, letterSpacing: widget.personal ? 0.5 : 2),
                      decoration: InputDecoration(
                        labelText: widget.personal
                            ? 'Type your code once to confirm'
                            : 'Type the last 4 letters to confirm',
                        counterText: '',
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _error!,
                        style: _t(
                          13.5,
                          color: Theme.of(context).colorScheme.error,
                        ),
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

  /// Personal code, right after joining (design D): "Your code" pill,
  /// the code first (one line) with Copy, a small animation of the key
  /// moving the account from the old phone to a new one, 3 clear steps,
  /// then paste or type it once to confirm, and Continue.
  Widget _personalView(BuildContext context) {
    final code = PersonalCode.normalize(widget.code);
    final groups = code.contains('-') && code.length == 11
        ? code.split('-')
        : [code.toUpperCase()];
    final ok = _matches;
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;

    Widget block(String t) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.blueTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        t,
        maxLines: 1,
        softWrap: false,
        style: GoogleFonts.robotoMono(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: 2.5,
          color: AppColors.blue,
        ),
      ),
    );

    // The code on one line (it gets a little smaller on narrow phones,
    // never split), and Copy.
    final codeCard = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _copy,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _line, width: 1.5),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [block(groups.join('-'))],
              ),
            ),
            const SizedBox(height: 12),
            Material(
              color: Colors.white,
              shape: const StadiumBorder(
                side: BorderSide(color: _line, width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _copy,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _copied ? Icons.check_rounded : Icons.copy_rounded,
                        size: 16,
                        color: AppColors.blue,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _copied ? 'Copied' : 'Copy code',
                        style: _t(
                          14,
                          weight: FontWeight.w500,
                          color: AppColors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    Widget step(int n, String title, String sub) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.blueTint,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$n',
            style: _t(13, weight: FontWeight.w600, color: AppColors.blue),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: _t(14.5, weight: FontWeight.w500)),
              const SizedBox(height: 1),
              Text(sub, style: _t(13, color: AppColors.muted, height: 1.4)),
            ],
          ),
        ),
      ],
    );

    return PopScope(
      canPop: false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
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
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // "Your code" pill on the top right (no back: shown once).
                        Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            height: 42,
                            padding: const EdgeInsets.fromLTRB(5, 5, 16, 5),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(21),
                              border: Border.all(
                                color: AppColors.blue.withValues(alpha: 0.35),
                              ),
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
                                  child: const Icon(
                                    Icons.key_outlined,
                                    size: 17,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 9),
                                Text('Your code', style: _t(16)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Save your recovery code',
                          textAlign: TextAlign.center,
                          style: _t(23, weight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Use to restore access after switching phones or reinstalling.',
                          textAlign: TextAlign.center,
                          style: _t(14, color: AppColors.muted),
                        ),
                        const SizedBox(height: 16),
                        codeCard,
                        // The animation and the steps hide while typing,
                        // so the field and the button stay in view.
                        AnimatedSize(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: typing
                              ? const SizedBox(width: double.infinity)
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const SizedBox(height: 12),
                                    const _MovePhones(),
                                    const SizedBox(height: 16),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      child: Column(
                                        children: [
                                          step(
                                            1,
                                            'Save it now',
                                            'Copy it, or take a screenshot.',
                                          ),
                                          const SizedBox(height: 12),
                                          step(
                                            2,
                                            'Changing your phone?',
                                            'Install the app on the new phone, tap “I have my recovery code” '
                                                'and enter this code. Your account will be restored on your new phone.',
                                          ),
                                          const SizedBox(height: 12),
                                          step(
                                            3,
                                            'Need to find your code?',
                                            'Find it anytime in Profile → My recovery code.',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 16),
                        // Paste or type the code once to confirm.
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          height: 56,
                          padding: const EdgeInsets.only(left: 16, right: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              width: 2,
                              color: ok
                                  ? const Color(0xFF16A34A)
                                  : _error != null
                                  ? const Color(0xFFC0392B)
                                  : _line,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _last4,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  keyboardType: TextInputType.visiblePassword,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  textInputAction: TextInputAction.done,
                                  inputFormatters: [
                                    TextInputFormatter.withFunction(
                                      (old, now) => now.copyWith(
                                        text: now.text.toUpperCase(),
                                      ),
                                    ),
                                  ],
                                  onChanged: (_) =>
                                      setState(() => _error = null),
                                  onSubmitted: (_) => _done(),
                                  style: _t(
                                    17,
                                    weight: FontWeight.w600,
                                    letterSpacing: 1.2,
                                  ),
                                  cursorColor: AppColors.blue,
                                  decoration: InputDecoration(
                                    hintText: 'Enter your code to confirm',
                                    hintStyle: _t(
                                      15,
                                      color: const Color(0xFFC3C9D6),
                                    ),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    filled: false,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                              if (ok)
                                const Padding(
                                  padding: EdgeInsets.only(right: 10),
                                  child: Icon(
                                    Icons.check_circle_rounded,
                                    color: Color(0xFF16A34A),
                                    size: 24,
                                  ),
                                )
                              else
                                TextButton.icon(
                                  onPressed: _paste,
                                  icon: const Icon(
                                    Icons.content_paste_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Paste'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.blue,
                                    textStyle: _t(14, weight: FontWeight.w500),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: _t(13.5, color: const Color(0xFFC0392B)),
                          ),
                        ],
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 56,
                          child: FilledButton(
                            onPressed: _done,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.blue,
                              shape: const StadiumBorder(),
                              textStyle: _t(16, weight: FontWeight.w600),
                            ),
                            child: const Text('Continue'),
                          ),
                        ),
                      ],
                    ),
                  ),
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
      final wrong =
          e is FirebaseAuthException &&
          (e.code == 'wrong-password' || e.code == 'invalid-credential');
      setState(
        () => _error = wrong
            ? 'This password is not correct.'
            : 'Could not make a new code. Please check your internet.',
      );
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
      text:
          'Enter your password. You’ll get a new code, and the old one '
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

/// Personal-code accounts: saves the account record right after joining
/// (by itself). If the app was closed in between, or something failed, it
/// asks for the entry code again.
class CodeFinishScreen extends StatefulWidget {
  const CodeFinishScreen({super.key});

  @override
  State<CodeFinishScreen> createState() => _CodeFinishScreenState();
}

class _CodeFinishScreenState extends State<CodeFinishScreen> {
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (AuthService.instance.pendingEntryCode != null) {
      _busy = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish(null));
    }
  }

  Future<void> _finish(String? entryCode) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.finishCodeAccount(entryCode);
      // AuthGate moves on by itself once the record exists.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AuthService.messageFor(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const PulseLoadingScreen(text: 'Setting up your account…');
    }
    return _AskScreen(
      key: const ValueKey('finish-entry'),
      icon: Icons.mark_email_read_outlined,
      title: 'Enter your entry code',
      text:
          'To finish setting up your account, enter a code from '
          'Pulse Codes in Zoho.',
      label: 'Entry code',
      obscure: false,
      button: 'Continue',
      error: _error,
      onSubmit: _finish,
    );
  }
}

/// The little animation on the personal code screen: small data blocks
/// fly from the old phone to the new phone, the new phone's bar fills up
/// and a green tick pops. Again and again.
class _MovePhones extends StatefulWidget {
  const _MovePhones();

  @override
  State<_MovePhones> createState() => _MovePhonesState();
}

class _MovePhonesState extends State<_MovePhones>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 0..1 inside [from]..[to] of the loop, eased.
  double _part(double t, double from, double to) =>
      Curves.easeInOut.transform(((t - from) / (to - from)).clamp(0.0, 1.0));

  Widget _phone(
    String label, {
    required double fill,
    required double done,
    required bool target,
  }) {
    final lit = target ? fill : 0.0;
    final avatarBg = Color.lerp(AppColors.blueTint, AppColors.blue, lit)!;
    final avatarIcon = Color.lerp(AppColors.blue, Colors.white, lit)!;
    return Container(
      width: 62,
      height: 96,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Color.lerp(_line, const Color(0xFF9DB4F5), done)!,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.blue.withValues(alpha: 0.10 * done),
            spreadRadius: 6 * done,
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 20,
            height: 4,
            decoration: BoxDecoration(
              color: _line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Spacer(),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: avatarBg,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.person_outline_rounded,
                  size: 17,
                  color: avatarIcon,
                ),
              ),
              if (target)
                Positioned(
                  right: -7,
                  bottom: -7,
                  child: Transform.scale(
                    scale: Curves.easeOutBack.transform(done),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A34A),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 11,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(label, style: _t(10, color: _soft)),
          const SizedBox(height: 8),
          // Data bar: empties on the old phone, fills on the new one.
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(2),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: target ? fill : 1 - fill * 0.6,
              child: Container(
                decoration: BoxDecoration(
                  color: done > 0.5 && target
                      ? const Color(0xFF16A34A)
                      : AppColors.blue,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          const SizedBox(height: 9),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 116,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.blueTint, Color(0xFFF7F9FE)],
        ),
      ),
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            final reset = t > 0.92 ? 1 - (t - 0.92) / 0.08 : 1.0;
            final fill = _part(t, 0.02, 0.72) * reset;
            final done = _part(t, 0.72, 0.82) * reset;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _phone('Old phone', fill: fill, done: 0, target: false),
                SizedBox(
                  width: 104,
                  height: 96,
                  child: CustomPaint(
                    painter: _DataFlow(t: t, active: t < 0.74),
                  ),
                ),
                _phone('New phone', fill: fill, done: done, target: true),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Dotted track with small blue data blocks flying along a low arc.
class _DataFlow extends CustomPainter {
  _DataFlow({required this.t, required this.active});

  final double t;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2 - 4;
    if (!active) return; // compact v2
    for (var i = 0; i < 5; i++) {
      final p = (t * 2.4 + i / 5) % 1.0;
      final hump = 4 * p * (1 - p); // 0 at the ends, 1 in the middle
      final x = 6 + (size.width - 12) * p;
      final y = midY - hump * 12;
      final s = 5 + hump * 4;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, y), width: s, height: s),
          Radius.circular(s * 0.3),
        ),
        Paint()..color = AppColors.blue.withValues(alpha: 0.25 + 0.75 * hump),
      );
    }
  }

  @override
  bool shouldRepaint(_DataFlow old) => old.t != t || old.active != active;
}
