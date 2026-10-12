import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared pieces of the Haystek Pulse look.

/// The app logo: the Haystek mark and name, then "Pulse".
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.height = 34});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/haystek_pulse_logo.png',
      height: height,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'Haystek Pulse',
    );
  }
}

/// The small pulse line under the word "Pulse".
class _WordPulsePainter extends CustomPainter {
  const _WordPulsePainter();

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final h = s.height;
    final mid = h * 0.58;
    final path = Path()
      ..moveTo(0, mid)
      ..lineTo(w * 0.32, mid)
      ..lineTo(w * 0.39, h * 0.08)
      ..lineTo(w * 0.48, h * 0.92)
      ..lineTo(w * 0.55, h * 0.25)
      ..lineTo(w * 0.58, mid)
      ..lineTo(w, mid);
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A 44px round button: white with a thin border.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.child,
    required this.onPressed,
    required this.tooltip,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(width: 44, height: 44, child: Center(child: child)),
        ),
      ),
    );
  }
}

/// The round back button used at the top of inner screens.
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 20),
      child: Center(
        child: RoundIconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Icon(Icons.chevron_left, color: AppColors.ink),
        ),
      ),
    );
  }
}

/// One entry in the account menu.
class MenuAction {
  const MenuAction(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;
}

/// The dark round button with the person's initial. Opens a small menu.
class AccountButton extends StatelessWidget {
  const AccountButton({super.key, required this.name, required this.actions});

  final String name;
  final List<MenuAction> actions;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return PopupMenuButton<int>(
      tooltip: 'Your account',
      position: PopupMenuPosition.under,
      onSelected: (i) => actions[i].onTap(),
      itemBuilder: (context) => [
        for (var i = 0; i < actions.length; i++)
          PopupMenuItem<int>(value: i, child: Text(actions[i].label)),
      ],
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.ink,
          shape: BoxShape.circle,
        ),
        child: Text(initial, style: heading(16, color: Colors.white)),
      ),
    );
  }
}

/// The pulse line: the one signature mark of the app.
class PulseLine extends StatelessWidget {
  const PulseLine({
    super.key,
    this.color = Colors.white,
    this.opacity = 0.3,
    this.height = 90,
  });

  final Color color;
  final double opacity;
  final double height;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _PulsePainter(color.withValues(alpha: opacity)),
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = size.width;
    final h = size.height;
    final y = h * 0.66;
    final x = w * 0.42;
    final path = Path()
      ..moveTo(0, y)
      ..lineTo(x, y)
      ..lineTo(x + 12, h * 0.24)
      ..lineTo(x + 28, h * 0.92)
      ..lineTo(x + 42, h * 0.48)
      ..lineTo(x + 54, y)
      ..lineTo(w, y);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PulsePainter oldDelegate) => oldDelegate.color != color;
}

/// A white panel with a thin border and large corners.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 24,
    this.color = Colors.white,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}
