import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Admin Profile -> "Also join as Employee" (HR/Ops phone, admin first).
///
/// The employee recovery code or entry code, like any employee. No admin
/// password here (asked once, the first time they switch back to admin).
class AlsoEmployeeScreen extends StatefulWidget {
  const AlsoEmployeeScreen({super.key});

  @override
  State<AlsoEmployeeScreen> createState() => _AlsoEmployeeScreenState();
}

class _AlsoEmployeeScreenState extends State<AlsoEmployeeScreen> {
  static const _ink = Color(0xFF111827);
  static const _soft = Color(0xCC0E1A3A);
  static const _line = Color(0xFFCBD3E1);

  final _code = TextEditingController();
  bool _hasRecovery = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  TextStyle _s(double size, {FontWeight w = FontWeight.w400, Color c = _ink}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: w,
        color: c,
        letterSpacing: 0,
        height: 1.4,
      );

  InputDecoration _deco(String hint, {Widget? suffix}) => InputDecoration(
    hintText: hint,
    hintStyle: _s(15, c: const Color(0xFF6B7489)),
    contentPadding: const EdgeInsets.all(14),
    suffixIcon: suffix,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _line, width: 1.5),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _line, width: 1.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
    ),
  );

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: 6),
    child: Text(t, style: _s(14, w: FontWeight.w600)),
  );

  Future<void> _join() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(
        () => _error = _hasRecovery
            ? 'Please enter your recovery code.'
            : 'Please enter your entry code.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context, rootNavigator: true);
    try {
      await AuthService.instance.joinAsEmployee(
        recoveryCode: _hasRecovery ? code : null,
        entryCode: _hasRecovery ? null : code,
      );
      // The employee side is open underneath: close this screen.
      nav.popUntil((r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AuthService.messageFor(e);
      });
    }
  }

  Widget _choice(String text, bool recovery) {
    final on = _hasRecovery == recovery;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _busy
            ? null
            : () => setState(() {
                _hasRecovery = recovery;
                _code.clear();
                _error = null;
              }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: on
                ? const [
                    BoxShadow(
                      color: Color(0x2E0E1A3A),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                text,
                maxLines: 1,
                style: _s(
                  14,
                  w: on ? FontWeight.w600 : FontWeight.w500,
                  c: on ? AppColors.blue : _soft,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        leadingWidth: 68,
        leading: const AppBackButton(),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text(
              'Also join as Employee',
              style: _s(22, w: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Use this phone as an employee too. Enter your recovery code '
              'or entry code, like any employee.',
              style: _s(15, c: _soft),
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F4F9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  _choice('I have a recovery code', true),
                  _choice('I have an entry code', false),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _label(_hasRecovery ? 'Recovery code' : 'Entry code'),
            TextField(
              controller: _code,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              style: _s(15),
              decoration: _deco(
                _hasRecovery ? 'Like K7M2P-X9F4R' : 'Code from Pulse Codes in Zoho',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: _s(14, c: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _busy ? null : _join,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.blue,
                minimumSize: const Size.fromHeight(52),
                shape: const StadiumBorder(),
                textStyle: _s(16, w: FontWeight.w600, c: Colors.white),
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
                  : const Text('Join as Employee'),
            ),
          ],
        ),
      ),
    );
  }
}


TextStyle _ds(double size, {FontWeight w = FontWeight.w400, Color? c}) =>
    GoogleFonts.inter(
      fontSize: size,
      fontWeight: w,
      color: c ?? const Color(0xFF111827),
      letterSpacing: 0,
      height: 1.45,
    );

const Color _dsoft = Color(0xCC0E1A3A);

/// First "Switch to Admin": the admin password, once. Null if cancelled.
Future<String?> askAdminPassword(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _PasswordDialog(),
  );
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _c = TextEditingController();
  bool _hide = true;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _ok() {
    final p = _c.text;
    if (p.isEmpty) return;
    Navigator.of(context).pop(p);
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFCBD3E1), width: 1.5),
    );
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text('Admin password', style: _ds(20, w: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Enter it once. It’s kept only on this phone, so next time you '
            'can switch without typing.',
            style: _ds(15, c: _dsoft),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _c,
            autofocus: true,
            obscureText: _hide,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => _ok(),
            style: _ds(15),
            decoration: InputDecoration(
              hintText: 'Your admin password',
              hintStyle: _ds(15, c: const Color(0xFF6B7489)),
              contentPadding: const EdgeInsets.all(14),
              border: border,
              enabledBorder: border,
              focusedBorder: border.copyWith(
                borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
              ),
              suffixIcon: IconButton(
                tooltip: _hide ? 'Show' : 'Hide',
                onPressed: () => setState(() => _hide = !_hide),
                icon: Icon(
                  _hide
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: _dsoft,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: _ds(15, w: FontWeight.w500, c: _dsoft)),
        ),
        FilledButton(
          onPressed: _ok,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.blue,
            shape: const StadiumBorder(),
          ),
          child: Text(
            'Switch to Admin',
            style: _ds(15, w: FontWeight.w600, c: Colors.white),
          ),
        ),
      ],
    );
  }
}
