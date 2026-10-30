import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/employee.dart';
import '../services/feedback_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'help_screen.dart';

/// Soft greys used on this screen.
const _panel = Color(0xFFF6F8FB);
const _line = Color(0xFFE3E8F1);
const _soft = Color(0xFF8E97AB);
const _tickOff = Color(0xFFC9D0DC);

/// Inter with a chosen size, weight and colour.
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

/// Inter for titles on this screen (same as the home screen).
TextStyle _title(double size, {Color color = AppColors.ink}) => GoogleFonts.inter(
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

  bool _anonymous = false;
  bool _busy = false;
  bool _submitted = false;
  String? _error;

  bool get _empty => _text.text.trim().isEmpty;

  @override
  void initState() {
    super.initState();
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
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
        textTheme: GoogleFonts.interTextTheme(theme.textTheme),
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
    final theme = Theme.of(context);
    // Keyboard open: fold the title away to make room.
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Form(
      key: _formKey,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: typing
                            ? const SizedBox(width: double.infinity)
                            : Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: _header(),
                        ),
                      ),
                      Text(
                        'YOUR MESSAGE',
                        style: _t(
                          13,
                          weight: FontWeight.w700,
                          color: AppColors.muted,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _writingBox(),
                      const SizedBox(height: 14),
                      _hideNameRow(),
                      _privacyLink(),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: _t(14, color: theme.colorScheme.error),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Button and note stay at the bottom, above the keyboard.
          SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DecoratedBox(
                        // Soft blue glow under the button when it's ready.
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: _empty || _busy
                              ? null
                              : [
                            BoxShadow(
                              color:
                              AppColors.blue.withValues(alpha: 0.28),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: FilledButton(
                          onPressed: _busy || _empty ? null : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.blue,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: _line,
                            disabledForegroundColor: _soft,
                            minimumSize: const Size.fromHeight(56),
                            shape: const StadiumBorder(),
                            textStyle: _t(16, weight: FontWeight.w700),
                          ),
                          child: _busy
                              ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 10),
                              Text('Sending…'),
                            ],
                          )
                              : Text(
                            _anonymous
                                ? 'Send anonymously'
                                : 'Send suggestion',
                          ),
                        ),
                      ),
                      // Hidden while typing, to give the box more room.
                      if (!typing) ...[
                        const SizedBox(height: 12),
                        Text(
                          'You can follow it in My Feedback',
                          textAlign: TextAlign.center,
                          style: _t(13.5, color: _soft),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
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
        border: Border.all(
          color: focused ? AppColors.blue : _line,
          width: 1.5,
        ),
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
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const HelpScreen()),
        ),
        icon: const Icon(Icons.help_outline_rounded, size: 16),
        label: const Text('How is my name hidden?'),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.blue,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          textStyle: GoogleFonts.inter(fontSize: 13.5),
        ),
      ),
    );
  }

  /// "Keep my name hidden": checkbox on the left, white row with a border.
  /// When ticked the row turns light blue. Tap anywhere on the row.
  Widget _hideNameRow() {
    return Semantics(
      checked: _anonymous,
      child: Material(
        color: _anonymous ? AppColors.blueTint : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: _anonymous ? AppColors.blue : _line,
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _busy ? null : () => setState(() => _anonymous = !_anonymous),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: _anonymous ? AppColors.blue : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _anonymous ? AppColors.blue : _tickOff,
                      width: 2,
                    ),
                  ),
                  child: _anonymous
                      ? const Icon(Icons.check_rounded,
                      size: 16, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Keep my name hidden',
                        style: _t(15.5, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _anonymous
                            ? 'Admin won’t know it’s you'
                            : 'Admin will see: ${widget.employee.name}',
                        maxLines: 2,
                        style: _t(13, color: AppColors.muted, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
              style: GoogleFonts.inter(
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