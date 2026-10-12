import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A moving heartbeat line, like a hospital monitor: a bright dot runs
/// from left to right drawing the beat, and the line behind it fades
/// away. It loops forever. If the phone has "reduce motion" turned on,
/// it shows a still line instead.
class HeartbeatMonitor extends StatefulWidget {
  const HeartbeatMonitor({super.key, this.duration = const Duration(milliseconds: 2600)});

  /// How long one run from left to right takes.
  final Duration duration;

  @override
  State<HeartbeatMonitor> createState() => _HeartbeatMonitorState();
}

class _HeartbeatMonitorState extends State<HeartbeatMonitor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..repeat();

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _run,
        builder: (context, _) => CustomPaint(
          painter: _MonitorPainter(progress: still ? 1.0 : _run.value),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _MonitorPainter extends CustomPainter {
  _MonitorPainter({required this.progress});

  /// 0 to 1: where the bright dot is, from left to right.
  final double progress;

  /// Height of the line at one point of a beat (0 to 1 across one beat).
  /// Flat, small bump up, big drop, small rise, flat again.
  static double _beat(double t) {
    const pts = <List<double>>[
      [0.00, 0.00],
      [0.30, 0.00],
      [0.34, -0.08],
      [0.38, 0.00],
      [0.44, 0.00],
      [0.48, -0.42],
      [0.53, 0.38],
      [0.57, -0.14],
      [0.61, 0.00],
      [1.00, 0.00],
    ];
    for (var i = 1; i < pts.length; i++) {
      if (t <= pts[i][0]) {
        final a = pts[i - 1];
        final b = pts[i];
        final f = (t - a[0]) / (b[0] - a[0]);
        return a[1] + (b[1] - a[1]) * f;
      }
    }
    return 0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final mid = h / 2;
    // Two beats across the screen.
    final period = w / 2;
    double yAt(double x) => mid + _beat((x % period) / period) * h;

    final head = progress * w;
    // How long the fading tail is.
    final tail = w * 0.85;

    // Very faint full line underneath, so the shape is always there.
    final base = Path()..moveTo(0, yAt(0));
    for (var x = 2.0; x <= w; x += 2) {
      base.lineTo(x, yAt(x));
    }
    canvas.drawPath(
      base,
      Paint()
        ..color = AppColors.blue.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // The bright line behind the dot, fading out towards the left.
    const step = 2.0;
    for (var x = math.max(0.0, head - tail); x < head; x += step) {
      final x2 = math.min(x + step, head);
      final fade = 1 - (head - x) / tail; // 0 far back, 1 at the dot
      canvas.drawLine(
        Offset(x, yAt(x)),
        Offset(x2, yAt(x2)),
        Paint()
          ..color = AppColors.blue.withValues(alpha: 0.55 * fade)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }

    // The bright dot with a soft glow.
    final dot = Offset(head, yAt(head));
    canvas.drawCircle(
      dot,
      9,
      Paint()
        ..color = AppColors.blue.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(dot, 4, Paint()..color = AppColors.blue);
  }

  @override
  bool shouldRepaint(_MonitorPainter old) => old.progress != progress;
}