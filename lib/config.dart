/// Settings you may want to change without touching the screens.
class AppConfig {
  /// `true` = Weekly Pulse open every day (only for testing).
  /// `false` = it opens on the day and time below.
  static const bool pulseOpenEveryDay = false;

  // ---- TESTING (Tuesday 6:05 PM, closes at midnight) ----
  static const int pulseOpenDay = DateTime.wednesday;
  static const int pulseOpenHour = 16;// 6 PM
  static const int pulseOpenMinute = 0;
  static const int pulseOpenDays = 1;

  // ---- RELEASE (Friday 5:00 PM to Sunday night) ----
  // static const int pulseOpenDay = DateTime.friday;
  // static const int pulseOpenHour = 17;  // 5 PM
  // static const int pulseOpenMinute = 0;
  // static const int pulseOpenDays = 3;   // Fri + Sat + Sun

  /// `true`: management is notified for every Weekly Pulse answer.
  /// `false`: no Weekly Pulse notifications to management.
  static const bool notifyManagementOnEveryPulse = false;
  static const bool notifyManagementOnPulseComments = false;

  /// `true`: the employee is notified on every status change.
  static const bool notifyEmployeeOnEveryStatus = true;

  /// How many weeks ahead a phone joins the "pending" reminder group.
  static const int pendingTopicWeeksAhead = 8;
}