import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

TextStyle _t(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = Colors.white,
  double? height,
}) => GoogleFonts.inter(
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
);

const Color _sky1 = Color(0xFF0B1B4D);
const Color _sky2 = Color(0xFF14328F);
const Color _dim = Color(0xC7FFFFFF); // white, 78%
const Color _faint = Color(0xB8FFFFFF); // white, 72%
const Color _glass = Color(0x1AFFFFFF); // white, 10%
const Color _glassLine = Color(0x2EFFFFFF); // white, 18%
const Color _glassIcon = Color(0x26FFFFFF); // white, 15%

/// Shows the intro once (the first time the app is opened on this phone),
/// then [child] (the sign-in screen).
class IntroGate extends StatefulWidget {
  const IntroGate({super.key, required this.child});

  final Widget child;

  @override
  State<IntroGate> createState() => _IntroGateState();
}

class _IntroGateState extends State<IntroGate> {
  static const _store = FlutterSecureStorage();

  /// v3: the intro for the entry-code sign-up.
  static const _key = 'intro_seen_v3';

  /// Remembered for this app run, so it is not read again.
  static bool? _seen;

  @override
  void initState() {
    super.initState();
    if (_seen == null) _load();
  }

  Future<void> _load() async {
    bool seen;
    try {
      seen = await _store.read(key: _key) == '1';
    } catch (_) {
      seen = false;
    }
    if (mounted) setState(() => _seen = seen);
  }

  Future<void> _done() async {
    setState(() => _seen = true);
    try {
      await _store.write(key: _key, value: '1');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final seen = _seen;
    if (seen == null) {
      return const Scaffold(backgroundColor: _sky1);
    }
    return seen ? widget.child : IntroScreen(onDone: _done);
  }
}

/// One slide: an icon, a title, a short text and a small picture.
class _Slide {
  const _Slide({
    required this.icon,
    required this.title,
    required this.text,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String text;
  final Widget body;
}

const List<_Slide> _slides = [
  _Slide(
    icon: Icons.chat_bubble_outline_rounded,
    title: 'Say it honestly.',
    text:
        'Share ideas, report problems, and tell us how your week went. '
        'Admin reads every message and replies.',
    body: _Features(),
  ),
  _Slide(
    icon: Icons.lock_outline_rounded,
    title: 'Your name stays hidden',
    text:
        'Everything you send is anonymous. Want credit for a good idea? '
        'Choose “With my name”. Your name shows only on that one message.',
    body: _AdminSees(),
  ),
  _Slide(
    icon: Icons.shield_outlined,
    title: 'Nobody knows it’s you',
    text:
        'No email, no phone number, no name. Your messages carry nothing '
        'that points to you, so admin can’t tell who wrote them.',
    body: _Privacy(),
  ),
  _Slide(
    icon: Icons.key_outlined,
    title: 'Ready in 10 seconds',
    text: 'Just the entry code shared with your team. No sign-up form.',
    body: _JoinSteps(),
  ),
];

/// The intro: all in the brand blue, white text, glass cards, dots and a
/// white button at the bottom. Swipe or tap Next. Skip at the top.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == _slides.length - 1) {
      widget.onDone();
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _slides.length - 1;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _sky1,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_sky1, _sky2, AppColors.blue],
              stops: [0, 0.55, 1],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Skip (hidden on the last slide).
                    SizedBox(
                      height: 48,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: AnimatedOpacity(
                          opacity: last ? 0 : 1,
                          duration: const Duration(milliseconds: 200),
                          child: TextButton(
                            onPressed: last ? null : widget.onDone,
                            style: TextButton.styleFrom(
                              foregroundColor: _dim,
                              textStyle: _t(14.5),
                            ),
                            child: const Text('Skip'),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _pages,
                        itemCount: _slides.length,
                        onPageChanged: (i) => setState(() => _page = i),
                        itemBuilder: (_, i) =>
                            _SlideView(slide: _slides[i], first: i == 0),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
                      child: Column(
                        children: [
                          _Dots(count: _slides.length, index: _page),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: FilledButton(
                              onPressed: _next,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppColors.blue,
                                shape: const StadiumBorder(),
                                textStyle: _t(16, weight: FontWeight.w600),
                              ),
                              child: Text(last ? 'Join now' : 'Next'),
                            ),
                          ),
                        ],
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

/// One slide. Scrolls if the phone is small.
class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide, required this.first});

  final _Slide slide;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, first ? 28 : 8, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _glassIcon,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(slide.icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 16),
          Text(
            slide.title,
            style: _t(first ? 30 : 26, weight: FontWeight.w600, height: 1.15),
          ),
          if (slide.text.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(slide.text, style: _t(15, color: _dim, height: 1.5)),
          ],
          const SizedBox(height: 20),
          slide.body,
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == index ? Colors.white : const Color(0x59FFFFFF),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

/// A see-through card on the blue background.
class _Glass extends StatelessWidget {
  const _Glass({required this.child, this.strong = false});

  final Widget child;

  /// A brighter border (the selected choice).
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: _glass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: strong ? Colors.white : _glassLine,
          width: strong ? 1.5 : 1,
        ),
      ),
      child: child,
    );
  }
}

/// Icon + title + one line, in a glass card.
class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.sub});

  final IconData icon;
  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return _Glass(
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _glassIcon,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _t(14.5, weight: FontWeight.w500)),
                const SizedBox(height: 1),
                Text(sub, style: _t(12.5, color: _faint, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Slide 1: the three things you can do.
class _Features extends StatelessWidget {
  const _Features();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _Row(
          icon: Icons.lightbulb_outline,
          title: 'Suggestion Box',
          sub:
              'Share an idea or a problem. Admin replies, and you can keep '
              'talking back and forth until it’s solved.',
        ),
        _Row(
          icon: Icons.favorite_border_rounded,
          title: 'Weekly Pulse',
          sub:
              'Once a week, tell us how your week went: Great, Good, Okay or '
              'Difficult. It takes 10 seconds.',
        ),
        _Row(
          icon: Icons.campaign_outlined,
          title: 'Broadcast',
          sub:
              'Admin shares what’s done and what’s coming next. You can '
              'comment and discuss it together.',
        ),
      ],
    );
  }
}

/// Slide 2: what admin sees, anonymous and with a name.
class _AdminSees extends StatelessWidget {
  const _AdminSees();

  @override
  Widget build(BuildContext context) {
    Widget card({
      required bool anonymous,
      required String label,
      required String who,
    }) => _Glass(
      strong: anonymous,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _t(12, color: _faint)),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _glassIcon,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: anonymous
                    ? const Icon(
                        Icons.lock_outline_rounded,
                        size: 15,
                        color: Colors.white,
                      )
                    : Text('R', style: _t(13, weight: FontWeight.w500)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(who, style: _t(13.5, weight: FontWeight.w500)),
                    Text(
                      'The pantry gets messy by lunchtime. Can we clean it twice a day?',
                      style: _t(12.5, color: _faint),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return Column(
      children: [
        card(
          anonymous: true,
          label: 'What admin sees · Anonymous',
          who: 'Name hidden',
        ),
        card(
          anonymous: false,
          label: 'What admin sees · With my name',
          who: 'Ravi Kumar (chose to show name)',        ),
      ],
    );
  }
}

/// Slide 3: three short promises.
class _Privacy extends StatelessWidget {
  const _Privacy();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _Row(
          icon: Icons.visibility_off_outlined,
          title: 'Nobody knows it’s you',
          sub: 'No name, no email, no phone number. Not even admin can tell who wrote it.',
        ),
        _Row(
          icon: Icons.enhanced_encryption_outlined,
          title: 'Kept safe',
          sub: 'Your messages are locked when saved, so they stay private.',
        ),
        _Row(
          icon: Icons.person_outline,
          title: 'Your name, only if you want',
          sub: 'Choose “With my name” when you send. It shows only on that one message.',
        ),
      ],
    );
  }
}

/// Slide 4: the three steps, then reinstall / new phone / lost.
class _JoinSteps extends StatelessWidget {
  const _JoinSteps();

  @override
  Widget build(BuildContext context) {
    Widget step(int n, String title, String sub) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$n',
              style: _t(13, weight: FontWeight.w600, color: AppColors.blue),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _t(15, weight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(sub, style: _t(13, color: _faint, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
    Widget tip(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: _t(13, color: _faint, height: 1.4)),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        step(
          1,
          'Enter the entry code',
          'It’s like a gate pass. Your team will share this code with you. It’s the same for everyone, '
              'so the app knows you work at Haystek, but not who you are.',
        ),
        step(
          2,
          'Save your personal code',
          'The app gives you your own code. Keep it safe. You need it only '
              'if you change your phone.',
        ),
        step(
          3,
          'You’re in!',
          'No sign-up, no password. Next time, the app opens straight away.',
        ),
        const SizedBox(height: 4),
        _Glass(
          child: Column(
            children: [
              tip(
                Icons.refresh_rounded,
                'Reinstalled the app? It finds your account by itself.',
              ),
              tip(
                Icons.phone_iphone_rounded,
                'New phone? Tap “I have my personal code” and enter it.',
              ),
              tip(
                Icons.warning_amber_rounded,
                'Lost your phone and your code? Join again with the entry code. '
                    'You’ll start fresh, and your old messages stay with admin.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
