import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

const Color _ink = Color(0xFF0E1A3A);
const Color _soft = Color(0xCC0E1A3A);
const Color _line = Color(0xFFE3E7EF);

TextStyle _s(double size, {FontWeight w = FontWeight.w400, Color c = _ink, double h = 1.4}) =>
    GoogleFonts.inter(
      fontSize: size,
      fontWeight: w,
      color: c,
      letterSpacing: 0,
      height: h,
    );

/// Admin Profile -> "Also join as Employee" (HR/Ops phone, admin first).
/// Same style as the employee welcome screen: a picture, a big title and
/// the same two buttons. A button opens a sheet with the code box.
/// No admin password here (asked once, the first time they switch back).
class AlsoEmployeeScreen extends StatelessWidget {
  const AlsoEmployeeScreen({super.key});

  Future<void> _openSheet(BuildContext context, {required bool recovery}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _CodeSheet(recovery: recovery),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final heroHeight = (size.height * 0.36).clamp(230.0, 330.0);
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final initial = email.isEmpty ? 'A' : email[0].toUpperCase();
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
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            _Hero(height: heroHeight, initial: initial, email: email),
            const SizedBox(height: 24),
            Text(
              'Also join\nas Employee',
              textAlign: TextAlign.center,
              style: _s(27, w: FontWeight.w800, h: 1.2),
            ),
            const SizedBox(height: 8),
            Text(
              'Use this phone as an employee too.\nSwitch anytime from Profile.',
              textAlign: TextAlign.center,
              style: _s(15, c: _soft, h: 1.45),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => _openSheet(context, recovery: false),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.blue,
                minimumSize: const Size.fromHeight(54),
                shape: const StadiumBorder(),
                textStyle: _s(16.5, w: FontWeight.w700, c: Colors.white),
              ),
              child: const Text('Join with entry code'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _openSheet(context, recovery: true),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.blue,
                minimumSize: const Size.fromHeight(54),
                side: const BorderSide(color: _line, width: 1.5),
                shape: const StadiumBorder(),
                textStyle: _s(16.5, w: FontWeight.w700, c: AppColors.blue),
              ),
              child: const Text('I have my recovery code'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The picture: Admin card, a switch icon, Employee card.
class _Hero extends StatelessWidget {
  const _Hero({required this.height, required this.initial, required this.email});

  final double height;
  final String initial;
  final String email;

  Widget _chip({required Widget avatar, required String title, required String sub}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 16, 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F1E3CA0),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar,
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: _s(15, w: FontWeight.w600)),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _s(12.5, c: _soft),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE4EBFD), Color(0xFFF3F6FE)],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          return Stack(
            children: [
              Positioned(
                left: -60,
                top: -60,
                child: Container(
                  width: w * 0.62,
                  height: w * 0.62,
                  decoration: const BoxDecoration(
                    color: Color(0xFFD9E3FB),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                right: -50,
                bottom: -60,
                child: Container(
                  width: w * 0.55,
                  height: w * 0.55,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE0E7FC),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              // Admin card.
              Positioned(
                left: 20,
                top: height * 0.1,
                right: w * 0.25,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Transform.rotate(
                    angle: -0.05,
                    child: _chip(
                      avatar: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.blue,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Text(
                          initial,
                          style: _s(15, w: FontWeight.w700, c: Colors.white),
                        ),
                      ),
                      title: 'Admin',
                      sub: email.isEmpty ? 'Work email' : email,
                    ),
                  ),
                ),
              ),
              // Switch icon.
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.blue,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x591D4ED8),
                        blurRadius: 24,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.swap_horiz_rounded,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
              ),
              // Employee card.
              Positioned(
                right: 18,
                bottom: height * 0.12,
                left: w * 0.25,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Transform.rotate(
                    angle: 0.035,
                    child: _chip(
                      avatar: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF0FF),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(
                          Icons.lock_outline_rounded,
                          size: 18,
                          color: AppColors.blue,
                        ),
                      ),
                      title: 'Employee',
                      sub: 'Anonymous · same phone',
                    ),
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

/// Recovery code: capitals, dash after 5, max 10 letters (K7M2P-X9F4R).
class _RecoveryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var raw = newValue.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (raw.length > 10) raw = raw.substring(0, 10);
    final text = raw.length > 5 ? '${raw.substring(0, 5)}-${raw.substring(5)}' : raw;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// The sheet: one code box and "Join as Employee".
class _CodeSheet extends StatefulWidget {
  const _CodeSheet({required this.recovery});

  final bool recovery;

  @override
  State<_CodeSheet> createState() => _CodeSheetState();
}

class _CodeSheetState extends State<_CodeSheet> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(
        () => _error = widget.recovery
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
        recoveryCode: widget.recovery ? code : null,
        entryCode: widget.recovery ? null : code,
      );
      // The employee side is open underneath: close the sheet and screen.
      nav.popUntil((r) => r.isFirst);
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
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFCBD3E1), width: 1.5),
    );
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.recovery ? 'Your recovery code' : 'Your entry code',
                style: _s(19, w: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                widget.recovery
                    ? 'The code you saved when you joined.'
                    : 'Type the 6-letter entry code from Zoho to join.',
                style: _s(14, c: _soft),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _code,
                autofocus: true,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: widget.recovery
                    ? [_RecoveryFormatter()]
                    : [
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                        LengthLimitingTextInputFormatter(12),
                      ],
                onSubmitted: (_) => _join(),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                style: _s(16, w: FontWeight.w500).copyWith(letterSpacing: 2),
                decoration: InputDecoration(
                  hintText: widget.recovery ? 'K7M2P-X9F4R' : 'ABCDEF',
                  hintStyle: _s(16, c: const Color(0xFF9AA3B8)).copyWith(letterSpacing: 2),
                  contentPadding: const EdgeInsets.all(15),
                  border: border,
                  enabledBorder: border,
                  focusedBorder: border.copyWith(
                    borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: _s(13.5, c: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _join,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  minimumSize: const Size.fromHeight(54),
                  shape: const StadiumBorder(),
                  textStyle: _s(16.5, w: FontWeight.w700, c: Colors.white),
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
