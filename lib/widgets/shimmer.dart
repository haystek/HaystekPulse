import 'package:flutter/material.dart';

/// A soft light that sweeps over its grey shapes (ShimmerBox), again and
/// again. Used while a part of the screen is still loading.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (rect) {
          final dx = rect.width * (_c.value * 2 - 1);
          return const LinearGradient(
            colors: [Color(0xFFE6EAF2), Color(0xFFF7F9FC), Color(0xFFE6EAF2)],
            stops: [0.35, 0.5, 0.65],
          ).createShader(Rect.fromLTWH(dx, 0, rect.width, rect.height));
        },
        child: child,
      ),
    );
  }
}

/// One grey rounded shape inside a [Shimmer].
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 6,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE6EAF2),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
