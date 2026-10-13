import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Shared by the employee home and the management dashboard.

/// A heartbeat (ECG) line that ends in a heart.
/// - faint line: the whole week, from Monday to the opening,
/// - bright line: the part that has passed,
/// - glowing dot: now. A ring grows out of it and fades, again and again,
/// - heart at the end: the moment the Weekly Pulse opens. It beats softly.
class PulseLine extends StatefulWidget {
  const PulseLine({
    required this.progress,
    this.heartColor = Colors.white,
    this.showDot = true,
    this.lineColor = const Color(0xFF7FA2FF),
    this.moving = false,
  });

  /// 0.0 = Monday, 1.0 = the moment it opens.
  final double progress;

  /// White while waiting, pink once it is open.
  final Color heartColor;

  /// The glowing "now" dot. Hidden once the line has reached the heart.
  final bool showDot;

  /// The colour of the part that has passed. Faint once the week is closed.
  final Color lineColor;

  /// Like a heart monitor: a bright part runs along the line again and
  /// again, and the heart beats each time it arrives. Used on sign in.
  final bool moving;

  @override
  State<PulseLine> createState() => _PulseLineState();
}

class _PulseLineState extends State<PulseLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.moving ? 2400 : 1500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // No movement for people who turned animations off.
    if (MediaQuery.of(context).disableAnimations) {
      _beat.stop();
      _beat.value = 0.3;
    } else if (!_beat.isAnimating) {
      _beat.repeat();
    }
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: AnimatedBuilder(
        animation: _beat,
        builder: (context, _) {
          final t = _beat.value;
          // Two quick beats, then rest: like a real heart.
          double bump(double at) {
            final x = (t - at).abs() / 0.08;
            return x >= 1 ? 0 : 1 - x;
          }

          // Moving line: the heart beats as the bright part reaches it.
          final heartScale = widget.moving
              ? 1 + 0.20 * bump(0.92) + 0.10 * bump(0.06)
              : 1 + 0.18 * bump(0.10) + 0.10 * bump(0.28);
          return Stack(
            children: [
              Positioned.fill(
                right: 34,
                child: CustomPaint(
                  painter: _PulseLinePainter(
                    progress: widget.progress,
                    beat: t,
                    showDot: widget.showDot,
                    lineColor: widget.lineColor,
                    moving: widget.moving,
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Transform.scale(
                    scale: heartScale,
                    child: Icon(
                      Icons.favorite,
                      color: widget.heartColor,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PulseLinePainter extends CustomPainter {
  _PulseLinePainter({
    required this.progress,
    required this.beat,
    this.showDot = true,
    this.lineColor = const Color(0xFF7FA2FF),
    this.moving = false,
  });

  final double progress;
  final double beat;
  final bool showDot;
  final Color lineColor;
  final bool moving;

  static const Color _glow = Color(0xFF7FA2FF);

  /// The points of the heartbeat line, from left to right.
  List<Offset> _points(Size size) {
    final w = size.width;
    final mid = size.height / 2;
    final h = size.height;
    final pts = <Offset>[Offset(0, mid)];
    // Three beats along the line.
    for (final at in [0.18, 0.50, 0.82]) {
      pts.addAll([
        Offset(w * (at - 0.05), mid),
        Offset(w * (at - 0.03), mid - h * 0.12),
        Offset(w * (at - 0.015), mid),
        Offset(w * at, mid - h * 0.42),
        Offset(w * (at + 0.02), mid + h * 0.36),
        Offset(w * (at + 0.035), mid),
        Offset(w * (at + 0.06), mid - h * 0.10),
        Offset(w * (at + 0.08), mid),
      ]);
    }
    pts.add(Offset(w, mid));
    return pts;
  }

  /// The height of the line at [x], so the dot sits on the line.
  double _yAt(List<Offset> pts, double x) {
    for (var i = 1; i < pts.length; i++) {
      if (x <= pts[i].dx) {
        final a = pts[i - 1];
        final b = pts[i];
        final f = b.dx == a.dx ? 0.0 : (x - a.dx) / (b.dx - a.dx);
        return a.dy + (b.dy - a.dy) * f;
      }
    }
    return pts.last.dy;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pts = _points(size);
    final path = Path()..addPolygon(pts, false);
    final x = size.width * progress;

    // The whole week: faint.
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    // Heart monitor: a bright part runs from left to right, with a
    // glowing dot at its front.
    if (moving) {
      final head = size.width * beat;
      const tail = 120.0;
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(head - tail, 0, tail, size.height));
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            colors: [lineColor.withValues(alpha: 0), lineColor],
          ).createShader(Rect.fromLTWH(head - tail, 0, tail, size.height))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.restore();
      final dot = Offset(head, _yAt(pts, head));
      canvas.drawCircle(
        dot,
        7,
        Paint()..color = lineColor.withValues(alpha: 0.35),
      );
      canvas.drawCircle(dot, 3.5, Paint()..color = Colors.white);
      return;
    }

    // The part that has passed: bright.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, x, size.height));
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();

    if (!showDot) return;

    // Now: a dot on the line, with a ring that grows and fades.
    final dot = Offset(x, _yAt(pts, x));
    final e = Curves.easeOut.transform(beat);
    canvas.drawCircle(
      dot,
      5 + 12 * e,
      Paint()
        ..color = _glow.withValues(alpha: 0.6 * (1 - e))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(dot, 5.5, Paint()..color = _glow);
    canvas.drawCircle(dot, 2.2, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_PulseLinePainter old) =>
      old.beat != beat || old.progress != progress || old.moving != moving;
}

/// A live countdown: "2d 6h 14m", "6h 20m 15s" or "4m 09s".
/// It ticks every second by itself, without redrawing the whole card,
/// and tells the card when it reaches zero.
class LiveCountdown extends StatefulWidget {
  const LiveCountdown({
    required this.to,
    required this.onDone,
    this.prefix = '',
    this.suffix = '',
    this.color = Colors.white,
    this.size = 14,
  });

  final DateTime to;
  final VoidCallback onDone;

  /// Added before the time, for example "Opens in ".
  final String prefix;

  /// Added after the time, for example " left".
  final String suffix;
  final Color color;
  final double size;

  @override
  State<LiveCountdown> createState() => _LiveCountdownState();
}

class _LiveCountdownState extends State<LiveCountdown> {
  Timer? _tick;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!_done && !DateTime.now().isBefore(widget.to)) {
        _done = true;
        _tick?.cancel();
        widget.onDone();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String _text(Duration d) {
    if (d.isNegative) d = Duration.zero;
    String two(int n) => n.toString().padLeft(2, '0');
    final days = d.inDays;
    final h = d.inHours % 24;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (days > 0) return '${days}d ${h}h ${m}m';
    if (h > 0) return '${h}h ${two(m)}m ${two(s)}s';
    return '${m}m ${two(s)}s';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      '${widget.prefix}${_text(widget.to.difference(DateTime.now()))}'
          '${widget.suffix}',
      maxLines: 1,
      // Same-width digits, so the text does not jump every second.
      style: GoogleFonts.inter(
        fontSize: widget.size,
        fontWeight: FontWeight.w600,
        color: widget.color,
      )
          .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}