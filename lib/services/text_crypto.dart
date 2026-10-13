import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Locks and unlocks the text people write (suggestions, Weekly Pulse
/// comments and management replies), so Firestore and the Firebase
/// console only ever hold unreadable text.
///
/// Locked text looks like `enc1:Xk92Lq0p...`. Text saved before this
/// change has no `enc1:` at the start and is shown as it is.
///
/// IMPORTANT: never change or lose [_keyBase64]. A different key cannot
/// open messages that were locked with this one, so they would be lost.
class TextCrypto {
  TextCrypto._();

  /// The secret key (AES-256). Keep it private.
  static const String _keyBase64 =
      'pGnltKvOTLjl0WwLwcI9iB/oQWd0u4SzPndtKHv5i20=';

  static const String _prefix = 'enc1:';
  static const int _ivLength = 12;
  static const int _tagBits = 128;

  static final Uint8List _key = base64Decode(_keyBase64);
  static final Random _random = Random.secure();

  /// True if this text is locked.
  static bool isLocked(String value) => value.startsWith(_prefix);

  /// Locks [plain]. Empty text stays empty.
  static String encrypt(String plain) {
    if (plain.isEmpty || isLocked(plain)) return plain;
    final iv = Uint8List.fromList(
      List<int>.generate(_ivLength, (_) => _random.nextInt(256)),
    );
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(_key), _tagBits, iv, Uint8List(0)),
      );
    final locked = cipher.process(Uint8List.fromList(utf8.encode(plain)));
    final out = Uint8List(iv.length + locked.length)
      ..setAll(0, iv)
      ..setAll(iv.length, locked);
    return '$_prefix${base64Encode(out)}';
  }

  /// Unlocks [value]. Old, unlocked text is returned as it is.
  static String decrypt(String value) {
    if (!isLocked(value)) return value;
    try {
      final data = base64Decode(value.substring(_prefix.length));
      final iv = Uint8List.sublistView(data, 0, _ivLength);
      final locked = Uint8List.sublistView(data, _ivLength);
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(KeyParameter(_key), _tagBits, iv, Uint8List(0)),
        );
      return utf8.decode(cipher.process(locked));
    } catch (_) {
      return 'This message could not be opened.';
    }
  }
}