import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';


/// App start: keeps the phone splash on screen until the first real
/// screen (Home, sign-in, …) is ready, so the start is one clean change
/// (Splash -> Home) with no loader in between.
class StartupSplash {
  static bool _held = false;

  /// Called first thing in main().
  static void hold(WidgetsBinding binding) {
    _held = true;
    FlutterNativeSplash.preserve(widgetsBinding: binding);
    // Safety: never keep the splash longer than 5 seconds.
    Timer(const Duration(seconds: 5), done);
  }

  /// A real screen is ready: remove the splash (once, after this frame).
  static void done() {
    if (!_held) return;
    _held = false;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => FlutterNativeSplash.remove(),
    );
  }
}
