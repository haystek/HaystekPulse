import 'package:flutter/material.dart';

/// The four answers to "How was your week?".
class PulseRating {
  static const String great = 'great';
  static const String good = 'good';
  static const String okay = 'okay';
  static const String difficult = 'difficult';

  static const List<String> all = [great, good, okay, difficult];

  /// Okay and Difficult ask one more question. Great and Good do not.
  static bool needsText(String rating) =>
      rating == okay || rating == difficult;

  static String label(String rating) {
    switch (rating) {
      case great:
        return 'Great';
      case good:
        return 'Good';
      case okay:
        return 'Okay';
      default:
        return 'Difficult';
    }
  }

  static String question(String rating) => rating == okay
      ? 'What can we improve?'
      : 'What was difficult, and how can we improve?';

  static IconData icon(String rating) {
    switch (rating) {
      case great:
        return Icons.sentiment_very_satisfied;
      case good:
        return Icons.sentiment_satisfied;
      case okay:
        return Icons.sentiment_neutral;
      default:
        return Icons.sentiment_dissatisfied;
    }
  }

  static Color color(String rating) {
    switch (rating) {
      case great:
        return const Color(0xFF1B4FD8);
      case good:
        return const Color(0xFF4A78E8);
      case okay:
        return const Color(0xFFE0A21B);
      default:
        return const Color(0xFFD9482B);
    }
  }

  static Color tint(String rating) {
    switch (rating) {
      case great:
        return const Color(0xFFE6F7EC);
      case good:
        return const Color(0xFFE6F1FD);
      case okay:
        return const Color(0xFFFEF6DC);
      default:
        return const Color(0xFFFDE7E5);
    }
  }
}
