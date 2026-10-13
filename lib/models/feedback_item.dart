import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/text_crypto.dart';

/// One document in the `feedback` collection.
///
/// The document never stores who wrote it when `anonymous` is true.
/// The link to the author lives in `feedback_owners/{same id}`, which
/// management cannot read.
///
/// The text and the management reply are stored locked (`enc1:...`) and
/// are unlocked here, so every screen shows readable text.
class FeedbackItem {
  const FeedbackItem({
    required this.id,
    required this.source,
    required this.text,
    required this.anonymous,
    required this.status,
    required this.managementMessage,
    this.authorName,
    this.authorEmployeeId,
    this.rating,
    this.weekId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;

  /// 'box' = Suggestion Box, 'pulse' = Weekly Pulse.
  final String source;
  final String text;
  final bool anonymous;
  final String status;
  final String managementMessage;
  final String? authorName;
  final String? authorEmployeeId;

  /// Only for Weekly Pulse feedback: 'okay' or 'difficult'.
  final String? rating;

  /// Only for Weekly Pulse feedback: the week it belongs to.
  final String? weekId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isFromBox => source == 'box';
  bool get hasReply => managementMessage.trim().isNotEmpty;

  factory FeedbackItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    DateTime? toDate(Object? v) => v is Timestamp ? v.toDate() : null;
    return FeedbackItem(
      id: doc.id,
      source: (data['source'] ?? 'box') as String,
      text: TextCrypto.decrypt((data['text'] ?? '') as String),
      anonymous: (data['anonymous'] ?? false) as bool,
      status: (data['status'] ?? FeedbackStatus.newItem) as String,
      managementMessage:
      TextCrypto.decrypt((data['managementMessage'] ?? '') as String),
      authorName: data['authorName'] as String?,
      authorEmployeeId: data['authorEmployeeId'] as String?,
      rating: data['rating'] as String?,
      weekId: data['weekId'] as String?,
      createdAt: toDate(data['createdAt']),
      updatedAt: toDate(data['updatedAt']),
    );
  }
}

/// The five statuses from the flow, stored as short codes.
class FeedbackStatus {
  static const String newItem = 'new';
  static const String underReview = 'under_review';
  static const String planned = 'planned';
  static const String inProgress = 'in_progress';
  static const String implemented = 'implemented';

  static const List<String> all = [
    newItem,
    underReview,
    planned,
    inProgress,
    implemented,
  ];

  static String label(String status) {
    switch (status) {
      case underReview:
        return 'Under Review';
      case planned:
        return 'Planned';
      case inProgress:
        return 'In Progress';
      case implemented:
        return 'Implemented';
      default:
        return 'New';
    }
  }

  static Color color(String status) {
    switch (status) {
      case underReview:
        return const Color(0xFFB5651D);
      case planned:
        return const Color(0xFF1C5FC0);
      case inProgress:
        return const Color(0xFFD9770B);
      case implemented:
        return const Color(0xFF178A47);
      default:
        return const Color(0xFF8A6A00);

        // here we have to add colors

    }
  }
}