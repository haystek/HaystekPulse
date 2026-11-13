import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// iPhone keeps the Keychain after the app is deleted, so the intro and the
/// tips would never show again after a reinstall. Android clears them.
///
/// To behave the same on both, we keep a small marker file inside the app's
/// own folder (deleted together with the app). No marker = fresh install:
/// clear ONLY the "seen" marks. The account, personal code and phone ID stay.
class FreshInstall {
  /// True when this app start was the first after a (re)install on iPhone.
  static bool wasFresh = false;

  static const List<String> _seenKeys = [
    'intro_seen_v4',
    'welcome_tour_seen_v4',
    'home_tour_seen_v2',
    'profile_tour_seen_v4',
  ];

  static Future<void> resetSeenMarksIfNew() async {
    if (!Platform.isIOS) return;
    try {
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) return;
      final marker = File('$home/Library/.pulse_installed');
      if (await marker.exists()) return;
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
      await marker.create(recursive: true);
      wasFresh = true;
    } catch (_) {
      // Never block app start for this.
    }
  }
}
