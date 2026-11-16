import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Red "No internet connection" bar at the top of every screen.
/// Shows after 2 seconds without internet (so a short drop does not flash),
/// and hides by itself as soon as it is back. Also catches Wi-Fi that has
/// no internet: every 10 seconds a tiny request checks Google can be reached.
class OfflineBar extends StatefulWidget {
  const OfflineBar({super.key, required this.child});

  final Widget child;

  @override
  State<OfflineBar> createState() => _OfflineBarState();
}

class _OfflineBarState extends State<OfflineBar> {
  StreamSubscription<Object?>? _sub;
  Timer? _wait;
  Timer? _poll;
  bool _offline = false;
  bool _netUp = true;

  static bool _none(Object? r) => r is List
      ? (r.isEmpty || r.every((e) => e == ConnectivityResult.none))
      : r == ConnectivityResult.none;

  @override
  void initState() {
    super.initState();
    final c = Connectivity();
    c.checkConnectivity().then(_on, onError: (_) {});
    _sub = c.onConnectivityChanged.listen(_on, onError: (_) {});
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _check());
  }

  void _on(Object? r) {
    _netUp = !_none(r);
    _check();
  }

  /// Network on? Then also check the internet really works.
  Future<void> _check() async {
    var ok = _netUp;
    if (ok && !kIsWeb) {
      try {
        final res = await http
            .head(Uri.parse('https://www.gstatic.com/generate_204'))
            .timeout(const Duration(seconds: 5));
        ok = res.statusCode < 500;
      } catch (_) {
        ok = false;
      }
    }
    _set(!ok);
  }

  void _set(bool off) {
    if (!mounted) return;
    if (off) {
      _wait ??= Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _offline = true);
      });
    } else {
      _wait?.cancel();
      _wait = null;
      if (_offline) setState(() => _offline = false);
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _poll?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          child: _offline
              ? Material(
                  color: const Color(0xFFB42318),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, mq.padding.top + 6, 16, 8),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.wifi_off_rounded,
                            color: Colors.white, size: 16),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'No internet connection',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        Expanded(
          // Same widget tree online and offline, so no screen is rebuilt.
          child: MediaQuery(
            data: _offline ? mq.removePadding(removeTop: true) : mq,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
