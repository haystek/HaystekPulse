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
  }) => GoogleFonts.plusJakartaSans(
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF0B1B4D),
                          Color(0xFF14328F),
                          AppColors.blue,
                        ],
                        stops: [0, 0.55, 1],
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x8C2453D6),
                          blurRadius: 34,
                          offset: Offset(0, 18),
                          spreadRadius: -16,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.system_update_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    'Please update Haystek Pulse',
                    textAlign: TextAlign.center,
                    style: _s(22, w: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message.isNotEmpty
                        ? message
                        : 'A new version is ready. Please update to keep '
                              'using the app.',
                    textAlign: TextAlign.center,
                    style: _s(15, c: AppColors.muted, h: 1.5),
                  ),
                  const SizedBox(height: 28),
                  if (url.isNotEmpty)
                    FilledButton.icon(
                      onPressed: () => _open(context),
                      icon: const Icon(Icons.download_rounded, size: 20),
                      label: const Text('Update now'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        minimumSize: const Size.fromHeight(54),
                        shape: const StadiumBorder(),
                        textStyle: _s(16, w: FontWeight.w600),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.blueTint,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'Get the new version from the app store, or ask '
                        'the Haystek Pulse team for the latest link.',
                        textAlign: TextAlign.center,
                        style: _s(13.5, h: 1.45),
                      ),
                    ),
                  const SizedBox(height: 18),
                  Text(
                    'Installed: $version  ·  Latest: $latest',
                    textAlign: TextAlign.center,
                    style: _s(12, c: const Color(0xFF8E97AB)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
