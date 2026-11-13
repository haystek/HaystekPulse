import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/fresh_install.dart';

const Color _sky1 = Color(0xFF0B1B4D);

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
  static const _key = 'intro_seen_v4';

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
      seen = !FreshInstall.showAgain(_key) &&
          await _store.read(key: _key) == '1';
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

// ---------------------------------------------------------------------
// Intro: 4 animated slides (welcome, what you can do, privacy, join).
// ---------------------------------------------------------------------

const Color _iNavy = Color(0xFF1B3590);
const Color _iInk = Color(0xFF111827);
const Color _iSoft = Color(0xFF6B7280);
const Color _iFaint = Color(0xFF9CA3AF);
const Color _iPale = Color(0xFFC9D6FF);
const LinearGradient _iGrad = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF142261), Color(0xFF1B3590), Color(0xFF2A57D9)],
  stops: [0, 0.55, 1],
);

/// Part of [a] between [from] and [to] (0–1), with a curve.
Animation<double> _iPart(
  Animation<double> a,
  double from,
  double to, [
  Curve curve = Curves.easeOutCubic,
]) => CurvedAnimation(
  parent: a,
  curve: Interval(from, to, curve: curve),
);

/// First open: 4 slides that animate in. Swipe or tap Next; Skip on top.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen>
    with TickerProviderStateMixin {
  static const _count = 4;
  final _page = PageController();
  int _index = 0;

  /// Plays once each time a slide is shown.
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..forward();

  /// Slow up-and-down for the floating cards.
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat(reverse: true);

  /// The pulse line keeps beating (a bright wave runs along it).
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  bool get _last => _index == _count - 1;

  @override
  void dispose() {
    _page.dispose();
    _enter.dispose();
    _float.dispose();
    _beat.dispose();
    super.dispose();
  }

  void _next() {
    if (_last) {
      widget.onDone();
      return;
    }
    _page.nextPage(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _slide(int i, Animation<double> a) {
    switch (i) {
      case 0:
        return _IPage(
          a: a,
          hero: _HeroWelcome(a: a, float: _float, beat: _beat),
          title: 'Your voice at Haystek, heard.',
          sub:
              'Share ideas, raise problems and tell us how your week '
              'went. Admin reads every message and replies.',
        );
      case 1:
        return _IPage(
          a: a,
          hero: _HeroTiles(a: a, float: _float),
          title: 'Three simple things',
          body: const [
            _IItem(
              icon: Icons.lightbulb_outline_rounded,
              color: Color(0xFFB7791F),
              bg: Color(0xFFFEF3C7),
              title: 'Suggestion Box',
              text: 'Ideas or problems, any day. Admin replies.',
            ),
            _IItem(
              icon: Icons.monitor_heart_outlined,
              color: _iNavy,
              bg: Color(0xFFEAF0FF),
              title: 'Weekly Pulse',
              text: 'Once a week, tell us how your week went. Takes 5 seconds.',
            ),
            _IItem(
              icon: Icons.campaign_outlined,
              color: Color(0xFFC2410C),
              bg: Color(0xFFFFEDD5),
              title: 'Broadcast',
              text: 'News and updates for everyone.',
            ),
          ],
        );
      case 2:
        return _IPage(
          a: a,
          hero: _HeroPrivate(a: a, float: _float),
          title: 'Anonymous by default',
          body: const [
            _IItem(
              icon: Icons.lock_outline_rounded,
              color: _iNavy,
              bg: Color(0xFFEAF0FF),
              title: 'Nobody knows it’s you',
              text: 'Not admin, not the developer.',
              size: 36,
            ),
            _IItem(
              icon: Icons.shield_outlined,
              color: _iNavy,
              bg: Color(0xFFEAF0FF),
              title: 'Stored encrypted',
              text: 'Your messages are encrypted in the database.',
              size: 36,
            ),
            _IItem(
              icon: Icons.vpn_key_outlined,
              color: _iNavy,
              bg: Color(0xFFEAF0FF),
              title: 'Your name only if you choose',
              text: 'Pick “With my name” for one message.',
              size: 36,
            ),
          ],
        );
      default:
        return _IPage(
          a: a,
          hero: _HeroJoin(a: a),
          title: 'Join in 10 seconds',
          body: const [
            _IStep(
              n: 1,
              title: 'Enter your entry code',
              text:
                  'You will find it on Zoho. Only Haystek staff can see it, '
                  'so outsiders cannot join.',
            ),
            _IStep(
              n: 2,
              title: 'Save your personal code',
              text:
                  'The app gives you this code after you join. Keep it safe. You need it only if you move to a new phone.',
            ),
            _IStep(
              n: 3,
              title: 'You are in',
              text: 'No email and no password. This phone is your account.',
              last: true,
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _page,
                    itemCount: _count,
                    onPageChanged: (i) {
                      setState(() => _index = i);
                      _enter.forward(from: 0);
                    },
                    itemBuilder: (_, i) => _slide(
                      i,
                      i == _index ? _enter : kAlwaysDismissedAnimation,
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
                    child: Row(
                      children: [
                        _IDots(index: _index, count: _count),
                        const Spacer(),
                        _INext(last: _last, onTap: _next),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (!_last)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 10,
                right: 16,
                child: _IPill(text: 'Skip', onTap: widget.onDone),
              ),
          ],
        ),
      ),
    );
  }
}

/// One slide: navy picture on top, title, short text and items below.
class _IPage extends StatelessWidget {
  const _IPage({
    required this.a,
    required this.hero,
    required this.title,
    this.sub,
    this.body = const [],
  });

  final Animation<double> a;
  final Widget hero;
  final String title;
  final String? sub;
  final List<Widget> body;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: (h * 0.46).clamp(300.0, 420.0),
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(
            gradient: _iGrad,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
          ),
          child: Stack(
            children: [
              const Positioned(top: -90, right: -140, child: _IRing(360)),
              const Positioned(bottom: -110, left: -80, child: _IRing(240)),
              Positioned.fill(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Center(child: hero),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(28, 26, 28, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IRise(
                  a: a,
                  from: 0.25,
                  to: 0.6,
                  child: Text(
                    title,
                    style: t.headlineSmall?.copyWith(
                      fontSize: 26,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: _iInk,
                    ),
                  ),
                ),
                if (sub != null) ...[
                  const SizedBox(height: 10),
                  _IRise(
                    a: a,
                    from: 0.35,
                    to: 0.7,
                    child: Text(
                      sub!,
                      style: t.bodyLarge?.copyWith(
                        fontSize: 15,
                        height: 1.55,
                        color: _iSoft,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                for (var i = 0; i < body.length; i++)
                  _IRise(
                    a: a,
                    from: 0.45 + i * 0.1,
                    to: 0.8 + i * 0.07,
                    child: body[i],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Fades in and slides up while [a] goes from [from] to [to].
class _IRise extends StatelessWidget {
  const _IRise({
    required this.a,
    required this.from,
    required this.to,
    required this.child,
    this.dy = 18,
  });

  final Animation<double> a;
  final double from;
  final double to;
  final double dy;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = _iPart(a, from, to);
    return AnimatedBuilder(
      animation: p,
      child: child,
      builder: (_, c) => Opacity(
        opacity: p.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, dy * (1 - p.value)),
          child: c,
        ),
      ),
    );
  }
}

/// Fades in and slides in from the side ([dx] < 0: from the left).
class _ISide extends StatelessWidget {
  const _ISide({
    required this.a,
    required this.from,
    required this.to,
    required this.dx,
    required this.child,
  });

  final Animation<double> a;
  final double from;
  final double to;
  final double dx;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = _iPart(a, from, to);
    return AnimatedBuilder(
      animation: p,
      child: child,
      builder: (_, c) => Opacity(
        opacity: p.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(dx * (1 - p.value), 0),
          child: c,
        ),
      ),
    );
  }
}

/// Gentle up-and-down (the other way when [flip]).
class _IFloat extends StatelessWidget {
  const _IFloat({
    required this.float,
    required this.child,
    this.flip = false,
    this.amp = 5,
    this.horizontal = false,
  });

  final Animation<double> float;
  final Widget child;
  final bool flip;
  final double amp;

  /// Left/right instead of up/down.
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: float,
      child: child,
      builder: (_, c) {
        final v = Curves.easeInOut.transform(float.value) - 0.5;
        return Transform.translate(
          offset: horizontal
              ? Offset(v * 2 * amp * (flip ? -1 : 1), 0)
              : Offset(0, v * 2 * amp * (flip ? -1 : 1)),
          child: c,
        );
      },
    );
  }
}

class _IRing extends StatelessWidget {
  const _IRing(this.size);

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
    );
  }
}

/// See-through card on the navy picture.
class _IGlass extends StatelessWidget {
  const _IGlass({
    required this.icon,
    required this.iconColor,
    required this.tile,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final Color iconColor;
  final Color tile;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      width: 290,
      padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 24,
            offset: Offset(0, 10),
            spreadRadius: -8,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: tile,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: t.labelLarge?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _iInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: t.bodySmall?.copyWith(
                    fontSize: 12.5,
                    height: 1.4,
                    color: _iSoft,
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

/// Slide 1: the pulse line draws itself, then two cards slide up.
class _HeroWelcome extends StatelessWidget {
  const _HeroWelcome({
    required this.a,
    required this.float,
    required this.beat,
  });

  final Animation<double> a;
  final Animation<double> float;
  final Animation<double> beat;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScaleTransition(
          scale: _iPart(a, 0, 0.35, Curves.easeOutBack),
          child: Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(28),
            ),
            child: CustomPaint(
              painter: _IPulsePainter(_iPart(a, 0.15, 0.6), beat),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _IFloat(
          float: float,
          horizontal: true,
          child: _ISide(
            a: a,
            from: 0.4,
            to: 0.7,
            dx: -70,
            child: const _IGlass(
              icon: Icons.lightbulb_outline_rounded,
              iconColor: Color(0xFFB7791F),
              tile: Color(0xFFFEF3C7),
              title: 'New suggestion',
              text:
                  'Can we keep drinking water bottles filled in the meeting rooms?',
            ),
          ),
        ),
        const SizedBox(height: 12),
        _IFloat(
          float: float,
          flip: true,
          horizontal: true,
          child: Padding(
            padding: const EdgeInsets.only(left: 32),
            child: _ISide(
              a: a,
              from: 0.55,
              to: 0.85,
              dx: 70,
              child: const _IGlass(
                icon: Icons.shield_outlined,
                iconColor: _iNavy,
                tile: Color(0xFFEAF0FF),
                title: 'Admin replied',
                text: 'Sure! Housekeeping will refill them every morning.',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The pulse line: drawn in from left to right ([p] 0 → 1), then a
/// bright wave with a glowing dot keeps running along it ([beat]).
class _IPulsePainter extends CustomPainter {
  _IPulsePainter(this.p, this.beat)
    : super(repaint: Listenable.merge([p, beat]));

  final Animation<double> p;
  final Animation<double> beat;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final path = Path()
      ..moveTo(3 * s, 12 * s)
      ..lineTo(7 * s, 12 * s)
      ..lineTo(9 * s, 7 * s)
      ..lineTo(13 * s, 17 * s)
      ..lineTo(15 * s, 12 * s)
      ..lineTo(21 * s, 12 * s);
    final m = path.computeMetrics().first;
    final len = m.length;
    final v = p.value.clamp(0.0, 1.0);
    Paint line(double alpha, double width) => Paint()
      ..color = Colors.white.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // The whole line, soft.
    canvas.drawPath(m.extractPath(0, len * v), line(0.45, 4));

    // The bright wave: while drawing in it follows the pen; after that it
    // runs again and again (with a short pause at the end).
    final head = v < 1 ? v : beat.value * 1.35;
    if (head <= 1.0) {
      final from = (head - 0.35).clamp(0.0, 1.0);
      final to = head.clamp(0.0, 1.0);
      canvas.drawPath(m.extractPath(len * from, len * to), line(1, 4));
      final tip = m.getTangentForOffset(len * to);
      if (tip != null) {
        canvas.drawCircle(
          tip.position,
          7,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.55)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
        canvas.drawCircle(tip.position, 3.2, Paint()..color = Colors.white);
      }
    }
  }

  @override
  bool shouldRepaint(_IPulsePainter old) => old.p != p || old.beat != beat;
}

/// Slide 2: three tiles pop in one by one and float.
class _HeroTiles extends StatelessWidget {
  const _HeroTiles({required this.a, required this.float});

  final Animation<double> a;
  final Animation<double> float;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const tiles = [
      (Icons.lightbulb_outline_rounded, Color(0xFFB7791F), 'Suggest'),
      (Icons.monitor_heart_outlined, _iNavy, 'Pulse'),
      (Icons.campaign_outlined, Color(0xFFC2410C), 'Updates'),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Padding(
            padding: EdgeInsets.only(top: i == 1 ? 0 : 26),
            child: _IFloat(
              float: float,
              flip: i == 1,
              child: ScaleTransition(
                scale: _iPart(
                  a,
                  0.05 + i * 0.12,
                  0.45 + i * 0.12,
                  Curves.easeOutBack,
                ),
                child: Container(
                  width: 92,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 24,
                        offset: Offset(0, 10),
                        spreadRadius: -8,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: tiles[i].$2.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(tiles[i].$1, size: 21, color: tiles[i].$2),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        tiles[i].$3,
                        style: t.labelMedium?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _iInk,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Slide 3: "what admin sees" card flips in, then the badge.
class _HeroPrivate extends StatelessWidget {
  const _HeroPrivate({required this.a, required this.float});

  final Animation<double> a;
  final Animation<double> float;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final flip = _iPart(a, 0.1, 0.55);
    final card = Container(
      width: 290,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 40,
            offset: Offset(0, 18),
            spreadRadius: -18,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline_rounded, size: 14, color: _iFaint),
              const SizedBox(width: 6),
              Text(
                'Name hidden',
                style: t.labelLarge?.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _iInk,
                ),
              ),
              const Spacer(),
              Text(
                'Today',
                style: t.bodySmall?.copyWith(fontSize: 12, color: _iFaint),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'The pantry is not clean after lunch.',
            style: t.bodyLarge?.copyWith(
              fontSize: 15,
              height: 1.5,
              color: const Color(0xFF374151),
            ),
          ),
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _IRise(
          a: a,
          from: 0,
          to: 0.3,
          dy: 8,
          child: Text(
            'WHAT ADMIN SEES',
            style: t.labelSmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: const Color(0xFFAFC0EA),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _IFloat(
          float: float,
          amp: 4,
          child: AnimatedBuilder(
            animation: flip,
            child: card,
            builder: (_, c) => Opacity(
              opacity: flip.value > 0.02 ? 1 : 0,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0015)
                  ..rotateX((1 - flip.value) * 1.5708),
                child: c,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _IRise(
          a: a,
          from: 0.55,
          to: 0.85,
          child: _IPill(
            icon: Icons.shield_outlined,
            text: 'No name. No ID. Encrypted.',
          ),
        ),
      ],
    );
  }
}

/// Slide 4: the entry code fills in letter by letter.
class _HeroJoin extends StatelessWidget {
  const _HeroJoin({required this.a});

  final Animation<double> a;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final typing = _iPart(a, 0.1, 0.7, Curves.linear);
    const letters = 'HAYS';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: typing,
          builder: (_, __) {
            final done = typing.value * 6;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 6; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Builder(
                    builder: (_) {
                      final lp = (done - i).clamp(0.0, 1.0);
                      final filled = i < 4 && lp > 0;
                      return Transform.scale(
                        scale: filled
                            ? 0.85 + 0.15 * Curves.easeOutBack.transform(lp)
                            : 1,
                        child: Container(
                          width: 42,
                          height: 54,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: filled
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          child: filled
                              ? Text(
                                  letters[i],
                                  style: t.titleLarge?.copyWith(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: _iNavy,
                                  ),
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _IRise(
          a: a,
          from: 0.6,
          to: 0.85,
          dy: 8,
          child: Text(
            'Find your entry code on Zoho',
            style: t.bodyMedium?.copyWith(fontSize: 13, color: _iPale),
          ),
        ),
        const SizedBox(height: 12),
        _IRise(
          a: a,
          from: 0.7,
          to: 0.95,
          dy: 8,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.schedule_rounded, size: 15, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                'Takes about 10 seconds',
                style: t.labelLarge?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Icon tile + title + short line (slides 2 and 3).
class _IItem extends StatelessWidget {
  const _IItem({
    required this.icon,
    required this.color,
    required this.bg,
    required this.title,
    required this.text,
    this.size = 44,
  });

  final IconData icon;
  final Color color;
  final Color bg;
  final String title;
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(size * 0.32),
            ),
            child: Icon(icon, size: size * 0.45, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: t.titleSmall?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _iInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: t.bodyMedium?.copyWith(
                    fontSize: 13,
                    height: 1.45,
                    color: _iSoft,
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

/// Numbered step with a line down to the next one (slide 4).
class _IStep extends StatelessWidget {
  const _IStep({
    required this.n,
    required this.title,
    required this.text,
    this.last = false,
  });

  final int n;
  final String title;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: last ? const Color(0xFFDCFCE7) : _iNavy,
                  shape: BoxShape.circle,
                ),
                child: last
                    ? const Icon(
                        Icons.check_rounded,
                        size: 17,
                        color: Color(0xFF15803D),
                      )
                    : Text(
                        '$n',
                        style: t.labelLarge?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: const Color(0xFFE5E7EB),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 4, bottom: last ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: t.titleSmall?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _iInk,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    text,
                    style: t.bodyMedium?.copyWith(
                      fontSize: 13,
                      height: 1.45,
                      color: _iSoft,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Page dots: the current one stretches.
class _IDots extends StatelessWidget {
  const _IDots({required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            width: i == index ? 22 : 6,
            height: 6,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: i == index ? _iNavy : const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

/// "Next →" / "Join now →".
class _INext extends StatelessWidget {
  const _INext({required this.last, required this.onTap});

  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Material(
      color: _iNavy,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 15, 22, 15),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  last ? 'Join now' : 'Next',
                  key: ValueKey(last),
                  style: t.labelLarge?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small see-through pill on navy (Skip, or a badge with an icon).
class _IPill extends StatelessWidget {
  const _IPill({required this.text, this.icon, this.onTap});

  final String text;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: Colors.white),
                const SizedBox(width: 6),
              ],
              Text(
                text,
                style: t.labelLarge?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
