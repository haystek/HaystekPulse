import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/pulse_rating.dart';
import '../theme/app_theme.dart';

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

const Color _soft = Color(0xFF8E97AB);
const Color _line = Color(0xFFE3E8F1);
const Color _panel = Color(0xFFF6F8FB);
const Color _sky1 = Color(0xFF0B1B4D);
const Color _sky2 = Color(0xFF14328F);
const Color _light = Color(0xFFC9D6FF);

/// Shows the intro once (the first time the app is opened on this phone),
/// then [child] (the login screen).
class IntroGate extends StatefulWidget {
  const IntroGate({super.key, required this.child});

  final Widget child;

  @override
  State<IntroGate> createState() => _IntroGateState();
}

class _IntroGateState extends State<IntroGate> {
  static const _store = FlutterSecureStorage();
  static const _key = 'intro_seen_v1';

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
      return const Scaffold(backgroundColor: Colors.white);
    }
    return seen ? widget.child : IntroScreen(onDone: _done);
  }
}

/// One slide: the icon in the night-sky top, the title and short lines
/// on the white sheet, and a small picture of how it looks in the app.
class _Slide {
  const _Slide({
    required this.icon,
    required this.title,
    required this.lines,
    required this.preview,
  });

  final IconData icon;
  final String title;
  final List<String> lines;
  final Widget preview;
}

final List<_Slide> _slides = [
  const _Slide(
    icon: Icons.favorite_border_rounded,
    title: 'Welcome to Haystek Pulse',
    lines: [
      'Share ideas, problems and how your week went.',
      'Admin reads everything and replies to you here.',
    ],
    preview: _WelcomePreview(),
  ),
  const _Slide(
    icon: Icons.lightbulb_outline,
    title: 'Suggestion Box',
    lines: [
      'Ideas, problems or concerns. Open every day, any time.',
      'Admin replies and updates the status. You can reply back, like a chat.',
    ],
    preview: _ChatPreview(),
  ),
  const _Slide(
    icon: Icons.monitor_heart_outlined,
    title: 'Weekly Pulse',
    lines: ['Once a week, tap how your week was.'],
    preview: _PulsePreview(),
  ),
  const _Slide(
    icon: Icons.campaign_outlined,
    title: 'Broadcast',
    lines: [
      'Admin shares updates with everyone, like what changed after a '
          'suggestion.',
      'You get a notification and can discuss it, with or without your name.',
    ],
    preview: _BroadcastPreview(),
  ),
  const _Slide(
    icon: Icons.lock_outline_rounded,
    title: 'Your name, your choice',
    lines: ['Every time you write, you decide if admin sees your name.'],
    preview: _NamePreview(),
  ),
  const _Slide(
    icon: Icons.shield_outlined,
    title: 'Your private locker',
    lines: [
      'The list of what you sent is kept in a locker. Only your password '
          'opens it.',
    ],
    preview: _LockerPreview(),
  ),
  const _Slide(
    icon: Icons.phone_iphone_rounded,
    title: 'New phone? Forgot password?',
    lines: ['Your locker is never lost.'],
    preview: _RecoverPreview(),
  ),
];

/// The intro: night-sky top (same as sign in), white sheet below, dots and
/// the blue button at the bottom. Swipe or tap Next. Skip at the top.
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
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _slides.length - 1;
    final pad = MediaQuery.paddingOf(context);
    final slide = _slides[_page];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The night-sky top stays still. Only its icon changes, with a
            // soft fade, so the whole screen doesn't slide.
            Container(
              padding: EdgeInsets.fromLTRB(20, pad.top + 8, 12, 56),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_sky1, _sky2, AppColors.blue],
                  stops: [0, 0.55, 1],
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text('${_page + 1} of ${_slides.length}',
                          style: _t(13, color: _light)),
                      const Spacer(),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: last ? 0 : 1,
                        child: TextButton(
                          onPressed: last ? null : widget.onDone,
                          style: TextButton.styleFrom(foregroundColor: _light),
                          child: Text('Skip', style: _t(14.5, color: _light)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: ScaleTransition(
                          scale: Tween(begin: 0.85, end: 1.0).animate(anim),
                          child: child,
                        ),
                      ),
                      child: Icon(
                        slide.icon,
                        key: ValueKey(_page),
                        size: 34,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // The white sheet, pulled up over the dark top. Only the text
            // and the picture inside it move when swiping.
            Expanded(
              child: Transform.translate(
                offset: const Offset(0, -28),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: _slides.length,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) => _SlideBody(
                      slide: _slides[i],
                      controller: _pages,
                      index: i,
                    ),
                  ),
                ),
              ),
            ),
            // Dots and the button stay in place.
            Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 16 + pad.bottom),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _slides.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _page ? 20 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i == _page ? AppColors.blue : const Color(0xFFD5DCE8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _GradientButton(
                    label: last ? 'Get started' : 'Next',
                    onTap: _next,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The text and picture of one slide. While swiping, it slides with the
/// finger and fades a little at the edges.
///
/// When a slide is taller than the screen, a soft white fade and a small
/// "Scroll for more" chip show at the bottom, until the end is reached.
class _SlideBody extends StatefulWidget {
  const _SlideBody({
    required this.slide,
    required this.controller,
    required this.index,
  });

  final _Slide slide;
  final PageController controller;
  final int index;

  @override
  State<_SlideBody> createState() => _SlideBodyState();
}

class _SlideBodyState extends State<_SlideBody> {
  final _scroll = ScrollController();

  /// True while there is more below.
  bool _more = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _check() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final more = p.maxScrollExtent > 8 && p.pixels < p.maxScrollExtent - 8;
    if (more != _more) setState(() => _more = more);
  }

  void _scrollDown() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    _scroll.animateTo(
      (p.pixels + p.viewportDimension * 0.8).clamp(0.0, p.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final slide = widget.slide;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        var delta = 0.0;
        final c = widget.controller;
        if (c.hasClients && c.position.haveDimensions) {
          delta = (c.page ?? widget.index.toDouble()) - widget.index;
        }
        // Normal side-by-side swipe (no overlap), with a light fade at
        // the edges so it feels soft.
        final d = delta.clamp(-1.0, 1.0).abs();
        return Opacity(opacity: (1 - d * 0.5).clamp(0.0, 1.0), child: child);
      },
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          // Size changed (for example the screen turned): check after
          // this frame, not during layout.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _check();
          });
          return false;
        },
        child: Stack(
          children: [
            SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        slide.title,
                        style: _t(23, weight: FontWeight.w500, letterSpacing: -0.4),
                      ),
                      for (final line in slide.lines) ...[
                        const SizedBox(height: 8),
                        Text(line, style: _t(15, color: AppColors.muted, height: 1.5)),
                      ],
                      const SizedBox(height: 18),
                      slide.preview,
                    ],
                  ),
                ),
              ),
            ),
            // More below: white fade + "Scroll for more" chip.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: !_more,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _more ? 1 : 0,
                  child: Container(
                    height: 70,
                    alignment: Alignment.bottomCenter,
                    padding: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white,
                        ],
                      ),
                    ),
                    child: Material(
                      color: AppColors.blueTint,
                      shape: const StadiumBorder(),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: _scrollDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Scroll for more',
                                  style: _t(12.5, color: AppColors.blue)),
                              const SizedBox(width: 4),
                              const Icon(Icons.keyboard_arrow_down_rounded,
                                  size: 18, color: AppColors.blue),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Previews: small pictures of the real app screens
// ---------------------------------------------------------------------

/// A light grey card with a small caps label on top.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label.toUpperCase(),
            style: _t(11, weight: FontWeight.w500, color: _soft, letterSpacing: 1.1),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _WelcomePreview extends StatelessWidget {
  const _WelcomePreview();

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String title, String sub) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.blueTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.blue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _t(15, weight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(sub, style: _t(13, color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
    return Column(
      children: [
        row(Icons.lightbulb_outline, 'Suggestion Box', 'Any day, any time'),
        row(Icons.monitor_heart_outlined, 'Weekly Pulse', 'Once a week, 10 seconds'),
        row(Icons.campaign_outlined, 'Broadcast', 'Updates from admin for everyone'),
      ],
    );
  }
}

/// You → status → admin → you, like the real chat.
class _ChatPreview extends StatelessWidget {
  const _ChatPreview();

  @override
  Widget build(BuildContext context) {
    Widget mine(String text) => Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
          color: AppColors.blue,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(text, style: _t(13.5, color: Colors.white)),
      ),
    );
    return _PreviewCard(
      label: 'How it looks',
      child: Column(
        children: [
          mine('The pantry is not clean.'),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE6F6F5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('● Status changed to Planned',
                style: _t(11.5, color: const Color(0xFF0F766E))),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Admin', style: _t(11.5, weight: FontWeight.w500, color: AppColors.blue)),
                  const SizedBox(height: 2),
                  Text('Thanks, we’ll fix it this week.', style: _t(13.5)),
                ],
              ),
            ),
          ),
          mine('Great, thank you!'),
        ],
      ),
    );
  }
}

/// The four answers, and what admin sees for each.
class _PulsePreview extends StatelessWidget {
  const _PulsePreview();

  @override
  Widget build(BuildContext context) {
    Widget tile(String r) {
      final c = PulseRating.color(r);
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _line, width: 1.2),
          ),
          child: Column(
            children: [
              Icon(PulseRating.icon(r), color: c, size: 24),
              const SizedBox(height: 4),
              Text(PulseRating.label(r), style: _t(12, color: AppColors.ink)),
            ],
          ),
        ),
      );
    }

    Widget rule(Color dot, String title, String text) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$title  ',
                    style: _t(14, weight: FontWeight.w500),
                  ),
                  TextSpan(text: text),
                ],
              ),
              style: _t(14, color: const Color(0xFF344054), height: 1.45),
            ),
          ),
        ],
      ),
    );

    final all = PulseRating.all;
    return _PreviewCard(
      label: 'You tap one',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var i = 0; i < all.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                tile(all[i]),
              ],
            ],
          ),
          rule(
            AppColors.blue,
            'Great or Good:',
            'admin sees only the count, like “Great 5 · Good 3”. Not who.',
          ),
          rule(
            const Color(0xFFD9961F),
            'Okay or Difficult:',
            'tell what could be better, with or without your name. It helps '
                'admin fix things.',
          ),
        ],
      ),
    );
  }
}

/// What admin sees with the name hidden, and with it shown.
class _NamePreview extends StatelessWidget {
  const _NamePreview();

  @override
  Widget build(BuildContext context) {
    Widget card({
      required bool hidden,
      required String title,
      required String sub,
    }) =>
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hidden ? AppColors.blue : _line,
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: _t(13, weight: FontWeight.w500,
                  color: hidden ? AppColors.blue : AppColors.ink)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: hidden ? _panel : AppColors.blueTint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: hidden
                        ? const Icon(Icons.lock_outline_rounded, size: 15, color: _soft)
                        : Text('S', style: _t(13, color: AppColors.blue)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(hidden ? 'Name hidden' : 'Shiva Tumma',
                            style: _t(13.5, weight: FontWeight.w500)),
                        Text('The pantry is not clean.',
                            style: _t(13, color: AppColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(sub, style: _t(12.5, color: _soft, height: 1.4)),
            ],
          ),
        );

    return Column(
      children: [
        card(
          hidden: true,
          title: '🔒 Hide my name',
          sub: 'Admin reads it and can reply, but nobody can find out it '
              'was you.',
        ),
        card(
          hidden: false,
          title: '👤 Show my name',
          sub: 'Admin sees your name with the message.',
        ),
      ],
    );
  }
}

/// One simple picture (password → key → locker), the bank-locker idea,
/// three promises, and what Firebase really holds.
class _LockerPreview extends StatelessWidget {
  const _LockerPreview();

  @override
  Widget build(BuildContext context) {
    Widget node(IconData icon, String label, {bool locked = false}) => Column(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: locked ? AppColors.blue : AppColors.blueTint,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: locked ? Colors.white : AppColors.blue, size: 25),
        ),
        const SizedBox(height: 6),
        Text(label, textAlign: TextAlign.center, style: _t(12, color: AppColors.muted)),
      ],
    );
    Widget arrow() => const Padding(
      padding: EdgeInsets.only(bottom: 20),
      child: Icon(Icons.arrow_forward_rounded, color: _soft, size: 18),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PreviewCard(
          label: 'Like a bank locker',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  node(Icons.password_rounded, 'Your\npassword'),
                  arrow(),
                  node(Icons.vpn_key_outlined, 'Your\nkey'),
                  arrow(),
                  node(Icons.lock_rounded, 'Your\nlocker', locked: true),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Firebase keeps the locker safe, like a bank. But only your '
                    'key opens it, and only your password makes your key.',
                textAlign: TextAlign.center,
                style: _t(13.5, color: const Color(0xFF344054), height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const _Promise(
          icon: Icons.phonelink_lock_outlined,
          title: 'Your key is made on your phone',
          text: 'From your password, every time you sign in. It is never '
              'sent or saved anywhere.',
        ),
        const _Promise(
          icon: Icons.visibility_off_outlined,
          title: 'Nobody else can open your locker',
          text: 'We never see or store your password, so admin and the '
              'developer can’t make your key.',
        ),
        const _Promise(
          icon: Icons.verified_user_outlined,
          title: 'Same idea as WhatsApp backups',
          text: 'Also used by Apple iCloud and password apps like 1Password.',
        ),
        const SizedBox(height: 6),
        // What admin and the developer see in Firebase.
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _line, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('What admin and the developer see',
                  style: _t(13, weight: FontWeight.w500)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'locker:  "Q7v#k2Lp9xZr4…"',
                  style: GoogleFonts.robotoMono(fontSize: 12.5, color: const Color(0xFF5F6A84)),
                ),
              ),
              const SizedBox(height: 6),
              Text('Only scrambled text. They can’t tell which posts are yours.',
                  style: _t(12.5, color: _soft, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}

/// One promise: a round icon, a short bold line and one plain sentence.
class _Promise extends StatelessWidget {
  const _Promise({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: Color(0xFFE8F7EE),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 17, color: const Color(0xFF15803D)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _t(14.5, weight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(text, style: _t(13.5, color: AppColors.muted, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// New phone and forgot password, each in one card, and the two tips.
class _RecoverPreview extends StatelessWidget {
  const _RecoverPreview();

  @override
  Widget build(BuildContext context) {
    Widget card(IconData icon, String title, List<String> steps) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.blueTint,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 19, color: AppColors.blue),
              ),
              const SizedBox(width: 10),
              Text(title, style: _t(15, weight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: Text('${i + 1}.', style: _t(13.5, color: AppColors.blue)),
                  ),
                  Expanded(
                    child: Text(steps[i],
                        style: _t(13.5, color: const Color(0xFF344054), height: 1.45)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card(Icons.phone_iphone_rounded, 'New phone', const [
          'Sign in with the same email and password.',
          'Your password makes the same key again.',
          'Your locker opens and everything is back.',
        ]),
        card(Icons.key_outlined, 'Forgot password', const [
          'Tap “Reset password” and set a new one.',
          'Enter your backup code (you get it at sign-up).',
          'Your locker opens and is locked again with the new password.',
        ]),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF6E5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            '• Pick a password only you know.\n'
                '• Save your backup code somewhere safe. Without it, a forgotten '
                'password means your old posts can’t be shown to you again '
                '(admin still has them).',
            style: _t(13, color: const Color(0xFF8A5A00), height: 1.55),
          ),
        ),
      ],
    );
  }
}

/// A broadcast card and two comments, like the real Broadcast screen.
class _BroadcastPreview extends StatelessWidget {
  const _BroadcastPreview();

  @override
  Widget build(BuildContext context) {
    Widget bubble(String who, String text, {bool admin = false}) => Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: admin ? AppColors.blueTint : Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(who, style: _t(11.5, weight: FontWeight.w500,
                color: admin ? AppColors.blue : const Color(0xFF475467))),
            const SizedBox(height: 2),
            Text(text, style: _t(13.5)),
          ],
        ),
      ),
    );

    return _PreviewCard(
      label: 'How it looks',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _line, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Admin', style: _t(12, color: AppColors.blue)),
                    const TextSpan(text: '  ·  Today'),
                  ]),
                  style: _t(12, color: _soft),
                ),
                const SizedBox(height: 4),
                Text('Air dryer added on the 5th floor 🎉',
                    style: _t(14.5, weight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text('💬 6 comments', style: _t(12.5, color: _soft)),
              ],
            ),
          ),
          bubble('🔒 Name hidden', 'Can we get one on the 3rd floor too?'),
          bubble('Admin', 'Yes, next week.', admin: true),
        ],
      ),
    );
  }
}

/// The big button in the same navy-to-blue as the sign-in button.
class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [_sky1, _sky2, AppColors.blue],
          stops: [0, 0.5, 1],
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 54,
            child: Center(
              child: Text(
                label,
                style: _t(16, weight: FontWeight.w500, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}