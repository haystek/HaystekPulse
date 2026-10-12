import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A white card that slides down from the top of the screen, for a
/// notification that arrives while the app is open.
/// It hides by itself after a few seconds, or when swiped up, or when
/// "Later" is tapped. Only one shows at a time.
class TopBanner {
  TopBanner._();

  static OverlayEntry? _current;

  static void show({
    required OverlayState overlay,
    required IconData icon,
    required Color iconColor,
    required Color tint,
    required String title,
    required String body,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 6),
  }) {
    hide();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _BannerView(
        icon: icon,
        iconColor: iconColor,
        tint: tint,
        title: title,
        body: body,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
        onGone: () {
          if (_current == entry) {
            entry.remove();
            _current = null;
          }
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }

  /// Removes the banner on screen, if any.
  static void hide() {
    _current?.remove();
    _current = null;
  }
}

class _BannerView extends StatefulWidget {
  const _BannerView({
    required this.icon,
    required this.iconColor,
    required this.tint,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    required this.duration,
    required this.onGone,
  });

  final IconData icon;
  final Color iconColor;
  final Color tint;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
  final VoidCallback onGone;

  @override
  State<_BannerView> createState() => _BannerViewState();
}

class _BannerViewState extends State<_BannerView>
    with TickerProviderStateMixin {
  /// Slides the card in and out.
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  /// The thin blue line that runs out, then the card hides.
  late final AnimationController _timer = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _slide.forward();
    _timer.forward().whenComplete(_close);
  }

  @override
  void dispose() {
    _slide.dispose();
    _timer.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer.stop();
    await _slide.reverse();
    widget.onGone();
  }

  Future<void> _tapAction() async {
    final action = widget.onAction;
    await _close();
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _slide, curve: Curves.easeOutCubic);
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: SafeArea(
        bottom: false,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1.3),
            end: Offset.zero,
          ).animate(curve),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                // Swipe up to close.
                child: GestureDetector(
                  onVerticalDragEnd: (d) {
                    if ((d.primaryVelocity ?? 0) < -100) _close();
                  },
                  onTap: widget.onAction == null ? null : _tapAction,
                  child: Material(
                    color: Colors.white,
                    elevation: 12,
                    shadowColor: const Color(0x590E1A3A),
                    borderRadius: BorderRadius.circular(22),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 10, 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: widget.tint,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  widget.icon,
                                  color: widget.iconColor,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: heading(
                                        15.5,
                                        weight: FontWeight.w800,
                                      ),
                                    ),
                                    if (widget.body.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        widget.body,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 14,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Close',
                                visualDensity: VisualDensity.compact,
                                onPressed: _close,
                                icon: const Icon(
                                  Icons.close,
                                  size: 20,
                                  color: Color(0xFF8A94AA),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(70, 10, 14, 14),
                          child: Row(
                            children: [
                              if (widget.actionLabel != null) ...[
                                FilledButton(
                                  onPressed: _tapAction,
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(0, 38),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  child: Text(widget.actionLabel!),
                                ),
                                const SizedBox(width: 8),
                              ],
                              TextButton(
                                onPressed: _close,
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(0, 38),
                                  backgroundColor: const Color(0xFFF2F6FF),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                child: Text(
                                  widget.actionLabel == null ? 'OK' : 'Later',
                                ),
                              ),
                            ],
                          ),
                        ),
                        // The line that shows how long until it hides.
                        AnimatedBuilder(
                          animation: _timer,
                          builder: (context, _) => Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: 1 - _timer.value,
                              child: Container(
                                height: 3,
                                color: AppColors.blue,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
