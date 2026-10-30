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
    'What can I do in this app?',
    'Two things:\n'
        '• Suggestion Box: send an idea or a problem to admin, any time.\n'
        '• Weekly Pulse: once a week, tell admin how your week was.',
  ),
  _Qa(
    'Who reads what I send?',
    'Only admins. Other employees can’t see it, and the developer can’t '
        'see who sent it.',
  ),
  _Qa(
    'Will admin know it was me?',
    'You decide, every time:\n'
        '• Hide my name: admin reads your message but does not know who '
        'sent it.\n'
        '• Show my name: admin sees your name with the message.',
  ),
  _Qa(
    'In Weekly Pulse, does admin see my answer?',
    'Admin sees only numbers, like “Great 5 · Good 3 · Okay 2 · '
        'Difficult 1”. Admin does not see what you chose.\n\n'
        'If you choose Okay or Difficult, you can add a comment. You choose '
        'again: hide or show your name. If you show your name, admin will '
        'know your answer.',
  ),
  _Qa(
    'Can admin reply if my name is hidden?',
    'Yes. Admin replies to the message and you get a notification. You can '
        'reply back, like a chat. Admin still doesn’t know it’s you.',
  ),
  _Qa(
    'Can anyone find out who sent a hidden message?',
    'No. Hidden messages are saved without your name and without any ID '
        'that points to you. Not admin, not the developer.',
  ),
  _Qa(
    'Where can I see my old messages?',
    'In My Feedback. Only you can see them: the list is locked with your '
        'password.',
  ),
  _Qa(
    'What if I change my phone?',
    'Sign in with the same email and password. Everything comes back.',
  ),
  _Qa(
    'What if I forget my password?',
    'Reset it from the sign-in screen, then enter your backup code (given '
        'at sign-up). Without the backup code, your old messages can’t be '
        'shown again. Admin still has them.',
  ),
  _Qa(
    'I lost my backup code. What now?',
    'While you still know your password: Profile → Backup code → make a '
        'new one. The old code stops working.',
  ),
];

/// Profile → Help & Privacy. Questions open when tapped, and a small
/// "Who sees what" table at the end.
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
                            'Name hidden means nobody knows it’s you. '
                            'Not admin, not the developer.',
                            style: _t(14.5, height: 1.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  for (final qa in _questions) _QaTile(qa: qa),
                  const SizedBox(height: 22),
                  Text('Who sees what', style: _t(16, weight: FontWeight.w500)),
                  const SizedBox(height: 10),
                  const _WhoSeesWhat(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QaTile extends StatelessWidget {
  const _QaTile({required this.qa});

  final _Qa qa;

  @override
  Widget build(BuildContext context) {
    return Container(
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
        title: Text(qa.q, style: _t(15, weight: FontWeight.w500)),
        children: [
          Text(qa.a, style: _t(14, color: AppColors.muted, height: 1.5)),
        ],
      ),
    );
  }
}

/// You / Admin / Developer, row by row.
class _WhoSeesWhat extends StatelessWidget {
  const _WhoSeesWhat();

  @override
  Widget build(BuildContext context) {
    const rows = [
      // The developer can still open the database (message text and a
      // shown name). Change these two to false once only admins can read
      // posts (admin lock).
      ('Your messages', true, true, true),
      ('Your name (shown)', true, true, true),
      ('Your name (hidden)', true, false, false),
      ('Your Weekly Pulse choice', true, false, false),
      ('Your list of old messages', true, false, false),
    ];

    Widget mark(bool yes) => Icon(
          yes ? Icons.check_circle_rounded : Icons.remove_circle_outline,
          size: 18,
          color: yes ? const Color(0xFF16A34A) : const Color(0xFFC9D0DC),
        );

    Widget head(String s) => SizedBox(
          width: 64,
          child: Text(s,
              textAlign: TextAlign.center,
              style: _t(12, weight: FontWeight.w500, color: _soft)),
        );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line, width: 1.2),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
            child: Row(
              children: [
                const Expanded(child: SizedBox()),
                head('You'),
                head('Admin'),
                head('Developer'),
              ],
            ),
          ),
          for (final r in rows) ...[
            const Divider(height: 1, color: Color(0xFFF0F2F7)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 6, 11),
              child: Row(
                children: [
                  Expanded(child: Text(r.$1, style: _t(13.5))),
                  SizedBox(width: 64, child: Center(child: mark(r.$2))),
                  SizedBox(width: 64, child: Center(child: mark(r.$3))),
                  SizedBox(width: 64, child: Center(child: mark(r.$4))),
                ],
              ),
            ),
          ],
          const Divider(height: 1, color: Color(0xFFF0F2F7)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Text(
              'Weekly Pulse: admin sees only the totals.',
              style: _t(12, color: _soft),
            ),
          ),
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
