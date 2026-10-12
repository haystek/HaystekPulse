import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/employee.dart';
import '../config.dart';
import '../models/feedback_item.dart';
import 'notification_service.dart';
import 'push_sender.dart';

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

  /// The author's device address for each feedback, so management's app
  /// can notify that one person. It holds no name and no employee ID.
  CollectionReference<Map<String, dynamic>> get _notify =>
      _db.collection('feedback_notify');

  /// Adds the author's device address to a batch, if this device has one.
  void addNotifyDoc(WriteBatch batch, String feedbackId) {
    final token = NotificationService.instance.token;
    if (token == null) return;
    batch.set(_notify.doc(feedbackId), <String, dynamic>{
      'tokens': [token],
      'createdAt': FieldValue.serverTimestamp(),
    });
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
      'text': text.trim(),
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
    addNotifyDoc(batch, ref.id);

    await batch.commit();

    // Tell management. Not awaited: the employee does not wait for it.
    unawaited(
      PushSender.toTopic(
        NotificationService.topicManagement,
        title: 'New suggestion · Needs reply',
        body: '“${PushSender.shorten(text)}”',
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
  Stream<List<FeedbackItem>> watchAll() {
    return _feedback
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(FeedbackItem.fromDoc).toList());
  }

  /// Management sets the status. The reply is kept only for "Implemented",
  /// where it is required.
  Future<void> updateStatus({
    required String id,
    required String status,
    required String message,
  }) async {
    final implemented = status == FeedbackStatus.implemented;
    await _feedback.doc(id).update(<String, dynamic>{
      'status': status,
      'managementMessage': implemented ? message.trim() : '',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (implemented || AppConfig.notifyEmployeeOnEveryStatus) {
      unawaited(_notifyAuthor(id, status, message));
    }
  }

  /// Notifies only the employee who wrote this feedback.
  Future<void> _notifyAuthor(String id, String status, String message) async {
    if (!PushSender.available) return;
    try {
      final doc = await _notify.doc(id).get();
      final tokens = ((doc.data()?['tokens'] ?? const <dynamic>[]) as List)
          .whereType<String>()
          .toList();
      if (tokens.isEmpty) return;
      final implemented = status == FeedbackStatus.implemented;
      await PushSender.toTokens(
        tokens,
        title: implemented
            ? 'Your feedback is Implemented ✅'
            : 'Your feedback is now ${FeedbackStatus.label(status)}',
        body: implemented
            ? '“${PushSender.shorten(message)}”'
            : 'Tap to see it in My Feedback.',
        data: {'type': PushSender.typeFeedbackReply, 'feedbackId': id},
      );
    } catch (_) {
      // The status is already saved. A failed notification is not an error.
    }
  }

  /// Everything this employee has submitted, newest first, updating live.
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
      final list = items.values.toList()
        ..sort(
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
                onError: (Object _) {
                  waiting.remove(id);
                  emit();
                },
              );
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
