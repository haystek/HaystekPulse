import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import '../widgets/ui.dart';

TextStyle _t(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.ink,
  double? height,
}) =>
    GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );

const Color _soft = Color(0xFF8E97AB);
const Color _line = Color(0xFFE3E8F1);

/// One question and its answer.
class _Qa {
  const _Qa(this.q, this.a);
  final String q;
  final String a;
}

const List<_Qa> _questions = [
  _Qa(
    'What can I do here?',
    '• Suggestion Box: send an idea or a problem to admin, any time.\n'
        '• Weekly Pulse: once a week, tap how your week was.\n'
        '• Broadcast: read updates from admin and comment.',
  ),
  _Qa(
    'Will admin know it’s me?',
    'No. Everything you send is anonymous by default.\n\n'
        'If you want admin to know, choose “With my name” and type your name '
        'before you send. Your name is shown only on that one message.',
  ),
  _Qa(
    'Who reads my messages?',
    'Only admins. Other employees can’t see them.',
  ),
  _Qa(
    'Can anyone find out a message is mine?',
    'No. Messages are saved with no name and no ID. Nobody can tell which '
        'ones are yours: not admin, not the developer.',
  ),
  _Qa(
    'Is my data encrypted?',
    'Yes. Messages are stored encrypted, so in the database they look like '
        'scrambled text. Admin reads them in the app. Your list of sent '
        'messages is locked with your personal code.',
  ),
  _Qa(
    'What does admin see in Weekly Pulse?',
    '• Great or Good: admin sees only the count, like “Great 12 · Good 6”. '
        'Not who chose it.\n'
        '• Okay or Difficult: you write a few words, and admin reads them. '
        'Your name is not shown, unless you choose “With my name”.',
  ),
  _Qa(
    'Can admin reply to me?',
    'Yes. You get a notification and see the reply in My Feedback. You can '
        'reply back, like a chat. Admin still doesn’t know it’s you.',
  ),
  _Qa(
    'Why no email or name to sign up?',
    'So nobody can tell who you are. You join with a code from Pulse Codes '
        'in Zoho. Codes are not linked to anyone, so they only show you are from '
        'Haystek, not who you are.',
  ),
  _Qa(
    'What is my personal code?',
    '10 letters and numbers, like K7M2P-X9F4R. The app gives it '
        'to you when you join.\n\n'
        'You need it only when you change to a new phone. You can see it any '
        'time in Profile → My personal code. Keep it safe and don’t share it.',
  ),
  _Qa(
    'I reinstalled the app or got a new phone.',
    '• Same phone: the app finds your account. Tap Continue.\n'
        '• New phone: tap “I have my personal code” and enter it.',
  ),
  _Qa(
    'I lost my phone and my code.',
    'Join again with a new code from Pulse Codes in Zoho. Admin keeps your old messages, but your '
        'history in the app is gone.',
  ),
  _Qa(
    'When should I delete my account?',
    'Only when you leave Haystek. You don’t need to delete it for a new '
        'phone or a reinstall.\n\n'
        'Profile → Delete my account. Your personal code stops working and '
        'your history in the app is removed. Messages you sent stay with '
        'admin, without your name.',
  ),
];

/// Profile → Help & Privacy. Questions open when tapped.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Theme(
      data: t.copyWith(
        textTheme: GoogleFonts.interTextTheme(t.textTheme),
        dividerColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          leadingWidth: 68,
          leading: const AppBackButton(),
          title: const SizedBox.shrink(),
          actions: const [_TitlePill()],
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  // Short promise at the top.
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.blueTint,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.lock_outline_rounded,
                            color: AppColors.blue, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Everything is anonymous by default. Nobody can '
                            'tell which messages are yours: not admin, not '
                            'the developer.',
                            style: _t(14.5, height: 1.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  for (final qa in _questions) _QaTile(qa: qa),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One question. When opened, it scrolls up so the whole answer shows
/// (no need to scroll by hand, even for the last question).
class _QaTile extends StatefulWidget {
  const _QaTile({required this.qa});

  final _Qa qa;

  @override
  State<_QaTile> createState() => _QaTileState();
}

class _QaTileState extends State<_QaTile> {
  final _key = GlobalKey();

  void _opened(bool open) {
    if (!open) return;
    // After the open animation, bring the whole tile into view.
    Future<void>.delayed(const Duration(milliseconds: 260), () {
      final ctx = _key.currentContext;
      if (!mounted || ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final qa = widget.qa;
    return Container(
      key: _key,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(16, 2, 12, 2),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        iconColor: AppColors.blue,
        collapsedIconColor: _soft,
        shape: const Border(),
        collapsedShape: const Border(),
        onExpansionChanged: _opened,
        title: Text(qa.q, style: _t(15, weight: FontWeight.w500)),
        children: [
          Text(qa.a, style: _t(14, color: AppColors.muted, height: 1.5)),
        ],
      ),
    );
  }
}

class _TitlePill extends StatelessWidget {
  const _TitlePill();

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
              child: const Icon(Icons.shield_outlined,
                  size: 17, color: Colors.white),
            ),
            const SizedBox(width: 9),
            Text('Help & Privacy', style: _t(16)),
          ],
        ),
      ),
    );
  }
}
