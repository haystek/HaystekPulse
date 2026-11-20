import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// Shows "Please update" when this phone has an older version than the
/// latest one released in the store.
///
/// Firestore `settings/app` (set with ./app_update.sh):
///   latestAndroid  string  e.g. "1.1.2+2" (latest Android release)
///   latestIos      string  e.g. "1.1.2+2" (latest iPhone release)
///   androidUrl     string  Play Store link
///   iosUrl         string  App Store link
///   message        string  optional text for the screen
///
/// Empty value, no internet, or any error: the app opens as normal.
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  PackageInfo? _info;

  // Live: when a new latest version is saved, open apps react at once.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _settings =
      FirebaseFirestore.instance.doc('settings/app').snapshots();

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _info = i);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _settings,
      builder: (context, snap) {
        final info = _info;
        if (info == null) return widget.child;
        final data = snap.hasError ? null : snap.data?.data();
        final isIos = defaultTargetPlatform == TargetPlatform.iOS;
        final latestKey = isIos ? 'latestIos' : 'latestAndroid';
        final latest = (data?[latestKey] as String?)?.trim() ?? '';
        // This phone, e.g. "1.1.2+2" (Android dev builds end in "-dev").
        final mine =
            '${info.version.replaceAll('-dev', '')}+${info.buildNumber}';
        if (!_isOlder(mine, latest)) return widget.child;

        final linkKey = isIos ? 'iosUrl' : 'androidUrl';
        final url = (data?[linkKey] as String?)?.trim() ?? '';
        final message = (data?['message'] as String?)?.trim() ?? '';
        return _UpdateScreen(
          url: url,
          message: message,
          version: mine,
          latest: latest,
        );
      },
    );
  }
}

/// "1.1.2+2" -> name parts [1, 1, 2] and build 2. "99.0.0" -> no build.
/// Null if not a version.
({List<int> name, int? build})? _parse(String v) {
  final m = RegExp(r'^(\d+(?:\.\d+)*)(?:\+(\d+))?$').firstMatch(v.trim());
  if (m == null) return null;
  return (
    name: m.group(1)!.split('.').map(int.parse).toList(),
    build: m.group(2) == null ? null : int.parse(m.group(2)!),
  );
}

/// True only when [mine] is clearly older than [latest]: first the name
/// (1.1.1 < 1.1.2), then, for the same name, the build (+1 < +2).
/// Anything unclear (empty, wrong format) counts as not older.
bool _isOlder(String mine, String latest) {
  final a = _parse(mine);
  final b = _parse(latest);
  if (a == null || b == null) return false;
  final len = a.name.length > b.name.length ? a.name.length : b.name.length;
  for (var i = 0; i < len; i++) {
    final x = i < a.name.length ? a.name[i] : 0;
    final y = i < b.name.length ? b.name[i] : 0;
    if (x != y) return x < y;
  }
  // Same name: compare builds only if the latest has one ("1.1.2+2").
  final want = b.build;
  if (want == null) return false;
  return (a.build ?? 0) < want;
}

class _UpdateScreen extends StatelessWidget {
  const _UpdateScreen({
    required this.url,
    required this.message,
    required this.version,
    required this.latest,
  });

  final String url;
  final String message;
  final String version;
  final String latest;

  TextStyle _s(
    double size, {
    FontWeight w = FontWeight.w400,
    Color c = AppColors.ink,
    double? h,
  }) => GoogleFonts.inter(
    fontSize: size,
    fontWeight: w,
    color: c,
    height: h,
  );

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    var ok = false;
    try {
      ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not open the store. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _UpdateBody(
      onUpdate: () => _open(context),
      message: message,
      version: version,
      latest: latest,
    );
  }
}

// ── Update screen design B: soft card, gently animated ──────────────────────
class _UpdateBody extends StatefulWidget {
  const _UpdateBody({
    required this.onUpdate,
    required this.message,
    required this.version,
    required this.latest,
  });

  final VoidCallback onUpdate;
  final String message;
  final String version;
  final String latest;

  @override
  State<_UpdateBody> createState() => _UpdateBodyState();
}

class _UpdateBodyState extends State<_UpdateBody>
    with TickerProviderStateMixin {
  static const _ink = Color(0xFF0F1A3A);
  static const _grey = Color(0xFF5B6478);
  static const _soft = Color(0xFF9AA2B5);
  static const _blue = Color(0xFF1C4ED8);

  // Arrow drops in + bar fills (loop).
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();
  // Dotted ring turns slowly.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat();
  // Light sweep on the button.
  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();
  // Card slides up once when the screen opens.
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Phone setting "reduce motion": show a still screen.
    if (MediaQuery.of(context).disableAnimations) {
      _loop.stop();
      _loop.value = 0.75;
      _spin.stop();
      _shine.stop();
      _shine.value = 1;
      _enter.value = 1;
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    _spin.dispose();
    _shine.dispose();
    _enter.dispose();
    super.dispose();
  }

  TextStyle _t(double size, {FontWeight w = FontWeight.w400, Color c = _ink, double? h}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: c, height: h);

  /// "1.0.0+12" -> "1.0.0 (12)".
  static String _nice(String v) {
    final i = v.indexOf('+');
    return i < 0 ? v : '${v.substring(0, i)} (${v.substring(i + 1)})';
  }

  Widget _picture() {
    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RotationTransition(
            turns: _spin,
            child: CustomPaint(size: const Size(240, 240), painter: _OrbitPainter()),
          ),
          Container(
            width: 170,
            height: 170,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFF2F6FF),
              border: Border.all(color: const Color(0xFFDDE6FB), width: 1.5),
            ),
          ),
          Container(
            width: 84,
            height: 140,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0B1A4F), _blue],
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x591C4ED8), blurRadius: 36, offset: Offset(0, 18)),
              ],
            ),
            child: AnimatedBuilder(
              animation: _loop,
              builder: (context, _) {
                final t = _loop.value;
                final drop = Curves.easeInOut.transform((t / 0.6).clamp(0.0, 1.0));
                final dy = -26 + 30 * drop;
                final fade = (t / 0.3).clamp(0.0, 1.0);
                final fill = Curves.easeInOut.transform((t / 0.7).clamp(0.0, 1.0));
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Transform.translate(
                      offset: Offset(0, dy),
                      child: Opacity(
                        opacity: fade,
                        child: const Icon(Icons.arrow_downward_rounded, color: Colors.white, size: 30),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: SizedBox(
                        width: 50,
                        height: 6,
                        child: Stack(
                          children: [
                            const Positioned.fill(child: ColoredBox(color: Color(0x40FFFFFF))),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: fill,
                                heightFactor: 1,
                                child: const ColoredBox(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _button() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Material(
        color: _blue,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onUpdate,
          child: LayoutBuilder(
            builder: (context, box) => Stack(
              children: [
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.download_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text('Update now', style: _t(17, w: FontWeight.w700, c: Colors.white)),
                    ],
                  ),
                ),
                AnimatedBuilder(
                  animation: _shine,
                  builder: (context, _) {
                    final p = (_shine.value / 0.45).clamp(0.0, 1.0);
                    final x = -80 + (box.maxWidth + 100) * p;
                    return Positioned(
                      top: 0,
                      bottom: 0,
                      left: x,
                      width: 60,
                      child: IgnorePointer(
                        child: Transform(
                          transform: Matrix4.skewX(-0.35),
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0x00FFFFFF), Color(0x73FFFFFF), Color(0x00FFFFFF)],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final up = CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);
    final fadeIn = CurvedAnimation(parent: _enter, curve: const Interval(0.5, 1, curve: Curves.easeOut));
    final text = widget.message.isNotEmpty
        ? widget.message
        : 'Please update Haystek Pulse to keep using the app.';

    return Scaffold(
      backgroundColor: Colors.white,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0, 0.58],
            colors: [Color(0xFFEEF3FF), Colors.white],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _picture(),
                          const SizedBox(height: 36),
                          FadeTransition(
                            opacity: up,
                            child: SlideTransition(
                              position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(up),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: const Color(0xFFE3E8F2)),
                                  boxShadow: const [
                                    BoxShadow(color: Color(0x140F1A3A), blurRadius: 34, offset: Offset(0, 14)),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    Text('A new version is ready',
                                        textAlign: TextAlign.center,
                                        style: _t(23, w: FontWeight.w700)),
                                    const SizedBox(height: 8),
                                    Text(text,
                                        textAlign: TextAlign.center,
                                        style: _t(14, c: _grey, h: 1.5)),
                                    const SizedBox(height: 16),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF2F4F8),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(_nice(widget.version), style: _t(13, c: _grey)),
                                          const SizedBox(width: 8),
                                          const Icon(Icons.arrow_forward_rounded, size: 14, color: _grey),
                                          const SizedBox(width: 8),
                                          Text(_nice(widget.latest),
                                              style: _t(13, w: FontWeight.w700, c: _blue)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    _button(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          FadeTransition(
                            opacity: fadeIn,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.lock_outline_rounded, size: 14, color: _soft),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text('Your answers and settings stay safe',
                                      style: _t(12, c: _soft)),
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
          ),
        ),
      ),
    );
  }
}

/// Dotted ring with three coloured dots (turned by RotationTransition).
class _OrbitPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 2;
    final dash = Paint()
      ..color = const Color(0xFFC5D3F7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const n = 60;
    for (var k = 0; k < n; k++) {
      final a = k * 2 * math.pi / n;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), a, math.pi / n, false, dash);
    }
    void dot(double deg, double d, Color color) {
      final a = deg * math.pi / 180;
      canvas.drawCircle(
        c + Offset(math.cos(a) * r, math.sin(a) * r),
        d / 2,
        Paint()..color = color,
      );
    }
    dot(200, 12, const Color(0xFF2F5CF0));
    dot(300, 9, const Color(0xFFF5B73B));
    dot(40, 10, const Color(0xFF27B07F));
  }

  @override
  bool shouldRepaint(_OrbitPainter oldDelegate) => false;
}

