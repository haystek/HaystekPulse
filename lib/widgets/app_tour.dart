import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One stop of a tour: the widget to highlight (by its key) and a tip.
class TourStep {
  const TourStep(this.key, this.title, this.text);

  final GlobalKey key;
  final String title;
  final String text;
}

/// Shows a tour once per phone ([id] is remembered), a moment after
/// [child] first appears. Navy tip card with a pointer; the rest of the
/// screen is dimmed. Next / Skip / Got it.
class TourStarter extends StatefulWidget {
  const TourStarter({
    super.key,
    required this.id,
    required this.steps,
    required this.child,
    this.delay = const Duration(milliseconds: 900),
  });

  final String id;
  final List<TourStep> Function() steps;
  final Widget child;
  final Duration delay;

  @override
  State<TourStarter> createState() => _TourStarterState();
}

class _TourStarterState extends State<TourStarter> {
  static const _store = FlutterSecureStorage();

  /// Tours already started in this app run.
  static final Set<String> _started = {};

  @override
  void initState() {
    super.initState();
    if (_started.add(widget.id)) _maybeStart();
  }

  Future<void> _maybeStart() async {
    String? seen;
    try {
      seen = await _store.read(key: widget.id);
    } catch (_) {}
    if (seen == '1') return;
    await Future<void>.delayed(widget.delay);
    if (!mounted) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TourOverlay(
        steps: widget.steps(),
        onDone: () {
          entry.remove();
          _store.write(key: widget.id, value: '1').catchError((_) {});
        },
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _TourOverlay extends StatefulWidget {
  const _TourOverlay({required this.steps, required this.onDone});

  final List<TourStep> steps;
  final VoidCallback onDone;

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> {
  late final List<TourStep> _steps = widget.steps
      .where((s) => s.key.currentContext != null)
      .toList();
  int _i = 0;
  Rect? _rect;

  @override
  void initState() {
    super.initState();
    if (_steps.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone());
    } else {
      _show(0);
    }
  }

  Future<void> _show(int i) async {
    final ctx = _steps[i].key.currentContext;
    if (ctx == null) return _next();
    try {
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.35,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
    if (!mounted) return;
    final box = _steps[i].key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return _next();
    final topLeft = box.localToGlobal(Offset.zero);
    setState(() {
      _i = i;
      _rect = (topLeft & box.size).inflate(6);
    });
  }

  void _next() {
    if (_i + 1 >= _steps.length) {
      widget.onDone();
    } else {
      _show(_i + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rect = _rect;
    final size = MediaQuery.sizeOf(context);
    final t = Theme.of(context).textTheme;
    if (rect == null || _steps.isEmpty) {
      return const SizedBox.shrink();
    }
    final step = _steps[_i];
    final last = _i == _steps.length - 1;
    final below = rect.center.dy < size.height * 0.55;
    const pale = Color(0xFFC9D6FF);
    final card = Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF142261), Color(0xFF1B3590), Color(0xFF2A57D9)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, 10),
            spreadRadius: -6,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var k = 0; k < _steps.length; k++)
                Container(
                  width: k == _i ? 18 : 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    color: k == _i
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              const Spacer(),
              Text(
                '${_i + 1} of ${_steps.length}',
                style: t.labelSmall?.copyWith(fontSize: 12, color: pale),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            step.title,
            style: t.titleMedium?.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            step.text,
            style: t.bodyMedium?.copyWith(
              fontSize: 14,
              height: 1.45,
              color: pale,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (!last)
                TextButton(
                  onPressed: widget.onDone,
                  style: TextButton.styleFrom(foregroundColor: pale),
                  child: const Text('Skip'),
                ),
              const Spacer(),
              FilledButton(
                onPressed: _next,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1B3590),
                  shape: const StadiumBorder(),
                ),
                child: Text(last ? 'Got it' : 'Next'),
              ),
            ],
          ),
        ],
      ),
    );
    // Small pointer from the tip to the highlighted card.
    final arrowX = rect.center.dx.clamp(44.0, size.width - 44.0) - 20 - 9;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _next,
              child: TweenAnimationBuilder<Rect?>(
                tween: RectTween(end: rect),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                builder: (_, r, __) =>
                    CustomPaint(painter: _TourDim(r ?? rect)),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            left: 20,
            right: 20,
            top: below ? rect.bottom + 16 : null,
            bottom: below ? null : size.height - rect.top + 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (below)
                  Padding(
                    padding: EdgeInsets.only(left: arrowX),
                    child: const _TourArrow(up: true),
                  ),
                card,
                if (!below)
                  Padding(
                    padding: EdgeInsets.only(left: arrowX),
                    child: const _TourArrow(up: false),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dark layer with a rounded hole around the highlighted card.
class _TourDim extends CustomPainter {
  _TourDim(this.hole);

  final Rect hole;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(26)));
    canvas.drawPath(path, Paint()..color = const Color(0xC70B1230));
  }

  @override
  bool shouldRepaint(_TourDim old) => old.hole != hole;
}

/// Little triangle on the tip card, pointing at the card.
class _TourArrow extends StatelessWidget {
  const _TourArrow({required this.up});

  final bool up;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(18, 9), painter: _TourArrowPainter(up));
  }
}

class _TourArrowPainter extends CustomPainter {
  _TourArrowPainter(this.up);

  final bool up;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path();
    if (up) {
      p
        ..moveTo(0, size.height)
        ..lineTo(size.width / 2, 0)
        ..lineTo(size.width, size.height);
    } else {
      p
        ..moveTo(0, 0)
        ..lineTo(size.width / 2, size.height)
        ..lineTo(size.width, 0);
    }
    canvas.drawPath(
      p..close(),
      Paint()..color = up ? const Color(0xFF15266F) : const Color(0xFF2550C8),
    );
  }

  @override
  bool shouldRepaint(_TourArrowPainter old) => old.up != up;
}
