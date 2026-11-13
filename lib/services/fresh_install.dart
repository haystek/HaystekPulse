import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// iPhone keeps the Keychain after the app is deleted, so the intro and the
/// tips would never show again after a reinstall. Android clears them.
///
/// We keep a small marker file inside the app's own folder (deleted together
/// with the app). No marker = fresh install: the intro and tips show again
/// and the old login is signed out. The personal code and phone ID stay.
class FreshInstall {
  /// True when this app start was the first after a (re)install on iPhone.
  static bool wasFresh = false;

  static final Set<String> _used = {};

  /// True once per tip/intro on a fresh install: show it even if the
  /// iPhone kept an old "seen" mark.
  static bool showAgain(String key) => wasFresh && _used.add(key);

  static const List<String> _seenKeys = [
    'intro_seen_v4',
    'welcome_tour_seen_v4',
    'home_tour_seen_v2',
    'profile_tour_seen_v4',
  ];

  static String? _appDir() {
    try {
      // The temp folder sits inside the app's own folder.
      return Directory.systemTemp.parent.path;
    } catch (_) {}
    final home = Platform.environment['HOME'];
    return (home == null || home.isEmpty) ? null : home;
  }

  static Future<void> resetSeenMarksIfNew() async {
    if (!Platform.isIOS) return;
    try {
      final dir = _appDir();
      // ignore: avoid_print
      print('[Fresh] app folder = $dir');
      if (dir == null) return;
      final marker = File('$dir/Library/.pulse_installed');
      if (await marker.exists()) return;

      wasFresh = true;
      // ignore: avoid_print
      print('[Fresh] fresh install');
      const storage = FlutterSecureStorage();
      const options = [
        IOSOptions(),
        IOSOptions(accessibility: KeychainAccessibility.first_unlock),
        IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
      ];
      for (final key in _seenKeys) {
        for (final o in options) {
          try {
            await storage.delete(key: key, iOptions: o);
          } catch (_) {}
        }
      }
      try {
        await marker.create(recursive: true);
      } catch (e) {
        // ignore: avoid_print
        print('[Fresh] marker not made: $e');
      }
    } catch (e) {
      // ignore: avoid_print
      print('[Fresh] error: $e');
    }
  }
}
