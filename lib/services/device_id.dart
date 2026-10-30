import 'dart:io';
import 'dart:math';

import 'package:android_id/android_id.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One ID per phone, used only to allow one account per phone.
/// It never says who the person is, and only a scrambled form of it
/// (see [AuthService]) is ever sent to Firebase.
///
/// - Android: ANDROID_ID. Same after the app is deleted and installed
///   again. Changes only after a factory reset.
/// - iPhone: Apple doesn't let apps read the phone's real ID, so the app
///   makes a random ID once and keeps it in the Keychain. The Keychain
///   keeps it even after the app is deleted. "This device only" means it
///   is never copied to another iPhone from a backup.
class DeviceId {
  DeviceId._();

  static const FlutterSecureStorage _store = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  static const String _key = 'device_id_v1';

  static String? _cached;

  static Future<String> get() async {
    final cached = _cached;
    if (cached != null) return cached;
    String? id;
    if (Platform.isAndroid) {
      try {
        id = await const AndroidId().getId();
      } catch (e) {
        debugPrint('[DeviceId] ANDROID_ID not readable: $e');
      }
    }
    id ??= await _ownId();
    _cached = id;
    return id;
  }

  /// A random ID made once and kept in secure storage (Keychain on iPhone).
  static Future<String> _ownId() async {
    try {
      final saved = await _store.read(key: _key);
      if (saved != null && saved.isNotEmpty) return saved;
    } catch (_) {
      // Not readable (rare). A new one is made below.
    }
    final r = Random.secure();
    final id = List<int>.generate(16, (_) => r.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    try {
      await _store.write(key: _key, value: id);
    } catch (e) {
      debugPrint('[DeviceId] could not save: $e');
    }
    return id;
  }
}
