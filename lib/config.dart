/// Settings you may want to change without touching the screens.
class AppConfig {
  /// `true` = Weekly Pulse open every day (only for testing).
  /// `false` = it opens on the day and time below.
  static const bool pulseOpenEveryDay = false;


  // ---- TESTING (Tuesday 6:05 PM, closes at midnight) ----
  // Default schedule. The real values come from Firebase: settings/pulse.
  // Change them in the Firebase console; no new build needed.
  static int pulseOpenDay = DateTime.friday;
  static int pulseOpenHour = 17; // 5 PM
  static int pulseOpenMinute = 0;
  static int pulseOpenDays = 3;

  // ---- RELEASE (Friday 5:00 PM to Sunday night) ----
  // static const int pulseOpenDay = DateTime.friday;
  // static const int pulseOpenHour = 17;  // 5 PM
  // static const int pulseOpenMinute = 0;
  // static const int pulseOpenDays = 3;   // Fri + Sat + Sun

  /// `true`: management is notified for every Weekly Pulse answer.
  /// `false`: no Weekly Pulse notifications to management.
  static const bool notifyManagementOnEveryPulse = true;
  static const bool notifyManagementOnPulseComments = true;

  /// `true`: the employee is notified on every status change.
  static const bool notifyEmployeeOnEveryStatus = true;

  /// How many weeks ahead a phone joins the "pending" reminder group.
  static const int pendingTopicWeeksAhead = 8;
}