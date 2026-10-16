import 'dart:async';

import 'models/feedback_item.dart';
import 'models/pulse_rating.dart';
import 'models/pulse_totals.dart';
import 'services/pulse_service.dart';

/// Sample data, so the app can be shown before real answers come in.
/// Turn it OFF before release: `on = false`.
///
/// Management: [weeks], [comments], [suggestions] (see below).
/// Employee: [mine] and [myAnswers] fill "Your feedback", My Feedback
/// and the Notifications screen of every employee.
///
/// - [people]: how many employees the dashboard counts.
/// - [weeks]: totals for the last 8 weeks and for this week. Real answers
///   from Firestore always replace the sample for the same week.
/// - [comments]: a few written Weekly Pulse comments for each sample week.
/// - [suggestions]: sample Suggestion Box entries.
/// Sample items can be opened, and their status and reply can be changed,
/// but only in memory: nothing is saved and no notification is sent.
class DemoData {
  static const bool on = false;
  static const int people = 30;

  /// Great, Good, Okay, Difficult. Oldest week first, this week last.
  /// The weeks are different on purpose: good, mixed, a hard one, and a
  /// great one, so the week cards and headlines show every case.
  static const List<List<int>> _sample = [
    [9, 11, 5, 2], //  8 weeks ago: A good week
    [12, 10, 4, 1], // 7 weeks ago: A good week
    [7, 9, 8, 4], //   6 weeks ago: Mostly good
    [15, 9, 2, 0], //  5 weeks ago: A great week
    [10, 12, 4, 2], // 4 weeks ago: A good week
    [4, 7, 11, 7], //  3 weeks ago: A hard week
    [8, 11, 6, 3], //  2 weeks ago: Mostly good
    [13, 10, 3, 2], // last week:   A good week
    [9, 5, 3, 1], //   this week:   18 of 30 so far, still open
  ];

  static Map<String, PulseTotals> weeks(String thisWeek) {
    final back = _sample.length - 1;
    return {
      for (var i = 0; i < _sample.length; i++)
        PulseService.shiftWeek(thisWeek, i - back): PulseTotals(
          great: _sample[i][0],
          good: _sample[i][1],
          okay: _sample[i][2],
          difficult: _sample[i][3],
          submitted: _sample[i].reduce((a, b) => a + b),
        ),
    };
  }

  /// Sample items start with this id, so the app never saves them.
  static const String idPrefix = 'demo_';

  static bool isDemo(FeedbackItem item) => item.id.startsWith(idPrefix);

  // -------------------------------------------------------------------
  // Weekly Pulse comment samples (management)
  // -------------------------------------------------------------------

  /// (rating, text, anonymous, name, status, reply) for each sample
  /// comment. The two "New" ones have no reply, to test "Needs reply".
  static const List<(String, String, bool, String, String, String)>
  _comments = [
    // New, no reply yet.
    (PulseRating.difficult, 'Too many late-night calls with the client this week. Hard to switch off.', true, '', FeedbackStatus.newItem, ''),
    // Okay.
    (PulseRating.okay, 'Work was fine, but too many meetings. I had little time to actually code.', false, 'Ravi Kumar', FeedbackStatus.planned, 'Thanks for sharing. We’re trying no-meeting Wednesday afternoons from next week.'),
    // Difficult.
    (PulseRating.difficult, 'Very stressful week. The deadline was too tight and I worked late three days.', true, '', FeedbackStatus.underReview, 'Thank you for telling us. Your manager will talk with you this week about the workload and timelines.'),
    // Okay.
    (PulseRating.okay, 'The requirements changed twice this week, so I had to redo some work.', false, 'Priya S', FeedbackStatus.inProgress, 'Sorry about that. We’ve asked the product team to finalise requirements before the sprint starts.'),
    // Difficult.
    (PulseRating.difficult, 'I’m stuck on a task and don’t know who to ask for help.', false, 'Karthik M', FeedbackStatus.inProgress, 'We’ve assigned a senior developer to pair with you. They’ll reach out today.'),
    // New, no reply yet.
    (PulseRating.okay, 'Not sure what my priorities are after the team change.', true, '', FeedbackStatus.newItem, ''),
    // Okay.
    (PulseRating.okay, 'Okay week. The AC in our bay is too cold.', false, 'Arjun Reddy', FeedbackStatus.implemented, 'We’ve asked facilities to adjust the temperature.'),
    // Difficult.
    (PulseRating.difficult, 'The production issue on Tuesday was hard. Nobody knew who was on call.', false, 'Sneha Rao', FeedbackStatus.implemented, 'We’ve now made an on-call list and shared it with everyone.'),
    // Difficult.
    (PulseRating.difficult, 'Not feeling well this week, and it was hard to focus.', true, '', FeedbackStatus.noted, 'Please take care of yourself. You can take leave if you need it, and talk to HR anytime.'),
  ];

  /// Sample comments for one week (none for weeks without sample totals).
  static List<FeedbackItem> comments(String weekId, String thisWeek) {
    final back = _sample.length - 1;
    var index = -1;
    for (var i = 0; i < _sample.length; i++) {
      if (PulseService.shiftWeek(thisWeek, i - back) == weekId) index = i;
    }
    if (index < 0) return const [];
    final open = _sample[index][2] + _sample[index][3];
    final count = open < 2 ? 1 : (open < 6 ? 2 : (index == back ? 3 : 4));
    final week = DateTime.parse(weekId);
    return [
      for (var j = 0; j < count; j++)
            () {
          final c = _comments[(index * 2 + j) % _comments.length];
          return _withChanges(FeedbackItem(
            id: '$idPrefix${weekId}_$j',
            source: 'pulse',
            text: c.$2,
            anonymous: c.$3,
            authorName: c.$3 ? null : c.$4,
            rating: c.$1,
            weekId: weekId,
            status: c.$5,
            managementMessage: c.$6,
            createdAt: week.add(Duration(hours: 18 + j * 5)),
          ));
        }(),
    ];
  }

  // -------------------------------------------------------------------
  // Suggestion Box samples (management)
  // -------------------------------------------------------------------

  /// (days ago, text, anonymous, name, employee ID, status, reply).
  /// The two "New" ones have no reply, to test "Needs reply".
  static const List<(int, String, bool, String, String, String, String)>
  _suggestions = [
    (0, 'Can we have a quiet room for calls? The open area is very noisy after lunch.', false, 'Sneha Rao', 'HST1012', FeedbackStatus.newItem, ''),
    (1, 'Please add more vegetarian options in the canteen on Fridays.', true, '', '', FeedbackStatus.newItem, ''),
    (2, 'Can we have a water dispenser on the 3rd floor? Everyone walks down to the 2nd floor to fill bottles.', false, 'Ravi Kumar', 'HST1001', FeedbackStatus.planned, 'Good point. We’ve ordered one, and it should be installed next week.'),
    (4, 'The meeting room booking often clashes. Two teams show up for the same slot.', false, 'Karthik M', 'HST1027', FeedbackStatus.inProgress, 'Thanks for raising this. We’re moving all bookings to the shared calendar from Monday.'),
    (7, 'Please allow work from home on Fridays.', true, '', '', FeedbackStatus.underReview, 'We’re discussing this with team leads and will share a decision by the end of the month.'),
    (12, 'The Wi-Fi is very slow after 4 PM.', false, 'Anitha P', 'HST1009', FeedbackStatus.implemented, 'We upgraded the internet plan last week. Please let us know if it’s still slow.'),
    (20, 'Can we have a short team lunch once a month?', false, 'Priya S', 'HST1018', FeedbackStatus.noted, 'Thanks for the idea. We’ve noted it for next quarter’s budget.'),
  ];

  /// Sample Suggestion Box entries, newest first.
  static List<FeedbackItem> suggestions() {
    final now = DateTime.now();
    return [
      for (var i = 0; i < _suggestions.length; i++)
            () {
          final s = _suggestions[i];
          final at = DateTime(now.year, now.month, now.day - s.$1, 10 + i % 6, 15 * (i % 4));
          return _withChanges(FeedbackItem(
            id: '${idPrefix}box_$i',
            source: 'box',
            text: s.$2,
            anonymous: s.$3,
            authorName: s.$3 ? null : s.$4,
            authorEmployeeId: s.$3 ? null : s.$5,
            status: s.$6,
            managementMessage: s.$7,
            createdAt: at,
            updatedAt: at,
          ));
        }(),
    ];
  }

  // -------------------------------------------------------------------
  // Changes made in the app to sample items (memory only)
  // -------------------------------------------------------------------

  static final Map<String, (String, String)> _changes = {};
  static final StreamController<void> _changed =
  StreamController<void>.broadcast();

  /// Fires when a sample item is changed, so open lists redraw.
  static Stream<void> get changes => _changed.stream;

  /// Called by FeedbackService instead of saving to Firestore.
  static void update(String id, String status, String message) {
    _changes[id] = (status, message);
    _changed.add(null);
  }

  /// Every sample item: the comments of all sample weeks and the
  /// suggestions. FeedbackService adds these to the real ones.
  static List<FeedbackItem> all() {
    final thisWeek = PulseService.currentWeekId();
    final back = _sample.length - 1;
    return [
      for (var i = 0; i < _sample.length; i++)
        ...comments(PulseService.shiftWeek(thisWeek, i - back), thisWeek),
      ...suggestions(),
    ];
  }

  // -------------------------------------------------------------------
  // Employee samples: what "I" sent (same for every employee)
  // -------------------------------------------------------------------

  /// (weeks ago, rating) for the employee's sample Weekly Pulse answers.
  /// This week is left out, so the real "Rate your week" still works.
  static const List<(int, String)> _myAnswers = [
    (1, PulseRating.okay),
    (2, PulseRating.difficult),
    (3, PulseRating.great),
    (4, PulseRating.okay),
    (5, PulseRating.difficult),
    (6, PulseRating.good),
  ];

  /// When a sample answer was sent: the open day of that week, 7:30 PM.
  static DateTime _answeredAt(int weeksAgo) {
    final weekId = PulseService.shiftWeek(PulseService.currentWeekId(), -weeksAgo);
    final d = DateTime.parse(weekId);
    return DateTime(d.year, d.month, d.day, 19, 30);
  }

  /// The employee's sample answers: weekId → (rating, sent at).
  static Map<String, (String, DateTime)> myAnswers() {
    final thisWeek = PulseService.currentWeekId();
    return {
      for (final a in _myAnswers)
        PulseService.shiftWeek(thisWeek, -a.$1): (a.$2, _answeredAt(a.$1)),
    };
  }

  /// (weeks ago, text, anonymous, status, reply) for the comments written
  /// with the Okay and Difficult sample answers above.
  static const List<(int, String, bool, String, String)> _myComments = [
    (1, 'Work was fine, but too many meetings. I had little time to actually code.', false, FeedbackStatus.planned, 'Thanks for sharing. We’re trying no-meeting Wednesday afternoons from next week.'),
    (2, 'Very stressful week. The deadline was too tight and I worked late three days.', true, FeedbackStatus.underReview, 'Thank you for telling us. Your manager will talk with you this week about the workload and timelines.'),
    (4, 'Okay week. The AC in our bay is too cold.', false, FeedbackStatus.implemented, 'We’ve asked facilities to adjust the temperature.'),
    (5, 'Not feeling well this week, and it was hard to focus.', true, FeedbackStatus.noted, 'Please take care of yourself. You can take leave if you need it, and talk to HR anytime.'),
  ];

  /// (days ago, text, anonymous, status, reply) for sample suggestions.
  /// The first one is New with no reply, to test rows without a reply.
  static const List<(int, String, bool, String, String)> _mySuggestions = [
    (1, 'Can we have a quiet room for calls? The open area is noisy after lunch.', false, FeedbackStatus.newItem, ''),
    (3, 'Can we have a water dispenser on the 3rd floor? Everyone walks down to the 2nd floor to fill bottles.', false, FeedbackStatus.planned, 'Good point. We’ve ordered one, and it should be installed next week.'),
    (6, 'The meeting room booking often clashes. Two teams show up for the same slot.', false, FeedbackStatus.inProgress, 'Thanks for raising this. We’re moving all bookings to the shared calendar from Monday.'),
    (10, 'Please allow work from home on Fridays.', true, FeedbackStatus.underReview, 'We’re discussing this with team leads and will share a decision by the end of the month.'),
    (15, 'The Wi-Fi is very slow after 4 PM.', false, FeedbackStatus.implemented, 'We upgraded the internet plan last week. Please let us know if it’s still slow.'),
    (24, 'Can we have a short team lunch once a month?', false, FeedbackStatus.noted, 'Thanks for the idea. We’ve noted it for next quarter’s budget.'),
  ];

  /// Everything the employee "sent": sample suggestions and the comments
  /// of the sample Weekly Pulse answers, newest first.
  static List<FeedbackItem> mine() {
    final now = DateTime.now();
    final thisWeek = PulseService.currentWeekId();
    final list = <FeedbackItem>[
      for (var i = 0; i < _mySuggestions.length; i++)
            () {
          final s = _mySuggestions[i];
          final at = DateTime(now.year, now.month, now.day - s.$1, 11, 20);
          return _withChanges(FeedbackItem(
            id: '${idPrefix}my_box_$i',
            source: 'box',
            text: s.$2,
            anonymous: s.$3,
            status: s.$4,
            managementMessage: s.$5,
            createdAt: at,
            updatedAt: at.add(const Duration(days: 1)),
          ));
        }(),
      for (var i = 0; i < _myComments.length; i++)
            () {
          final c = _myComments[i];
          final weekId = PulseService.shiftWeek(thisWeek, -c.$1);
          final at = _answeredAt(c.$1);
          return _withChanges(FeedbackItem(
            id: '${idPrefix}my_pulse_$i',
            source: 'pulse',
            text: c.$2,
            anonymous: c.$3,
            rating: myAnswers()[weekId]?.$1,
            weekId: weekId,
            status: c.$4,
            managementMessage: c.$5,
            createdAt: at,
            updatedAt: at.add(const Duration(days: 2)),
          ));
        }(),
    ];
    final fallback = DateTime.now();
    list.sort(
          (a, b) => (b.createdAt ?? fallback).compareTo(a.createdAt ?? fallback),
    );
    return list;
  }

  static FeedbackItem _withChanges(FeedbackItem f) {
    final c = _changes[f.id];
    if (c == null) return f;
    return FeedbackItem(
      id: f.id,
      source: f.source,
      text: f.text,
      anonymous: f.anonymous,
      authorName: f.authorName,
      authorEmployeeId: f.authorEmployeeId,
      rating: f.rating,
      weekId: f.weekId,
      status: c.$1,
      managementMessage: c.$2,
      createdAt: f.createdAt,
      updatedAt: DateTime.now(),
    );
  }
}