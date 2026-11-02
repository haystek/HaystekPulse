import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// Full-screen loading, the same look as the top of the sign-in screen:
/// night-sky blue, the logo on a white card, the moving white heartbeat
/// and one short line. Used everywhere the app waits, so it always looks
/// the same, with only one animation on screen.
class PulseLoadingScreen extends StatelessWidget {
  const PulseLoadingScreen({super.key, this.text = 'Your week, heard.'});

  final String text;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1B4D),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0B1B4D), Color(0xFF14328F), AppColors.blue],
              stops: [0, 0.55, 1],
            ),
          ),
          child: SizedBox.expand(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Image.asset('assets/haystek_pulse_logo.png', height: 32),
                ),
                const SizedBox(height: 30),
                const SizedBox(
                  width: 300,
                  height: 56,
                  child: HeartbeatLine(color: Colors.white),
                ),
                const SizedBox(height: 22),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: const Color(0xFFC9D6FF),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The heartbeat line: a faint line with two beats, and a bright blue
/// trail with a dot that runs along it again and again.
class HeartbeatLine extends StatefulWidget {
  const HeartbeatLine({super.key, this.color = AppColors.blue});

  final Color color;

  @override
  State<HeartbeatLine> createState() => _HeartbeatLineState();
}

class _HeartbeatLineState extends State<HeartbeatLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _run,
        builder: (context, _) => CustomPaint(
          painter: _PulsePainter(_run.value, widget.color),
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.t, this.color);

  final double t;
  final Color color;

  static const List<Offset> _beat = [
    Offset(0.00, 0.55),
    Offset(0.28, 0.55),
    Offset(0.34, 0.45),
    Offset(0.40, 0.55),
    Offset(0.46, 0.55),
    Offset(0.50, 0.68),
    Offset(0.55, 0.04),
    Offset(0.60, 0.96),
    Offset(0.64, 0.55),
    Offset(0.74, 0.55),
    Offset(0.81, 0.38),
    Offset(0.88, 0.55),
    Offset(1.00, 0.55),
  ];

  Path _path(Size size) {
    const beats = 2;
    final w = size.width / beats;
    final path = Path();
    for (var b = 0; b < beats; b++) {
      for (var i = 0; i < _beat.length; i++) {
        final p = Offset(b * w + _beat[i].dx * w, _beat[i].dy * size.height);
        if (b == 0 && i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _path(size);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, line..color = color.withValues(alpha: 0.18));

    final metric = path.computeMetrics().first;
    final length = metric.length;
    final head = length * t;
    final trail = length * 0.35;

    const pieces = 10;
    for (var i = 0; i < pieces; i++) {
      final from = head - trail * (1 - i / pieces);
      final to = head - trail * (1 - (i + 1) / pieces);
      if (to <= 0) continue;
      canvas.drawPath(
        metric.extractPath(from.clamp(0.0, length), to.clamp(0.0, length)),
        line
          ..strokeWidth = 2.4
          ..color = color.withValues(alpha: 0.1 + 0.9 * (i + 1) / pieces),
      );
    }

    final dot = metric.getTangentForOffset(head.clamp(0.0, length))?.position;
    if (dot != null) {
      canvas.drawCircle(dot, 8, Paint()..color = color.withValues(alpha: 0.18));
      canvas.drawCircle(dot, 3.5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.t != t || old.color != color;
}
