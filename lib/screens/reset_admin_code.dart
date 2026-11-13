import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/admin_code_service.dart';

const _blue = Color(0xFF1D4ED8);
const _ink = Color(0xFF0E1A3A);
const _muted = Color(0xFF55607A);

/// Profile -> Reset admin code: ask first, then show the new code.
Future<void> showResetAdminCode(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Reset admin code?'),
      content: const Text(
        'A new admin code will be made and the old one will stop working.\n\n'
        'Admins who already signed up are not affected. '
        'Share the new code only with HR.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Reset'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  String? code;
  try {
    code = await AdminCodeService.reset();
  } catch (e) {
    debugPrint('Reset admin code failed: $e');
  }
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();

  if (code == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not reset the code. Check your internet and try again.',
        ),
      ),
    );
    return;
  }
  final newCode = code;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      title: const Text('New admin code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The old code no longer works. Share this code only with HR. '
            'You can see it again in Profile.',
          ),
          const SizedBox(height: 20),
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SelectableText(
                newCode,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4,
                  color: _ink,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: newCode));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Admin code copied')),
            );
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Copy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

/// Profile (admins): the current admin code, hidden by default.
/// Eye = show / hide, copy = copy to share with HR.
class AdminCodeRow extends StatefulWidget {
  const AdminCodeRow({super.key});

  @override
  State<AdminCodeRow> createState() => _AdminCodeRowState();
}

class _AdminCodeRowState extends State<AdminCodeRow> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String?>(
      stream: AdminCodeService.current(),
      builder: (context, snap) {
        final String code = snap.data ?? '';
        final bool has = code.isNotEmpty;
        final String shown = !has ? 'Not set yet' : (_show ? code : '••••••');
        final TextStyle style = has
            ? const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: _ink,
              )
            : const TextStyle(fontSize: 13, color: _muted);

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF0FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.key_outlined, color: _blue, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Admin code',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(shown, style: style),
                    ),
                  ],
                ),
              ),
              if (has)
                IconButton(
                  tooltip: _show ? 'Hide' : 'Show',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _show = !_show),
                  icon: Icon(
                    _show
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: _blue,
                  ),
                ),
              if (has)
                IconButton(
                  tooltip: 'Copy',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Admin code copied')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, color: _blue),
                ),
            ],
          ),
        );
      },
    );
  }
}
