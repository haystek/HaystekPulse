import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../demo_data.dart';
import '../models/employee.dart';
import 'dual_role.dart';
import 'notification_service.dart';
import 'push_sender.dart';
import 'text_crypto.dart';

/// Notification type for a new broadcast.
const String typeBroadcast = 'broadcast';

/// One message from admin to everyone (`updates/{id}`).
class Broadcast {
  const Broadcast({
    required this.id,
    required this.title,
    required this.body,
    this.quote,
    this.createdAt,
    this.commentCount = 0,
  });

  final String id;
  final String title;
  final String body;

  /// The suggestion it answers, when sent from a suggestion. Never the
  /// name of who wrote it.
  final String? quote;
  final DateTime? createdAt;
  final int commentCount;

  factory Broadcast.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final quote = TextCrypto.decrypt((d['quote'] ?? '') as String);
    return Broadcast(
      id: doc.id,
      title: TextCrypto.decrypt((d['title'] ?? '') as String),
      body: TextCrypto.decrypt((d['body'] ?? '') as String),
      quote: quote.trim().isEmpty ? null : quote,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      commentCount: (d['commentCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One comment under a broadcast.
class BroadcastComment {
  const BroadcastComment({
    required this.id,
    required this.text,
    required this.admin,
    this.name,
    this.createdAt,
    this.pending = false,
  });

  final String id;
  final String text;

  /// Written by an admin.
  final bool admin;

  /// The writer's name, only when they chose "Show my name".
  final String? name;
  final DateTime? createdAt;
  final bool pending;

  factory BroadcastComment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return BroadcastComment(
      id: doc.id,
      text: TextCrypto.decrypt((d['text'] ?? '') as String),
      admin: d['admin'] == true,
      name: d['name'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      pending: doc.metadata.hasPendingWrites,
    );
  }
}

/// Broadcast: admin sends one message to everyone, everyone gets a
/// notification and can discuss it in the comments.
class BroadcastService {
  BroadcastService._();
  static final BroadcastService instance = BroadcastService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _updates =>
      _db.collection('updates');

  /// Newest first.
  Stream<List<Broadcast>> watchAll() => _updates
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((s) {
        final real = s.docs.map(Broadcast.fromDoc).toList();
        if (!DemoData.on) return real;
        // Sample broadcasts too (memory only).
        final old = DateTime(2000);
        return [...real, ...DemoData.broadcasts()]..sort(
          (a, b) => (b.createdAt ?? old).compareTo(a.createdAt ?? old),
        );
      });

  Stream<Broadcast?> watchOne(String id) => id.startsWith(DemoData.idPrefix)
      ? Stream.value(
          DemoData.broadcasts().where((b) => b.id == id).firstOrNull,
        )
      : _updates
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? Broadcast.fromDoc(d) : null);

  /// Oldest first, like a chat.
  Stream<List<BroadcastComment>> watchComments(String id) =>
      id.startsWith(DemoData.idPrefix)
      ? Stream.value(DemoData.broadcastComments(id))
      : _updates
      .doc(id)
      .collection('comments')
      .orderBy('createdAt')
      .snapshots(includeMetadataChanges: true)
      .map((s) => s.docs.map(BroadcastComment.fromDoc).toList());

  /// Admin: sends to everyone. Returns the new broadcast's ID.
  Future<String> send({
    required String title,
    required String body,
    String? quote,
  }) async {
    final ref = _updates.doc();
    await ref
        .set(<String, dynamic>{
          'title': TextCrypto.encrypt(title.trim()),
          'body': TextCrypto.encrypt(body.trim()),
          if (quote != null && quote.trim().isNotEmpty)
            'quote': TextCrypto.encrypt(quote.trim()),
          'commentCount': 0,
          'createdAt': FieldValue.serverTimestamp(),
        })
        .timeout(const Duration(seconds: 15));

    // Everyone's phone is in the "employees" group, except the sender's own
    // phone when it is an HR/Ops phone (its private "me" group). If that
    // can't be sent, send to everyone as before.
    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    final everyoneButMe =
        "'${NotificationService.topicEmployees}' in topics && "
        "!('${DualRole.meTopic(me)}' in topics)";
    final pushTitle = '📢 ${title.trim()}';
    final pushBody = PushSender.shorten(body);
    final pushData = {'type': typeBroadcast, 'broadcastId': ref.id};
    Future<bool> push() async {
      final ok = await PushSender.toCondition(
        everyoneButMe,
        title: pushTitle,
        body: pushBody,
        data: pushData,
      );
      if (ok) return true;
      return PushSender.toTopic(
        NotificationService.topicEmployees,
        title: pushTitle,
        body: pushBody,
        data: pushData,
      );
    }

    unawaited(
      push().catchError((Object e) {
        debugPrint('[Broadcast] push failed: $e');
        return false;
      }),
    );
    return ref.id;
  }

  /// Adds a comment. Shows at once, and goes to the server when there is
  /// internet. Employees choose to show their name or not; admins show as
  /// "Admin".
  Future<void> comment({
    required String broadcastId,
    required Employee me,
    required String text,
    required bool showName,
    String? name,
  }) async {
    final t = text.trim();
    if (t.isEmpty) return;
    // Sample broadcast: nothing is saved.
    if (broadcastId.startsWith(DemoData.idPrefix)) return;
    final ref = _updates.doc(broadcastId);
    final batch = _db.batch();
    batch.set(ref.collection('comments').doc(), <String, dynamic>{
      'text': TextCrypto.encrypt(t),
      'admin': me.isManagement,
      // [name]: typed by the employee (no name in the app).
      if (!me.isManagement && showName) 'name': (name ?? me.name).trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(ref, {'commentCount': FieldValue.increment(1)});
    await batch.commit();
  }

  /// When this person last opened the Broadcast list (for "new" counts).
  /// Kept in their private user_state.
  Stream<DateTime?> watchSeenAt(String uid) => _db
      .collection('user_state')
      .doc(uid)
      .snapshots()
      .map((d) => (d.data()?['broadcastsSeenAt'] as Timestamp?)?.toDate())
      .handleError((Object _) {});

  /// Opened the Broadcast list: everything up to now is read.
  Future<void> markSeen(String uid) => _db
      .collection('user_state')
      .doc(uid)
      .set({'broadcastsSeenAt': Timestamp.now()}, SetOptions(merge: true))
      .catchError((Object e) => debugPrint('[Broadcast] markSeen: $e'));

  /// Admin: removes a broadcast (for example sent by mistake).
  Future<void> delete(String id) => id.startsWith(DemoData.idPrefix)
      ? Future<void>.value()
      : _updates.doc(id).delete();
}
