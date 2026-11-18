import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../widgets/ui.dart';

TextStyle _t(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.ink,
  double? height,
}) => GoogleFonts.inter(
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
  letterSpacing: 0,
);

const Color _soft = Color(0xCC0E1A3A);
const Color _page = Color(0xFFF4F6FA);
const Color _divider = Color(0xFFEEF1F6);

/// Full privacy policy (also given to the App Store and Play Store).
const String _privacyUrl = 'https://haystek-pulse.web.app/privacy.html';

/// One question and its answer.
class _Qa {
  const _Qa(this.icon, this.q, this.a);
  final IconData icon;
  final String q;
  final String a;
}

/// A group of questions under a small heading.
class _Group {
  const _Group(this.title, this.items);
  final String title;
  final List<_Qa> items;
}

// ---------------------------------------------------------------------
// Employee questions (same words as before, now in 3 groups).
// ---------------------------------------------------------------------
const List<_Group> _employeeGroups = [
  _Group('YOUR PRIVACY', [
    _Qa(
      Icons.person_outline_rounded,
      'Will admin know it’s me?',
      'No. Everything you send is anonymous by default.\n\n'
          'If you want admin to know, choose “With my name” and type your name '
          'before you send. Your name is shown only on that one message.',
    ),
    _Qa(
      Icons.visibility_outlined,
      'Who reads my messages?',
      'Only admins. Other employees can’t see them.',
    ),
    _Qa(
      Icons.shield_outlined,
      'Can anyone find out a message is mine?',
      'No. Messages are saved with no name and no ID. Nobody can tell which '
          'ones are yours: not admin, not the developer.',
    ),
    _Qa(
      Icons.smartphone_rounded,
      'Does the app store anything about my phone?',
      'Only a scrambled phone ID, so each phone has one account and the app '
          'can find your account after a reinstall. It is never used for ads or '
          'tracking, and it is deleted when you delete your account.',
    ),
    _Qa(
      Icons.lock_outline_rounded,
      'Is my data encrypted?',
      'Yes. Messages are stored encrypted, so in the database they look like '
          'scrambled text. Admin reads them in the app. Your list of sent '
          'messages is locked with your recovery code.',
    ),
  ]),
  _Group('USING THE APP', [
    _Qa(
      Icons.auto_awesome_outlined,
      'What can I do here?',
      '• Suggestion Box: send an idea or a problem to admin, any time.\n'
          '• Weekly Pulse: once a week, tap how your week was.\n'
          '• Broadcast: read updates from admin and comment.\n'
          '• My Feedback: see everything you sent, its status and admin’s '
          'replies.',
    ),
    _Qa(
      Icons.show_chart_rounded,
      'What does admin see in Weekly Pulse?',
      '• Great or Good: admin sees only the count, like “Great 12 · Good 6”. '
          'Not who chose it.\n'
          '• Okay or Difficult: you write a few words, and admin reads them. '
          'Your name is not shown, unless you choose “With my name”.',
    ),
    _Qa(
      Icons.event_outlined,
      'When is the Weekly Pulse open?',
      'Once a week, for a few days. Home shows when it opens and closes, '
          'and you get a notification just before it opens.',
    ),
    _Qa(
      Icons.edit_off_outlined,
      'Can I change my Weekly Pulse answer?',
      'No, there’s one answer per week. If you want to add something, use '
          'the Suggestion Box.',
    ),
    _Qa(
      Icons.chat_bubble_outline_rounded,
      'Can admin reply to me?',
      'Yes. You get a notification and see the reply in My Feedback. You can '
          'reply back, like a chat. Admin still doesn’t know it’s you.',
    ),
  ]),
  _Group('YOUR ACCOUNT', [
    _Qa(
      Icons.help_outline_rounded,
      'Why no email or name to sign up?',
      'So nobody can tell who you are. You join with a code from Pulse Codes '
          'in Zoho. Codes are not linked to anyone, so they only show you are from '
          'Haystek, not who you are.',
    ),
    _Qa(
      Icons.key_outlined,
      'What is my recovery code?',
      '10 letters and numbers, like K7M2P-X9F4R. The app gives it '
          'to you when you join.\n\n'
          'You need it only when you change to a new phone. On the new phone, '
          'tap “I have my recovery code” and enter it. Your account moves to '
          'the new phone, and the old phone is signed out.\n\n'
          'You can see it any time in Profile → My recovery code. Keep it safe '
          'and don’t share it.',
    ),
    _Qa(
      Icons.sync_rounded,
      'I reinstalled the app or got a new phone.',
      '• Same phone: the app finds your account. Tap Continue.\n'
          '• New phone: tap “I have my recovery code” and enter it. Your '
          'account moves to the new phone, and the old phone is signed out.',
    ),
    _Qa(
      Icons.report_gmailerrorred_rounded,
      'I lost my phone and my code.',
      'Lost only your phone? Use your recovery code on the new phone.\n\n'
          'Lost both? Join again with a new code from Pulse Codes in Zoho. '
          'Admin keeps your old messages, but your history in the app is gone.',
    ),
    _Qa(
      Icons.delete_outline_rounded,
      'When should I delete my account?',
      'Only when you leave Haystek. You don’t need to delete it for a new '
          'phone or a reinstall.\n\n'
          'Profile → Delete my account. Your recovery code stops working and '
          'your history in the app is removed. Messages you sent stay with '
          'admin exactly as you sent them: anonymous ones stay anonymous, and '
          'ones sent “With my name” keep that name.',
    ),
  ]),
];

// ---------------------------------------------------------------------
// Admin questions (new wording – check with Ma'am).
// ---------------------------------------------------------------------
const List<_Group> _adminGroups = [
  _Group('PRIVACY', [
    _Qa(
      Icons.person_outline_rounded,
      'Can I see who sent a message?',
      'No. You see a name only when the employee chooses “With my name” for '
          'that one message. Everything else shows as Anonymous, even to '
          'admins.',
    ),
    _Qa(
      Icons.show_chart_rounded,
      'What do I see in Weekly Pulse?',
      '• Great and Good: only the count, like “Great 12 · Good 6”.\n'
          '• Okay and Difficult: the few words they wrote, without a name '
          'unless they chose “With my name”.\n'
          '• The week’s result shows once at least a quarter of people have '
          'answered (at least 3).',
    ),
    _Qa(
      Icons.lock_outline_rounded,
      'Is the data encrypted?',
      'Yes. Messages are stored encrypted, so in the database they look like '
          'scrambled text. You read them here in the app.',
    ),
  ]),
  _Group('REPLYING', [
    _Qa(
      Icons.sell_outlined,
      'What do the statuses mean?',
      '• Under Review: we are looking at it.\n'
          '• Planned: we will do it.\n'
          '• In Progress: work has started.\n'
          '• Implemented: done (a reply is needed).\n'
          '• Noted: needs no work.\n\n'
          'The employee sees every change in their chat.',
    ),
    _Qa(
      Icons.task_alt_rounded,
      'What does “Employee + everyone” do?',
      'When you mark something Implemented, you can tell only the employee, '
          'or the employee and everyone. Everyone sees it as a broadcast with '
          'the suggestion as the title, never the sender’s name.',
    ),
    _Qa(
      Icons.campaign_outlined,
      'When should I send a broadcast?',
      'For news everyone should know, like a change you made. Everyone gets '
          'a notification and can comment. You can delete a broadcast later.',
    ),
    _Qa(
      Icons.notifications_none_rounded,
      'What does Remind do?',
      'While the Weekly Pulse is open, Remind sends a notification to the '
          'people who haven’t answered yet. You don’t see who they are.',
    ),
  ]),
  _Group('ADMIN ACCOUNT', [
    _Qa(
      Icons.vpn_key_outlined,
      'What is the admin code?',
      'New admins need it to sign up with their work email. See it in '
          'Profile → Admin code. If it was shared by mistake, use Reset admin '
          'code: the old code stops working.',
    ),
    _Qa(
      Icons.swap_horiz_rounded,
      'Can I also use the app as an employee?',
      'Yes. Profile → Also join as Employee, with your recovery code or entry '
          'code. Then switch between Admin and Employee from Profile. Your '
          'employee side stays anonymous.',
    ),
    _Qa(
      Icons.password_rounded,
      'Where do I change my password?',
      'Profile → Change password. Use at least 8 characters.',
    ),
  ]),
];

/// Profile → Help & Privacy. Questions in groups; each opens when tapped.
/// [admin]: admin questions and "Your promise to the team" on top.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key, this.admin = false});

  final bool admin;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final groups = admin ? _adminGroups : _employeeGroups;
    return Theme(
      data: t.copyWith(
        textTheme: GoogleFonts.interTextTheme(t.textTheme),
        dividerColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: _page,
        appBar: AppBar(
          backgroundColor: _page,
          surfaceTintColor: _page,
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
                  _Promise(admin: admin),
                  for (final g in groups) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
                      child: Text(
                        g.title,
                        style: _t(12, weight: FontWeight.w700, color: _soft)
                            .copyWith(letterSpacing: 0.6),
                      ),
                    ),
                    Material(
                      color: Colors.white,
                      elevation: 1.5,
                      shadowColor: const Color(0x330E1A3A),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var i = 0; i < g.items.length; i++) ...[
                            if (i > 0)
                              const Divider(
                                height: 1,
                                thickness: 1,
                                color: _divider,
                              ),
                            _QaTile(qa: g.items[i]),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const _PrivacyLink(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The blue card on top.
class _Promise extends StatelessWidget {
  const _Promise({required this.admin});

  final bool admin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A3A8F), AppColors.blue],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              admin ? Icons.shield_outlined : Icons.lock_outline_rounded,
              size: 20,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  admin ? 'Your promise to the team' : 'Anonymous by default',
                  style: _t(15.5, weight: FontWeight.w700, color: Colors.white),
                ),
                const SizedBox(height: 3),
                Text(
                  admin
                      ? 'You see every message, but never who wrote it, '
                            'unless they choose “With my name”. This is what '
                            'makes people speak openly.'
                      : 'Nobody can tell which messages are yours: not '
                            'admin, not the developer.',
                  style: _t(
                    13.5,
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
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
  bool _open = false;

  void _opened(bool open) {
    setState(() => _open = open);
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
      color: _open ? const Color(0xFFFAFBFE) : Colors.white,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(14, 4, 12, 4),
        childrenPadding: const EdgeInsets.fromLTRB(60, 0, 16, 14),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        iconColor: AppColors.blue,
        collapsedIconColor: _soft,
        shape: const Border(),
        collapsedShape: const Border(),
        onExpansionChanged: _opened,
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.blueTint,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(qa.icon, size: 18, color: AppColors.blue),
        ),
        title: Text(
          qa.q,
          style: _t(14.5, weight: FontWeight.w500, height: 1.35),
        ),
        children: [
          Text(qa.a, style: _t(13.5, color: _soft, height: 1.5)),
        ],
      ),
    );
  }
}

/// Opens the full privacy policy (inside the app when possible).
class _PrivacyLink extends StatelessWidget {
  const _PrivacyLink();

  Future<void> _open(BuildContext context) async {
    final uri = Uri.parse(_privacyUrl);
    final messenger = ScaffoldMessenger.of(context);
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {}
    if (!ok) {
      try {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not open the page. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 1.5,
      shadowColor: const Color(0x330E1A3A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.blueTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  size: 20,
                  color: AppColors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Privacy Policy',
                      style: _t(15, weight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Read the full policy',
                      style: _t(13, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.open_in_new_rounded, size: 18, color: _soft),
            ],
          ),
        ),
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
              child: const Icon(
                Icons.shield_outlined,
                size: 17,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 9),
            Text('Help & Privacy', style: _t(16)),
          ],
        ),
      ),
    );
  }
}
