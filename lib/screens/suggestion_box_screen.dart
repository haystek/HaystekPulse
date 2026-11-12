import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/employee.dart';
import '../services/feedback_service.dart';
import '../services/typed_name.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'help_screen.dart';
import 'typed_name_field.dart';

/// Soft greys used on this screen.
const _panel = Color(0xFFF6F8FB);
const _line = Color(0xFFE3E8F1);
const _soft = Color(0xFF8E97AB);

/// Inter with a chosen size, weight and colour.
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

/// Inter for titles on this screen (same as the home screen).
TextStyle _title(double size, {Color color = AppColors.ink}) =>
    GoogleFonts.figtree(
      fontSize: size,
      fontWeight: FontWeight.w800,
      color: color,
      letterSpacing: -0.8,
      height: 1.15,
    );

/// Suggestion Box ("Clean" design):
/// - back arrow on the left, "Suggestion Box" pill on the right,
/// - a big title and a short line,
/// - "YOUR MESSAGE" and the writing box with a counter,
/// - "Keep my name hidden" with a checkbox (turns light blue when ticked),
/// - the Send button and a short note at the bottom, above the keyboard.
///
/// When the keyboard opens, the title folds away and the writing box
/// moves up, so it always stays visible above the button.
class SuggestionBoxScreen extends StatefulWidget {
  const SuggestionBoxScreen({super.key, required this.employee});

  final Employee employee;

  @override
  State<SuggestionBoxScreen> createState() => _SuggestionBoxScreenState();
}

class _SuggestionBoxScreenState extends State<SuggestionBoxScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _boxKey = GlobalKey();
  final _text = TextEditingController();

  /// One id for this suggestion, so Send can be tapped again safely after
  /// an error: it can never make a second copy.
  late final String _id = FeedbackService.instance.newSuggestionId();
  final _focus = FocusNode();

  /// No name in the app (joined with an entry code): they type one.
  late final bool _needsName = TypedName.needed(widget.employee);

  /// Anonymous by default. "With my name" is a choice for this message.
  bool _anonymous = true;
  final _name = TextEditingController();
  String? _nameError;
  bool _busy = false;
  bool _submitted = false;
  String? _error;

  bool get _empty => _text.text.trim().isEmpty;

  @override
  void initState() {
    super.initState();
    if (_needsName) {
      TypedName.load().then((n) {
        if (mounted && _name.text.isEmpty) setState(() => _name.text = n);
      });
    }
    WidgetsBinding.instance.addObserver(this);
    _focus.addListener(() {
      if (!mounted) return;
      setState(() {});
      if (_focus.hasFocus) _showBox();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _text.dispose();
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Keyboard opened or changed size: bring the writing box into view.
  @override
  void didChangeMetrics() {
    if (_focus.hasFocus) _showBox();
  }

  void _showBox() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _boxKey.currentContext;
      if (!mounted || ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// The name shown with the message ('' when hidden).
  String get _shownName =>
      _needsName ? _name.text.trim() : widget.employee.name;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_needsName && !_anonymous) {
      final problem = TypedName.check(_name.text);
      setState(() => _nameError = problem);
      if (problem != null) return;
      unawaited(TypedName.save(_name.text));
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FeedbackService.instance.submitSuggestion(
        employee: widget.employee,
        text: _text.text,
        anonymous: _anonymous,
        id: _id,
        name: _needsName && !_anonymous ? _name.text.trim() : null,
      );
      if (!mounted) return;
      setState(() => _submitted = true);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is SendError
            ? error.message
            : 'Could not send. Please check your internet connection '
                  'and try again.',
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
        textTheme: GoogleFonts.figtreeTextTheme(theme.textTheme),
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          leadingWidth: 68,
          leading: const AppBackButton(),
          // No title on the left: the name sits on the right in a pill.
          title: const SizedBox.shrink(),
          actions: const [
            _TitlePill('Suggestion Box', icon: Icons.lightbulb_outline),
          ],
        ),
        body: _submitted ? _buildDone(context) : _buildForm(context),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    // SB2 design: intro + tappable examples on top, chat-style box at the
    // bottom. The box sits above the keyboard, so it moves up with it.
    TextStyle t(double size, {FontWeight weight = FontWeight.w400, Color? color, double? height}) =>
        GoogleFonts.figtree(fontSize: size, fontWeight: weight, color: color ?? AppColors.ink, height: height);
    const line = Color(0xFFE3E8F1);
    const soft = Color(0xFFF5F7FB);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final named = !_anonymous;
    final count = _text.text.length;

    const examples = [
      'A quiet room for phone calls',
      'Drinking water bottles in every meeting room',
      'Better Wi-Fi in the conference room',
      'Healthy snacks in the pantry',
    ];

    void useExample(String e) {
      _text.text = e;
      _text.selection = TextSelection.collapsed(offset: e.length);
      _focus.requestFocus();
      setState(() {});
    }

    Widget pill(String label, IconData icon, bool on, VoidCallback onTap) {
      return Material(
        color: on ? AppColors.blueTint : Colors.white,
        shape: StadiumBorder(side: BorderSide(color: on ? AppColors.blue : line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(on ? Icons.check : icon, size: 15, color: on ? AppColors.blue : AppColors.muted),
                const SizedBox(width: 6),
                Text(label, style: t(13, weight: FontWeight.w600, color: on ? AppColors.blue : AppColors.muted)),
              ],
            ),
          ),
        ),
      );
    }

    final canSend = !_busy && !_empty;

    return Form(
      key: _formKey,
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusScope.of(context).unfocus(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.blueTint,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(Icons.lightbulb_outline, color: AppColors.blue, size: 26),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('Share an idea or a concern',
                      style: t(24, weight: FontWeight.w700, height: 1.2)),
                  const SizedBox(height: 6),
                  Text('Write below and send. You can follow the reply in My Feedback.',
                      style: t(15, color: AppColors.muted, height: 1.5)),
                  if (!keyboard) ...[
                    const SizedBox(height: 26),
                    Text('FOR EXAMPLE',
                        style: t(12, weight: FontWeight.w600, color: AppColors.muted)
                            .copyWith(letterSpacing: 1)),
                    const SizedBox(height: 10),
                    for (final e in examples)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: soft,
                          borderRadius: BorderRadius.circular(14),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: _busy ? null : () => useExample(e),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
                              child: Row(
                                children: [
                                  Expanded(child: Text(e, style: t(14.5, color: const Color(0xFF475467)))),
                                  const Icon(Icons.north_west, size: 16, color: AppColors.muted),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          // The box: always at the bottom, above the keyboard.
          Container(
            key: _boxKey,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFEEF1F6))),
            ),
            padding: EdgeInsets.fromLTRB(
              16, 12, 16, 12 + (keyboard ? 0 : MediaQuery.paddingOf(context).bottom),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Send as', style: t(13, color: AppColors.muted)),
                    const SizedBox(width: 8),
                    pill('Anonymous', Icons.lock_outline, _anonymous,
                        () => setState(() => _anonymous = true)),
                    const SizedBox(width: 8),
                    pill('With my name', Icons.person_outline, named, () {
                      setState(() => _anonymous = false);
                    }),
                  ],
                ),
                if (named && _needsName) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _name,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.words,
                    style: t(15),
                    decoration: InputDecoration(
                      hintText: 'Your name',
                      hintStyle: t(15, color: const Color(0xFF98A2B3)),
                      prefixIcon: const Icon(Icons.person_outline, size: 20, color: AppColors.muted),
                      isDense: true,
                      filled: true,
                      fillColor: soft,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    validator: (v) => !_anonymous && _needsName && (v == null || v.trim().isEmpty)
                        ? 'Please type your name'
                        : null,
                  ),
                ],
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 4, 6, 6),
                  decoration: BoxDecoration(
                    color: _focus.hasFocus || !_empty ? Colors.white : soft,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _focus.hasFocus || !_empty ? AppColors.blue : line,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _text,
                          focusNode: _focus,
                          enabled: !_busy,
                          minLines: 1,
                          maxLines: 6,
                          maxLength: FeedbackService.maxTextLength,
                          textCapitalization: TextCapitalization.sentences,
                          style: t(16, height: 1.45),
                          onChanged: (_) => setState(() {}),
                          onTap: () => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Write your suggestion…',
                            hintStyle: t(16, color: const Color(0xFF98A2B3)),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            filled: false,
                            counterText: '',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Please write your suggestion'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Material(
                        color: canSend ? AppColors.blue : const Color(0xFFE4E8F0),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: canSend ? _submit : null,
                          child: SizedBox(
                            width: 42,
                            height: 42,
                            child: _busy
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : Icon(Icons.send_rounded,
                                    size: 19,
                                    color: canSend ? Colors.white : const Color(0xFF8A94A8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      '${named ? 'Admin will see your name' : 'Your name stays hidden'}'
                      '  ·  $count / ${FeedbackService.maxTextLength}',
                      style: t(12.5, color: AppColors.muted),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Big title and a short line.

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What would you like to share?', style: _title(28)),
        const SizedBox(height: 8),
        Text(
          'Ideas, concerns, requests, anything that would make the office '
          'better.',
          style: _t(15, color: AppColors.muted, height: 1.45),
        ),
      ],
    );
  }

  /// The writing box: light grey, white with a blue border while typing.
  Widget _writingBox() {
    final focused = _focus.hasFocus;
    return AnimatedContainer(
      key: _boxKey,
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      decoration: BoxDecoration(
        color: focused ? Colors.white : _panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: focused ? AppColors.blue : _line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _text,
            focusNode: _focus,
            // Fixed height: long text scrolls inside the box.
            minLines: 6,
            maxLines: 6,
            maxLength: FeedbackService.maxTextLength,
            enabled: !_busy,
            textCapitalization: TextCapitalization.sentences,
            scrollPadding: const EdgeInsets.only(bottom: 80),
            onChanged: (_) => setState(() {}),
            style: _t(16, height: 1.5),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.zero,
              hintText: 'Tell us what’s on your mind…',
              hintMaxLines: 2,
              hintStyle: _t(15.5, color: _soft, height: 1.5),
              counterText: '',
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Please write your issue or suggestion'
                : null,
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${_text.text.length} / ${FeedbackService.maxTextLength}',
              style: _t(12, color: _soft),
            ),
          ),
        ],
      ),
    );
  }

  /// "How is my name hidden?" under the hide-name row. Opens Help & Privacy.
  Widget _privacyLink() {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const HelpScreen())),
        icon: const Icon(Icons.help_outline_rounded, size: 16),
        label: const Text('How is my name hidden?'),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.blue,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          textStyle: GoogleFonts.figtree(fontSize: 13.5),
        ),
      ),
    );
  }

  Widget _buildDone(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
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
                Text(
                  _anonymous
                      ? 'Thank you. It was sent without your name. '
                            'You can follow it in My Feedback.'
                      : 'Thank you. You can follow it in My Feedback.',
                  textAlign: TextAlign.center,
                  style: _t(15.5, color: AppColors.muted, height: 1.4),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    minimumSize: const Size.fromHeight(56),
                    shape: const StadiumBorder(),
                    textStyle: _t(16, weight: FontWeight.w700),
                  ),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Screen name on the right of the AppBar: pill with an icon.
class _TitlePill extends StatelessWidget {
  const _TitlePill(this.text, {required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Container(
        height: 42,
        padding: const EdgeInsets.fromLTRB(5, 5, 16, 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(21),
          border: Border.all(color: AppColors.blue.withValues(alpha: 0.35)),
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
              child: Icon(icon, size: 17, color: Colors.white),
            ),
            const SizedBox(width: 9),
            Text(
              text,
              style: GoogleFonts.figtree(
                fontSize: 16,
                fontWeight: FontWeight.normal,
                color: AppColors.ink,
                letterSpacing: -0.4,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
