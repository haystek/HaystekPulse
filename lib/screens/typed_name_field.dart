import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// "Your name" box, shown under "Show my name" for employees who have no
/// name in the app. The name goes only with this message.
class TypedNameField extends StatelessWidget {
  const TypedNameField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.error,
    this.onChanged,
    this.compact = false,
  });

  final TextEditingController controller;
  final bool enabled;
  final String? error;
  final ValueChanged<String>? onChanged;

  /// Smaller, without the help line (for the broadcast comment box).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const line = Color(0xFFE3E8F1);
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLength: 60,
      textCapitalization: TextCapitalization.words,
      autocorrect: false,
      onChanged: onChanged,
      style: GoogleFonts.inter(fontSize: compact ? 14 : 15, color: AppColors.ink),
      decoration: InputDecoration(
        isDense: true,
        counterText: '',
        labelText: 'Your name',
        labelStyle: GoogleFonts.inter(color: const Color(0xFF8E97AB)),
        helperText: compact
            ? null
            : 'Sent only with this message. Admin sees it as “name typed by '
                'sender”.',
        helperMaxLines: 2,
        helperStyle: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF8E97AB)),
        errorText: error,
        prefixIcon: const Icon(Icons.person_outline, size: 20, color: Color(0xFF8E97AB)),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: compact ? 10 : 14,
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(compact ? 14 : 16),
          borderSide: const BorderSide(color: line, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(compact ? 14 : 16),
          borderSide: const BorderSide(color: line, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(compact ? 14 : 16),
          borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
        ),
      ),
    );
  }
}

/// "Send as: 🔒 Anonymous / 👤 With my name". Anonymous is the default.
/// Used in Suggestion Box, Weekly Pulse and broadcast comments, so it
/// looks the same everywhere.
class SendAsChoice extends StatelessWidget {
  const SendAsChoice({
    super.key,
    required this.named,
    required this.onChanged,
    this.enabled = true,
    this.compact = false,
  });

  /// True: "With my name" is chosen.
  final bool named;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  /// Smaller, without the "SEND AS" label (broadcast comment box).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const line = Color(0xFFE3E8F1);
    Widget chip(String label, bool value) {
      final selected = named == value;
      return Expanded(
        child: Material(
          color: selected ? AppColors.blueTint : Colors.white,
          shape: StadiumBorder(
            side: BorderSide(
              color: selected ? AppColors.blue : line,
              width: 1.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? () => onChanged(value) : null,
            child: SizedBox(
              height: compact ? 36 : 44,
              child: Center(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: compact ? 13 : 14,
                    color: selected ? AppColors.blue : const Color(0xFF5F6A84),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final chips = Row(
      children: [
        chip('🔒 Anonymous', false),
        const SizedBox(width: 10),
        chip('👤 With my name', true),
      ],
    );
    if (compact) return chips;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SEND AS',
          style: GoogleFonts.inter(
            fontSize: 12,
            letterSpacing: 0.7,
            color: const Color(0xFF8E97AB),
          ),
        ),
        const SizedBox(height: 8),
        chips,
      ],
    );
  }
}

/// The small line under Send: "🔒 Sent without your name" or
/// "👤 Sent as Ravi Kumar".
class SentAsLine extends StatelessWidget {
  const SentAsLine({super.key, required this.named, required this.name});

  final bool named;
  final String name;

  @override
  Widget build(BuildContext context) {
    final n = name.trim();
    final text = !named
        ? '🔒 Sent without your name'
        : (n.isEmpty ? '👤 Type your name above' : '👤 Sent as $n');
    return Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF8E97AB)),
    );
  }
}
