import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pulse_loading.dart';
import '../widgets/ui.dart';

TextStyle _t(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.ink,
  double? height,
}) =>
    GoogleFonts.plusJakartaSans(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );

const Color _soft = Color(0xFF8E97AB);
const Color _line = Color(0xFFE3E8F1);
const Color _red = Color(0xFFC0392B);

/// Profile -> Delete my account. Says clearly what is lost and what stays,
/// then asks to type DELETE. Cancel is the big blue button.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _confirm = TextEditingController();
  final _secret = TextEditingController();
  final _scroll = ScrollController();
  final _confirmFocus = FocusNode();
  bool _busy = false;
  String? _error;

  /// Personal-code account with no code kept on this phone: ask for it.
  bool _askCode = false;

  final bool _codeAccount = AuthService.instance.isCodeAccount;

  @override
  void initState() {
    super.initState();
    // Typing DELETE: scroll up so the buttons show above the keyboard.
    _confirmFocus.addListener(() {
      if (_confirmFocus.hasFocus) _toBottom(wait: true);
    });
    if (_codeAccount) {
      AuthService.instance.savedCode().then((c) {
        if (mounted && c == null) setState(() => _askCode = true);
      });
    }
  }

  @override
  void dispose() {
    _confirm.dispose();
    _secret.dispose();
    _scroll.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  /// Scroll to the end (the Cancel and Delete buttons).
  /// wait: give the keyboard time to open first.
  Future<void> _toBottom({bool wait = false}) async {
    if (wait) await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted || !_scroll.hasClients) return;
    await _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  /// Last check before deleting: one more "Are you sure?".
  Future<void> _askAgain() async {
    _hideKeyboard();
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            color: Color(0xFFFDEFEC),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.delete_outline_rounded, color: _red, size: 28),
        ),
        title: Text(
          'Delete your account?',
          textAlign: TextAlign.center,
          style: _t(20, weight: FontWeight.w600),
        ),
        content: Text(
          _codeAccount
              ? 'Your account and personal code will be deleted for good. '
                  'You can’t get them back.'
              : 'Your account will be deleted for good. You can’t get it back.',
          textAlign: TextAlign.center,
          style: _t(14.5, color: AppColors.muted, height: 1.45),
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
                  textStyle: _t(15.5, weight: FontWeight.w500),
                ),
                child: const Text('No, keep my account'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                style: TextButton.styleFrom(
                  foregroundColor: _red,
                  minimumSize: const Size.fromHeight(46),
                  textStyle: _t(15, weight: FontWeight.w500),
                ),
                child: const Text('Yes, delete'),
              ),
            ],
          ),
        ],
      ),
    );
    // Closing the popup gives focus back to the field: close the keyboard.
    _hideKeyboard();
    if (yes == true && mounted) _delete();
  }

  void _hideKeyboard() {
    _confirmFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  bool get _typedDelete => _confirm.text.trim().toUpperCase() == 'DELETE';

  Future<void> _delete() async {
    _hideKeyboard();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.deleteMyAccount(
        secret: (_codeAccount && !_askCode) ? null : _secret.text,
      );
      if (!mounted) return;
      // Back to the start: the welcome screen shows by itself.
      Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      final needCode =
          e is FirebaseAuthException && e.code == 'personal-code-needed';
      setState(() {
        _busy = false;
        if (needCode) _askCode = true;
        _error = AuthService.messageFor(e);
      });
    }
  }

  Widget _point(IconData icon, String text, {Color color = AppColors.ink}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: _t(14, height: 1.4))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Deleting: one calm full-screen pulse, nothing to tap.
    if (_busy) {
      return const PopScope(
        canPop: false,
        child: PulseLoadingScreen(text: 'Deleting your account…'),
      );
    }
    final needSecret = !_codeAccount || _askCode;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        leadingWidth: 68,
        leading: const AppBackButton(),
        title: const SizedBox.shrink(),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
              children: [
                Text('Delete your account?', style: _t(24, weight: FontWeight.w500)),
                const SizedBox(height: 6),
                Text(
                  'Do this only when you leave Haystek. For a new phone or '
                  'a reinstall, you don’t need to delete anything. This '
                  'can’t be undone.',
                  style: _t(14.5, color: AppColors.muted, height: 1.45),
                ),
                const SizedBox(height: 18),

                // What is lost.
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDEFEC),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('You will lose', style: _t(14, weight: FontWeight.w600, color: _red)),
                      if (_codeAccount)
                        _point(Icons.key_off_outlined,
                            'Your personal code. It will stop working.',
                            color: _red),
                      _point(Icons.inbox_outlined,
                          'Your list of old messages (My Feedback).',
                          color: _red),
                      _point(Icons.chat_bubble_outline_rounded,
                          'Your chats with admin. You won’t get replies anymore.',
                          color: _red),
                      _point(Icons.favorite_border_rounded,
                          'Your Weekly Pulse history.',
                          color: _red),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // What stays.
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F8FB),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('What stays', style: _t(14, weight: FontWeight.w600)),
                      _point(Icons.lock_outline_rounded,
                          'Messages you sent stay with admin, without your name. '
                          'Nobody can link them to you.',
                          color: AppColors.blue),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                if (needSecret) ...[
                  TextField(
                    controller: _secret,
                    obscureText: !_codeAccount,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: _codeAccount
                        ? TextInputType.visiblePassword
                        : TextInputType.text,
                    onChanged: (_) => setState(() => _error = null),
                    style: _t(15.5),
                    decoration: InputDecoration(
                      labelText: _codeAccount ? 'Your personal code' : 'Your password',
                      hintText: _codeAccount ? 'XXXXX-XXXXX' : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _confirm,
                  focusNode: _confirmFocus,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) {
                    setState(() => _error = null);
                    // DELETE typed: show the Delete button.
                    if (_typedDelete) _toBottom();
                  },
                  style: _t(15.5, height: 1.2).copyWith(letterSpacing: 1.5),
                  decoration: const InputDecoration(
                    labelText: 'Type DELETE to confirm',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: _t(13.5, color: _red)),
                ],
                const SizedBox(height: 24),

                // Cancel: the big, easy choice.
                FilledButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    minimumSize: const Size.fromHeight(54),
                    shape: const StadiumBorder(),
                    textStyle: _t(16, weight: FontWeight.w500),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _busy || !_typedDelete ? null : _askAgain,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _red,
                    disabledForegroundColor: _soft,
                    minimumSize: const Size.fromHeight(50),
                    side: const BorderSide(color: _line, width: 1.5),
                    shape: const StadiumBorder(),
                    textStyle: _t(15, weight: FontWeight.w500),
                  ),
                  child: const Text('Delete my account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
