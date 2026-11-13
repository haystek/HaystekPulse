import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'vault_service.dart';

/// Admin code used to sign up as admin.
///
/// Only the SHA-256 of the code is saved, in `admin_codes/{hash}`.
/// Reset = make a new random code, delete the old one(s), save the new hash.
/// Admins who already signed up are not affected.
class AdminCodeService {
  // No I or O, so the code is easy to read and type.
  static const _letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';

  static String newCode() {
    final r = Random.secure();
    return List.generate(6, (_) => _letters[r.nextInt(_letters.length)]).join();
  }

  /// Makes a new code, removes the old one(s). Returns the new code.
  static Future<String> reset() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('not-signed-in');
    final db = FirebaseFirestore.instance;
    final col = db.collection('admin_codes');
    final old = await col.get(const GetOptions(source: Source.server));
    final code = newCode();
    final hash = VaultService.sha256Hex(code);
    final batch = db.batch();
    for (final d in old.docs) {
      if (d.id != hash) batch.delete(d.reference);
    }
    batch.set(col.doc(hash), {
      'createdAt': FieldValue.serverTimestamp(),
      'by': user.uid,
    });
    // Readable copy for admins only (Profile -> Admin code: Show / Copy).
    batch.set(db.collection('admin_secret').doc('current'), {
      'code': code,
      'createdAt': FieldValue.serverTimestamp(),
      'by': user.uid,
    });
    await batch.commit();
    return code;
  }

  /// The current admin code, live. Null until the first reset in the app.
  static Stream<String?> current() => FirebaseFirestore.instance
      .collection('admin_secret')
      .doc('current')
      .snapshots()
      .map((d) => d.data()?['code'] as String?);
}
