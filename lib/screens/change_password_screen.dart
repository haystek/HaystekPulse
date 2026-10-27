import 'package:flutter/material.dart';

import '../models/employee.dart';
import '../services/auth_service.dart';

/// Shown on first login, while `mustChangePassword` is true.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, required this.employee});

  final Employee employee;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newPassword = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  /// Each box has its own eye button to show or hide the password.
  bool _hideNew = true;
  bool _hideConfirm = true;

  @override
  void dispose() {
    _newPassword.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.changePassword(_newPassword.text);
      // AuthGate moves to the home screen once the flag is cleared.
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AuthService.messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set a new password'),
        actions: [
          TextButton(
            onPressed: AuthService.instance.signOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Welcome, ${widget.employee.name}.',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Please replace the password you were given with one of '
                          'your own before you continue.',
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _newPassword,
                      obscureText: _hideNew,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'New password',
                        helperText: 'At least 8 characters',
                        suffixIcon: _EyeButton(
                          hidden: _hideNew,
                          onTap: () => setState(() => _hideNew = !_hideNew),
                        ),
                      ),
                      validator: (v) => (v == null || v.length < 8)
                          ? 'Use at least 8 characters'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirm,
                      obscureText: _hideConfirm,
                      onFieldSubmitted: (_) => _save(),
                      decoration: InputDecoration(
                        labelText: 'Confirm new password',
                        suffixIcon: _EyeButton(
                          hidden: _hideConfirm,
                          onTap: () =>
                              setState(() => _hideConfirm = !_hideConfirm),
                        ),
                      ),
                      validator: (v) => v != _newPassword.text
                          ? 'The two passwords do not match'
                          : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: _busy
                            ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : const Text('Save password'),
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

/// The eye button at the end of a password box.
/// Eye = show the password, crossed eye = hide it again.
class _EyeButton extends StatelessWidget {
  const _EyeButton({required this.hidden, required this.onTap});

  final bool hidden;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: hidden ? 'Show password' : 'Hide password',
      onPressed: onTap,
      icon: Icon(
        hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 20,
        color: const Color(0xFF8E97AB),
      ),
    );
  }
}