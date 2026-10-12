import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/employee.dart';
import '../services/feedback_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Inter for titles on this screen (same as the home screen).
TextStyle _title(double size) => GoogleFonts.inter(
  fontSize: size,
  fontWeight: FontWeight.w800,
  color: AppColors.ink,
  letterSpacing: -0.5,
  height: 1.2,
);

/// Suggestion Box: one text box, the anonymous option, and a confirmation.
class SuggestionBoxScreen extends StatefulWidget {
  const SuggestionBoxScreen({super.key, required this.employee});

  final Employee employee;

  @override
  State<SuggestionBoxScreen> createState() => _SuggestionBoxScreenState();
}

class _SuggestionBoxScreenState extends State<SuggestionBoxScreen> {
  final _formKey = GlobalKey<FormState>();
  final _text = TextEditingController();
  bool _anonymous = false;
  bool _busy = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FeedbackService.instance.submitSuggestion(
        employee: widget.employee,
        text: _text.text,
        anonymous: _anonymous,
      );
      if (!mounted) return;
      setState(() => _submitted = true);
    } catch (_) {
      if (!mounted) return;
      setState(
            () => _error = 'Could not send. Please check your internet '
            'connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Inter for every text on this screen, buttons and the text box too.
    return Theme(
      data: theme.copyWith(
        textTheme: GoogleFonts.interTextTheme(theme.textTheme),
      ),
      child: Scaffold(
        appBar: AppBar(
          leadingWidth: 68,
          leading: const AppBackButton(),
          title: Text('Suggestion Box', style: _title(20)),
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: _submitted ? _buildDone(context) : _buildForm(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    OutlineInputBorder border(double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(22),
      borderSide: BorderSide(color: AppColors.ink, width: width),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('What would you like to tell us?', style: _title(26)),
            const SizedBox(height: 8),
            const Text(
              'Share an idea or a problem. '
                  'Add a little detail so we understand.',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 15.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _text,
              minLines: 6,
              maxLines: 10,
              maxLength: FeedbackService.maxTextLength,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 17, height: 1.45),
              decoration: InputDecoration(
                hintText: 'Write it here',
                contentPadding: const EdgeInsets.all(18),
                border: border(1.5),
                enabledBorder: border(1.5),
                focusedBorder: border(2),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Please write your issue or suggestion'
                  : null,
            ),
            const SizedBox(height: 8),
            Panel(
              radius: 20,
              padding: const EdgeInsets.fromLTRB(18, 6, 8, 6),
              child: CheckboxListTile(
                value: _anonymous,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _anonymous = v ?? false),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Submit anonymously',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                subtitle: const Text(
                  'Management will not see your name.',
                  style: TextStyle(color: AppColors.muted, fontSize: 14),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                textStyle: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: _busy
                  ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Text('Send suggestion'),
            ),
            const SizedBox(height: 14),
            const Text(
              'You can follow it in My Feedback.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDone(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            child: CircleAvatar(
              radius: 36,
              backgroundColor: AppColors.blue,
              child: Icon(Icons.check, color: Colors.white, size: 40),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Suggestion sent',
            textAlign: TextAlign.center,
            style: _title(26),
          ),
          const SizedBox(height: 8),
          const Text(
            'Thank you. You can follow it in My Feedback.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 15.5),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              textStyle: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}