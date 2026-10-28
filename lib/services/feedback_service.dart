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

/// How long Send may take before the person is told to try again.
const Duration sendLimit = Duration(seconds: 15);

/// Why sending did not work, in words the person understands.
/// The screens show [message] as it is.
class SendError implements Exception {
  const SendError(this.message, {this.alreadyAnswered = false});

  final String message;

  /// Weekly Pulse only: this week was already answered (on any phone).
  final bool alreadyAnswered;

  static const String noInternet =
      'Could not send. Please check your internet connection and try again.';

  /// Turns any error into a [SendError] with the right message:
  /// - no internet or too slow  -> [noInternet]
  /// - not allowed by the server -> [notAllowed]
  /// - anything else             -> "Something went wrong"
  static SendError from(Object error, {required String notAllowed}) {
    if (error is SendError) return error;
    debugPrint('[Send] $error');
    if (error is TimeoutException) return const SendError(noInternet);
    if (error is FirebaseException) {
      switch (error.code) {
        case 'unavailable':
        case 'deadline-exceeded':
        case 'network-request-failed':
          return const SendError(noInternet);
        case 'permission-denied':
        case 'unauthenticated':
          return SendError(notAllowed);
      }
    }
    return const SendError('Something went wrong. Please try again.');
  }

  @override
  String toString() => message;
}

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

  /// A new, unused id for a suggestion. The Suggestion Box takes one when
  /// it opens and uses it for every Send, so tapping Send again after an
  /// error can never make a second copy.
  String newSuggestionId() => _feedback.doc().id;

  /// Saves a Suggestion Box entry, straight on the server.
  ///
  /// Two documents are written together, with the same ID:
  /// - `feedback/{id}`: what management sees. The name is left out
  ///   when [anonymous] is true.
  /// - `feedback_owners/{id}`: the private link to the author.
  ///
  /// It is either saved on the server, or it throws a [SendError] with a
  /// clear message (no internet, not allowed, …) within [sendLimit].
  /// Nothing is kept on the phone to be sent later.
  Future<void> submitSuggestion({
    required Employee employee,
    required String text,
    required bool anonymous,
    String? id,
  }) async {
    final ref = _feedback.doc(id);
    final owner = _owners.doc(ref.id);

    try {
      await _db.runTransaction<void>(
            (tx) async {
          tx.set(ref, <String, dynamic>{
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
          tx.set(owner, <String, dynamic>{
            'uid': employee.uid,
            'createdAt': FieldValue.serverTimestamp(),
          });
        },
        timeout: sendLimit,
        maxAttempts: 3,
      ).timeout(sendLimit + const Duration(seconds: 2));
    } catch (error) {
      // Send tapped again after a try that reached the server late: it
      // is already saved, so that is a success, not an error.
      if (id != null && await _alreadySaved(owner, employee.uid)) {
        // Saved before: carry on as a success.
      } else {
        throw SendError.from(
          error,
          notAllowed: 'This could not be sent. Please sign in again '
              'and try once more.',
        );
      }
    }

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

  /// True if this suggestion is already on the server (its private owner
  /// link exists and is this person's).
  Future<bool> _alreadySaved(
      DocumentReference<Map<String, dynamic>> owner,
      String uid,
      ) async {
    try {
      final doc = await owner
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 5));
      return doc.exists && doc.data()?['uid'] == uid;
    } catch (_) {
      return false;
    }
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

  /// Management sets a new status, with an optional reply.
  /// It is also added to the conversation as "Moved to …", so the
  /// employee sees every step. The latest reply is kept in
  /// `managementMessage` too (lists show "Management replied").
  Future<void> updateStatus({
    required String id,
    required String status,
    required String message,
  }) async {
    final text = message.trim();
    final keepReply = FeedbackStatus.keepsReply(status);
    // Sample items (DemoData) are not in Firestore: keep the change in
    // memory only, and send no notification.
    if (id.startsWith(DemoData.idPrefix)) {
      DemoData.update(id, status, keepReply || text.isNotEmpty ? text : '');
      return;
    }
    final ref = _feedback.doc(id);
    final batch = _db.batch();
    batch.update(ref, <String, dynamic>{
      'status': status,
      if (text.isNotEmpty) 'managementMessage': TextCrypto.encrypt(text),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastFrom': 'm',
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
    batch.set(ref.collection('messages').doc(), <String, dynamic>{
      'from': 'm',
      'status': status,
      'text': text.isEmpty ? '' : TextCrypto.encrypt(text),
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();

    if (status == FeedbackStatus.implemented ||
        status == FeedbackStatus.noted ||
        text.isNotEmpty ||
        AppConfig.notifyEmployeeOnEveryStatus) {
      unawaited(_notifyAuthor(id, status, text));
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
        body: hasMessage
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

  // -------------------------------------------------------------------
  // Conversation: feedback/{id}/messages
  // -------------------------------------------------------------------

  /// One entry, updating live (status changes show at once).
  /// Null for sample items, or when it can't be read.
  Stream<FeedbackItem?> watchOne(String id) {
    if (id.startsWith(DemoData.idPrefix)) return Stream.value(null);
    return _feedback
        .doc(id)
        .snapshots()
        .map((doc) => doc.exists ? FeedbackItem.fromDoc(doc) : null);
  }

  /// The conversation of one entry, oldest first, updating live.
  /// A message still on its way shows as [ThreadEntry.pending].
  Stream<List<ThreadEntry>> watchThread(String id) {
    if (id.startsWith(DemoData.idPrefix)) {
      return Stream.value(const <ThreadEntry>[]);
    }
    return _feedback
        .doc(id)
        .collection('messages')
        .orderBy('createdAt')
        .snapshots(includeMetadataChanges: true)
        .map((snap) => snap.docs.map(ThreadEntry.fromDoc).toList());
  }

  /// Sends one reply in the conversation.
  /// - Employee: no name is added, so a hidden name stays hidden.
  ///   Management gets a notification.
  /// - Management: the employee gets a notification.
  ///
  /// The message shows on screen at once (as "Sending…") and goes to the
  /// server as soon as there is internet. The Future ends when the server
  /// has it; it throws a [SendError] if the server refuses it.
  Future<void> sendMessage({
    required FeedbackItem item,
    required bool fromManagement,
    required String text,
  }) async {
    final t = text.trim();
    if (t.isEmpty) return;
    if (item.id.startsWith(DemoData.idPrefix)) {
      throw const SendError('This is a sample item. Replies work on real '
          'feedback only.');
    }
    final ref = _feedback.doc(item.id);
    final batch = _db.batch();
    batch.set(ref.collection('messages').doc(), <String, dynamic>{
      'from': fromManagement ? 'm' : 'e',
      'text': TextCrypto.encrypt(t),
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(ref, <String, dynamic>{
      if (fromManagement) 'managementMessage': TextCrypto.encrypt(t),
      if (fromManagement) 'updatedAt': FieldValue.serverTimestamp(),
      'lastFrom': fromManagement ? 'm' : 'e',
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
    try {
      await batch.commit();
    } catch (error) {
      throw SendError.from(
        error,
        notAllowed: 'This reply could not be sent. Please sign in again '
            'and try once more.',
      );
    }

    if (fromManagement) {
      unawaited(_notifyReply(item.id, t));
    } else {
      // Tell management. They never learn who sent it.
      unawaited(
        PushSender.toTopic(
          NotificationService.topicManagement,
          title: item.isFromBox
              ? 'New reply · Suggestion'
              : 'New reply · Weekly Pulse',
          body: PushSender.shorten(t),
          data: {
            'type': PushSender.typeFeedbackNew,
            'feedbackId': item.id,
            'source': item.isFromBox ? 'box' : 'pulse',
          },
        ),
      );
    }
  }

  /// Management replied without changing the status.
  Future<void> _notifyReply(String id, String message) async {
    if (!PushSender.available) return;
    try {
      await PushSender.toTopic(
        NotificationService.feedbackTopic(id),
        title: 'Management replied 💬',
        body: PushSender.shorten(message),
        data: {'type': PushSender.typeFeedbackReply, 'feedbackId': id},
      );
    } catch (_) {
      // The reply is already saved. A failed notification is not an error.
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

/// One step in a conversation: a message, or a status change (with an
/// optional message from management).
class ThreadEntry {
  const ThreadEntry({
    required this.id,
    required this.fromManagement,
    required this.text,
    this.status,
    this.at,
    this.pending = false,
  });

  final String id;
  final bool fromManagement;
  final String text;

  /// Set when management moved the entry to this status.
  final String? status;
  final DateTime? at;

  /// Still on its way to the server (no internet yet).
  final bool pending;

  factory ThreadEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final raw = (d['text'] as String?) ?? '';
    return ThreadEntry(
      id: doc.id,
      fromManagement: d['from'] == 'm',
      text: raw.isEmpty ? '' : TextCrypto.decrypt(raw),
      status: d['status'] as String?,
      at: (d['createdAt'] as Timestamp?)?.toDate(),
      pending: doc.metadata.hasPendingWrites,
    );
  }
}