import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

/// What the vault holds: the IDs of my posts and my Weekly Pulse answers.
/// Only the employee can open it.
class VaultData {
  const VaultData({this.posts = const [], this.pulse = const {}});

  /// IDs of my suggestions and Weekly Pulse comments.
  final List<String> posts;

  /// My Weekly Pulse answers: weekId -> rating ('great', 'good', ...).
  final Map<String, String> pulse;

  Map<String, dynamic> toJson() => {'posts': posts, 'pulse': pulse};

  factory VaultData.fromJson(Map<String, dynamic> j) => VaultData(
        posts: [for (final p in (j['posts'] as List? ?? const [])) p as String],
        pulse: {
          for (final e in (j['pulse'] as Map? ?? const {}).entries)
            e.key as String: e.value as String,
        },
      );
}

/// Result of opening the vault with a password.
enum VaultOpen {
  /// Opened (or made new, see [VaultService.lastNewCode]).
  opened,

  /// A vault exists, but this password can't open it: the password was
  /// reset. The backup code is needed.
  needsBackup,
}

/// The employee's private, locked "diary" (`vaults/{uid}` in Firestore).
///
/// How it works:
/// - A random 32-byte **history key** locks the list of my posts.
/// - The history key is saved locked twice: with a key made from my
///   **password**, and with a key made from my **backup code**.
/// - Keys are made with PBKDF2 (many rounds, slow to guess) and locking
///   is AES-256-GCM. Everything happens on the phone; Firestore only
///   ever gets locked data. Admin and developer can't open it.
/// - While signed in, the history key is kept in the phone's secure
///   storage, so the password is not asked every time. Sign out deletes it.
class VaultService {
  VaultService._();
  static final VaultService instance = VaultService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const FlutterSecureStorage _store = FlutterSecureStorage();

  /// Rounds for the password key. Higher = slower to guess.
  static const int _passwordRounds = 200000;

  /// Rounds for the backup code key (the code itself is already long
  /// and random, so fewer rounds are enough).
  static const int _codeRounds = 20000;

  /// The opened list, live. Null while locked.
  final ValueNotifier<VaultData?> data = ValueNotifier<VaultData?>(null);

  Uint8List? _key;
  String? _uid;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  /// The backup code made by the last [openWithPassword] that created a
  /// new vault, or by [startFresh]. Shown once, then cleared.
  String? lastNewCode;

  bool get isReady => _key != null && data.value != null;

  List<String> get postIds => data.value?.posts ?? const [];

  String? pulseRating(String weekId) => data.value?.pulse[weekId];

  DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      _db.collection('vaults').doc(uid);

  static String _storeKey(String uid) => 'vault_key_$uid';

  // -------------------------------------------------------------------
  // Opening
  // -------------------------------------------------------------------

  /// Opens with the key saved on this phone. False if there is none, or
  /// it no longer fits (for example the vault was made new on another
  /// phone).
  Future<bool> openSaved(String uid) async {
    String? saved;
    try {
      saved = await _store.read(key: _storeKey(uid));
    } catch (_) {
      saved = null; // Secure storage not readable (e.g. after reinstall).
    }
    if (saved == null) return false;
    try {
      final key = base64Decode(saved);
      final doc = await _ref(uid).get();
      final d = doc.data();
      if (d == null) return false;
      final list = _open(key, d['list'] as String);
      _activate(uid, key, VaultData.fromJson(jsonDecode(list) as Map<String, dynamic>));
      return true;
    } catch (e) {
      debugPrint('[Vault] saved key not usable: $e');
      await _forget(uid);
      return false;
    }
  }

  /// Opens the vault with the person's password, or makes a new one if
  /// they have none yet. A new vault puts its backup code in
  /// [lastNewCode].
  ///
  /// The password must already be checked (sign in, or re-auth).
  Future<VaultOpen> openWithPassword(String uid, String password) async {
    // Ask the server, so a new vault is never made by mistake while
    // offline. No internet: throws, and the screen offers "Try again".
    final doc = await _ref(uid).get(const GetOptions(source: Source.server));
    final d = doc.data();
    if (d == null) {
      await _create(uid, password);
      return VaultOpen.opened;
    }
    final passKey = await _derive(password, d['salt'] as String, _passwordRounds);
    final Uint8List key;
    try {
      key = _openBytes(passKey, d['byPassword'] as String);
    } catch (_) {
      return VaultOpen.needsBackup;
    }
    final list = _open(key, d['list'] as String);
    await _activateAndSave(
      uid,
      key,
      VaultData.fromJson(jsonDecode(list) as Map<String, dynamic>),
    );
    return VaultOpen.opened;
  }

  /// After "Forgot password": opens with the backup code, then locks the
  /// history key again with the new password. False if the code is wrong.
  Future<bool> openWithBackup(String uid, String code, String password) async {
    final doc = await _ref(uid).get(const GetOptions(source: Source.server));
    final d = doc.data();
    if (d == null) return false;
    final codeKey =
        await _derive(normalizeCode(code), d['backupSalt'] as String, _codeRounds);
    final Uint8List key;
    try {
      key = _openBytes(codeKey, d['byBackup'] as String);
    } catch (_) {
      return false;
    }
    final list = _open(key, d['list'] as String);
    // Lock with the new password, so the code is not needed next time.
    final salt = _randomB64(16);
    final passKey = await _derive(password, salt, _passwordRounds);
    await _ref(uid).update({
      'salt': salt,
      'byPassword': _lockBytes(passKey, key),
    });
    await _activateAndSave(
      uid,
      key,
      VaultData.fromJson(jsonDecode(list) as Map<String, dynamic>),
    );
    return true;
  }

  /// No password and no backup code: start a new, empty history.
  /// The old posts stay for admin, but can't be shown here again.
  Future<void> startFresh(String uid, String password) =>
      _create(uid, password);

  Future<void> _create(String uid, String password) async {
    final key = _randomBytes(32);
    final salt = _randomB64(16);
    final passKey = await _derive(password, salt, _passwordRounds);
    final code = _newCode();
    final backupSalt = _randomB64(16);
    final codeKey = await _derive(normalizeCode(code), backupSalt, _codeRounds);
    const empty = VaultData();
    await _ref(uid).set({
      'v': 1,
      'salt': salt,
      'byPassword': _lockBytes(passKey, key),
      'backupSalt': backupSalt,
      'byBackup': _lockBytes(codeKey, key),
      'list': _lock(key, jsonEncode(empty.toJson())),
    });
    lastNewCode = code;
    await _activateAndSave(uid, key, empty);
  }

  // -------------------------------------------------------------------
  // Changing the password or the backup code
  // -------------------------------------------------------------------

  /// The password was changed in the app: lock the history key with the
  /// new one. Nothing is lost.
  Future<void> rewrapPassword(String newPassword) async {
    final uid = _uid;
    final key = _key;
    if (uid == null || key == null) return;
    final salt = _randomB64(16);
    final passKey = await _derive(newPassword, salt, _passwordRounds);
    await _ref(uid).update({
      'salt': salt,
      'byPassword': _lockBytes(passKey, key),
    });
  }

  /// Makes a new backup code. The old one stops working at once.
  Future<String> newBackupCode() async {
    final uid = _uid;
    final key = _key;
    if (uid == null || key == null) {
      throw StateError('Vault is locked');
    }
    final code = _newCode();
    final backupSalt = _randomB64(16);
    final codeKey = await _derive(normalizeCode(code), backupSalt, _codeRounds);
    await _ref(uid).update({
      'backupSalt': backupSalt,
      'byBackup': _lockBytes(codeKey, key),
    });
    return code;
  }

  // -------------------------------------------------------------------
  // Adding to the list
  // -------------------------------------------------------------------

  /// Adds a post ID (before it is sent, so a retry can't lose it).
  /// Saved on the phone at once and sent when there is internet.
  Future<void> addPost(String id) async {
    final d = data.value;
    if (d == null || d.posts.contains(id)) return;
    _save(VaultData(posts: [...d.posts, id], pulse: d.pulse));
  }

  /// Keeps my Weekly Pulse answer for this week.
  Future<void> setPulse(String weekId, String rating) async {
    final d = data.value;
    if (d == null) return;
    _save(VaultData(posts: d.posts, pulse: {...d.pulse, weekId: rating}));
  }

  void _save(VaultData next) {
    final uid = _uid;
    final key = _key;
    if (uid == null || key == null) return;
    data.value = next;
    // Not awaited: Firestore keeps it on the phone and sends it later
    // if there is no internet now.
    _ref(uid)
        .update({'list': _lock(key, jsonEncode(next.toJson()))})
        .catchError((Object e) => debugPrint('[Vault] save failed: $e'));
  }

  // -------------------------------------------------------------------
  // Closing (sign out)
  // -------------------------------------------------------------------

  /// Sign out: forget the key on this phone and close the list.
  Future<void> close() async {
    final uid = _uid;
    await _sub?.cancel();
    _sub = null;
    _key = null;
    _uid = null;
    data.value = null;
    lastNewCode = null;
    if (uid != null) await _forget(uid);
  }

  Future<void> _forget(String uid) async {
    try {
      await _store.delete(key: _storeKey(uid));
    } catch (_) {}
  }

  // -------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------

  Future<void> _activateAndSave(String uid, Uint8List key, VaultData d) async {
    try {
      await _store.write(key: _storeKey(uid), value: base64Encode(key));
    } catch (e) {
      // Not fatal: the password is just asked again next time.
      debugPrint('[Vault] could not keep the key: $e');
    }
    _activate(uid, key, d);
  }

  /// Opens the list and keeps it up to date (other phones can add to it).
  void _activate(String uid, Uint8List key, VaultData d) {
    _sub?.cancel();
    _uid = uid;
    _key = key;
    data.value = d;
    _sub = _ref(uid).snapshots().listen((doc) {
      final raw = doc.data()?['list'] as String?;
      if (raw == null || _key == null) return;
      try {
        data.value = VaultData.fromJson(
          jsonDecode(_open(_key!, raw)) as Map<String, dynamic>,
        );
      } catch (e) {
        // Made new on another phone with a different key. The next app
        // start asks for the password again.
        debugPrint('[Vault] list could not be opened: $e');
      }
    }, onError: (Object e) => debugPrint('[Vault] $e'));
  }

  static final Random _random = Random.secure();

  static Uint8List _randomBytes(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _random.nextInt(256)));

  static String _randomB64(int n) => base64Encode(_randomBytes(n));

  /// Backup code: 16 letters/digits in 4 groups, like K7QM-2XPA-9RTD-4LNC.
  /// No 0/O or 1/I, so it is easy to type.
  static String _newCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final b = StringBuffer();
    for (var i = 0; i < 16; i++) {
      if (i > 0 && i % 4 == 0) b.write('-');
      b.write(chars[_random.nextInt(chars.length)]);
    }
    return b.toString();
  }

  /// "k7qm 2xpa-9rtd4lnc" -> "K7QM2XPA9RTD4LNC".
  static String normalizeCode(String code) =>
      code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// Password (or code) -> 32-byte key. Runs in the background, so the
  /// screen does not freeze.
  static Future<Uint8List> _derive(String secret, String saltB64, int rounds) =>
      compute(_pbkdf2, <Object>[secret, saltB64, rounds]);

  static const int _ivLength = 12;

  /// AES-256-GCM: random IV + locked bytes, as base64.
  static String _lockBytes(Uint8List key, Uint8List plain) {
    final iv = _randomBytes(_ivLength);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    final locked = cipher.process(plain);
    final out = Uint8List(iv.length + locked.length)
      ..setAll(0, iv)
      ..setAll(iv.length, locked);
    return base64Encode(out);
  }

  /// Opens [_lockBytes]. Throws if the key is wrong.
  static Uint8List _openBytes(Uint8List key, String lockedB64) {
    final data = base64Decode(lockedB64);
    final iv = Uint8List.sublistView(data, 0, _ivLength);
    final locked = Uint8List.sublistView(data, _ivLength);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    return cipher.process(locked);
  }

  static String _lock(Uint8List key, String text) =>
      _lockBytes(key, Uint8List.fromList(utf8.encode(text)));

  static String _open(Uint8List key, String lockedB64) =>
      utf8.decode(_openBytes(key, lockedB64));

  /// SHA-256 of a text, as hex. Used for the admin code check.
  static String sha256Hex(String text) {
    final digest = SHA256Digest().process(Uint8List.fromList(utf8.encode(text)));
    return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Top level, so it can run in a background isolate ([compute]).
/// args: [secret, saltBase64, rounds].
Uint8List _pbkdf2(List<Object> args) {
  final secret = args[0] as String;
  final salt = base64Decode(args[1] as String);
  final rounds = args[2] as int;
  final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(salt, rounds, 32));
  return kdf.process(Uint8List.fromList(utf8.encode(secret)));
}
