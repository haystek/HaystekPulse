/// Settings you may want to change without touching the screens.
class AppConfig {
  /// `true` = Weekly Pulse open every day (only for testing).
  /// `false` = it opens on the day and time below.

  static const bool pulseOpenEveryDay = false;
  static const int pulseOpenDay = DateTime.monday;
  static const int pulseOpenHour = 12;
  static const int pulseOpenMinute = 30;
  static const int pulseOpenDays = 1;

  /// `true`: management is notified for every Weekly Pulse answer,
  /// including Great and Good (without the employee's pulseOpenEveryDayname).
  /// `false`: only for written Okay or Difficult feedback.
  static const bool notifyManagementOnEveryPulse = false;
  static const bool notifyManagementOnPulseComments = false;
  /// `false`: the employee is notified only when the status becomes
  /// Implemented, as in the proposal. `true`: on every status change.
  static const bool notifyEmployeeOnEveryStatus = true;

  /// How many weeks ahead a phone joins the "pending" reminder group.
  static const int pendingTopicWeeksAhead = 8;

}