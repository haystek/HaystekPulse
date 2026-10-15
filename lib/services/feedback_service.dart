import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/employee.dart';
import '../config.dart';
import '../demo_data.dart';
import '../models/feedback_item.dart';
import 'notification_service.dart';
import 'push_sender.dart';
import 'text_crypto.dart';

class FeedbackService {
  FeedbackService._();
  static final FeedbackService instance = FeedbackService._();

  static const int maxTextLength = 2000;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _feedback =>
      _db.collection('feedback');

  /// Who wrote each feedback. Only the author can read their own entries
  /// here. Management cannot read this collection at all.
  CollectionReference<Map<String, dynamic>> get _owners =>
      _db.collection('feedback_owners');

  /// The private link from each entry to the author, for this employee only.
  /// Used after sign-in to join the notification group of every entry
  /// this employee wrote (see NotificationService).
  Future<List<String>> myFeedbackIds(String uid) async {
    final snap = await _owners.where('uid', isEqualTo: uid).get();
    return snap.docs.map((d) => d.id).toList();
  }

  /// Saves a Suggestion Box entry.
  ///
  /// Two documents are written together, with the same ID:
  /// - `feedback/{id}`: what management sees. The name is left out
  ///   when [anonymous] is true.
  /// - `feedback_owners/{id}`: the private link to the author.
  Future<void> submitSuggestion({
    required Employee employee,
    required String text,
    required bool anonymous,
  }) async {
    final ref = _feedback.doc();
    final batch = _db.batch();

    batch.set(ref, <String, dynamic>{
      'source': 'box',
      'text': TextCrypto.encrypt(text.trim()),
      'anonymous': anonymous,
      if (!anonymous) 'authorName': employee.name,
      if (!anonymous) 'authorEmployeeId': employee.employeeId,
      'status': FeedbackStatus.newItem,
      'managementMessage': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.set(_owners.doc(ref.id), <String, dynamic>{
      'uid': employee.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();

    // This phone joins the group for this entry, so the author hears
    // about status changes. Management sends to the group and never
    // learns which phone is in it.
    unawaited(NotificationService.instance.followFeedback(ref.id));

    // Tell management. Not awaited: the employee does not wait for it.
    unawaited(
      PushSender.toTopic(
        NotificationService.topicManagement,
        title: 'New suggestion · Needs reply',
        body: PushSender.shorten(text),
        data: {
          'type': PushSender.typeFeedbackNew,
          'feedbackId': ref.id,
          'source': 'box',
        },
      ),
    );
  }

  /// One entry by its ID, or null if it does not exist.
  Future<FeedbackItem?> fetchById(String id) async {
    final doc = await _feedback.doc(id).get();
    return doc.exists ? FeedbackItem.fromDoc(doc) : null;
  }

  /// All feedback, newest first, updating live. Management only.
  /// While DemoData is on, the sample items are added to the real ones,
  /// so every screen (lists, comments, search) shows them too.
  Stream<List<FeedbackItem>> watchAll() {
    final real = _feedback
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(FeedbackItem.fromDoc).toList());
    if (!DemoData.on) return real;

    late final StreamController<List<FeedbackItem>> controller;
    StreamSubscription<List<FeedbackItem>>? realSub;
    StreamSubscription<void>? demoSub;
    List<FeedbackItem>? last;

    void emit() {
      final items = last;
      if (items == null || controller.isClosed) return;
      final fallback = DateTime.now();
      controller.add(
        [...items, ...DemoData.all()]..sort(
              (a, b) => (b.createdAt ?? fallback)
              .compareTo(a.createdAt ?? fallback),
        ),
      );
    }

    controller = StreamController<List<FeedbackItem>>(
      onListen: () {
        realSub = real.listen(
              (items) {
            last = items;
            emit();
          },
          onError: controller.addError,
        );
        demoSub = DemoData.changes.listen((_) => emit());
      },
      onCancel: () async {
        await realSub?.cancel();
        await demoSub?.cancel();
      },
    );
    return controller.stream;
  }

  /// Management sets the status. The reply is kept for "Implemented"
  /// (required) and "Noted" (optional).
  Future<void> updateStatus({
    required String id,
    required String status,
    required String message,
  }) async {
    final implemented = status == FeedbackStatus.implemented;
    final keepReply = FeedbackStatus.keepsReply(status);
    // Sample items (DemoData) are not in Firestore: keep the change in
    // memory only, and send no notification.
    if (id.startsWith(DemoData.idPrefix)) {
      DemoData.update(id, status, keepReply ? message.trim() : '');
      return;
    }
    await _feedback.doc(id).update(<String, dynamic>{
      'status': status,
      'managementMessage': keepReply && message.trim().isNotEmpty
          ? TextCrypto.encrypt(message.trim())
          : '',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (implemented ||
        status == FeedbackStatus.noted ||
        AppConfig.notifyEmployeeOnEveryStatus) {
      unawaited(_notifyAuthor(id, status, message));
    }
  }

  /// Notifies only the employee who wrote this feedback, through the
  /// group for this entry. Only the author's phone is in that group.
  Future<void> _notifyAuthor(String id, String status, String message) async {
    if (!PushSender.available) return;
    try {
      final implemented = status == FeedbackStatus.implemented;
      final noted = status == FeedbackStatus.noted;
      final hasMessage = message.trim().isNotEmpty;
      await PushSender.toTopic(
        NotificationService.feedbackTopic(id),
        title: implemented
            ? 'Your feedback is Implemented ✅'
            : noted
            ? 'Management has noted your feedback'
            : 'Your feedback is now ${FeedbackStatus.label(status)}',
        body: (implemented || noted) && hasMessage
            ? PushSender.shorten(message)
            : noted
            ? 'Thank you for sharing. Tap to see it in My Feedback.'
            : 'Tap to see it in My Feedback.',
        data: {'type': PushSender.typeFeedbackReply, 'feedbackId': id},
      );
    } catch (_) {
      // The status is already saved. A failed notification is not an error.
    }
  }

  /// Everything this employee has submitted, newest first, updating live.
  /// While DemoData is on, the employee's sample items are added too.
  ///
  /// It first listens to the employee's private owner links, then listens
  /// to each of those feedback entries, so a status change or a reply from
  /// management appears on screen straight away.
  Stream<List<FeedbackItem>> watchMyFeedback(String uid) {
    late final StreamController<List<FeedbackItem>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? ownersSub;
    final docSubs =
    <String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>{};
    final items = <String, FeedbackItem>{};
    final waiting = <String>{};

    void emit() {
      if (controller.isClosed) return;
      // Wait until every entry has arrived once, so the list does not
      // build up one row at a time.
      if (waiting.isNotEmpty) return;
      final fallback = DateTime.now();
      final list = [
        ...items.values,
        if (DemoData.on) ...DemoData.mine(),
      ]..sort(
            (a, b) =>
            (b.createdAt ?? fallback).compareTo(a.createdAt ?? fallback),
      );
      controller.add(list);
    }

    Future<void> stopAll() async {
      await ownersSub?.cancel();
      for (final sub in docSubs.values) {
        await sub.cancel();
      }
      docSubs.clear();
    }

    // Listens to one feedback entry, live.
    // A brand-new entry can be refused for a moment (the server checks
    // its private owner link, which may not be saved yet). Firestore then
    // stops that listener for good, and later status changes and replies
    // would never show. So on an error, try again a few times.
    void listenDoc(String id, [int attempt = 0]) {
      docSubs[id] = _feedback.doc(id).snapshots().listen(
            (doc) {
          waiting.remove(id);
          if (doc.exists) {
            items[id] = FeedbackItem.fromDoc(doc);
          } else {
            items.remove(id);
          }
          emit();
        },
        onError: (Object error) {
          debugPrint('[MyFeedback] $id: $error (try ${attempt + 1})');
          waiting.remove(id);
          emit();
          if (attempt >= 5 || controller.isClosed) return;
          Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)), () {
            // Still wanted, and not replaced meanwhile.
            if (controller.isClosed || !docSubs.containsKey(id)) return;
            docSubs[id]?.cancel();
            listenDoc(id, attempt + 1);
          });
        },
      );
    }

    controller = StreamController<List<FeedbackItem>>(
      onListen: () {
        ownersSub = _owners.where('uid', isEqualTo: uid).snapshots().listen(
              (snap) {
            final current = snap.docs.map((d) => d.id).toSet();

            for (final id in docSubs.keys.toList()) {
              if (!current.contains(id)) {
                docSubs.remove(id)?.cancel();
                items.remove(id);
                waiting.remove(id);
              }
            }

            for (final id in current) {
              if (docSubs.containsKey(id)) continue;
              waiting.add(id);
              listenDoc(id);
            }

            emit();
          },
          onError: (Object error) {
            if (!controller.isClosed) controller.addError(error);
          },
        );
      },
      onCancel: stopAll,
    );

    return controller.stream;
  }
}