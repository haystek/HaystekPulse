import 'dart:async';

import 'models/feedback_item.dart';
import 'models/pulse_rating.dart';
import 'models/pulse_totals.dart';
import 'services/pulse_service.dart';

/// Sample data, so the management dashboard can be shown before real
/// answers come in. Turn it OFF before release: `on = false`.
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

  /// (rating, text, anonymous, name, status) for each sample comment.
  static const List<(String, String, bool, String, String)> _comments = [
    (PulseRating.difficult, 'Too many late-night calls with the client this week. Hard to switch off.', true, '', FeedbackStatus.newItem),
    (PulseRating.okay, 'Release went fine, but the build server was slow every day.', false, 'Ravi Kumar', FeedbackStatus.underReview),
    (PulseRating.okay, 'Not sure what my priorities are after the team change.', true, '', FeedbackStatus.newItem),
    (PulseRating.difficult, 'Laptop keeps freezing. Lost half a day on Wednesday.', false, 'Priya S', FeedbackStatus.planned),
    (PulseRating.okay, 'Good week overall, but the AC on the 3rd floor is too cold.', false, 'Arjun Reddy', FeedbackStatus.implemented),
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
          final c = _comments[(index + j) % _comments.length];
          return _withChanges(FeedbackItem(
            id: '$idPrefix${weekId}_$j',
            source: 'pulse',
            text: c.$2,
            anonymous: c.$3,
            authorName: c.$3 ? null : c.$4,
            rating: c.$1,
            weekId: weekId,
            // Newer weeks keep "new" comments; older ones look answered.
            status: index == back ? c.$5 : FeedbackStatus.implemented,
            managementMessage: index == back ? '' : 'Thanks, we have looked into this.',
            createdAt: week.add(Duration(hours: 18 + j * 5)),
          ));
        }(),
    ];
  }

  // -------------------------------------------------------------------
  // Suggestion Box samples
  // -------------------------------------------------------------------

  /// (days ago, text, anonymous, name, employee ID, status, reply).
  static const List<(int, String, bool, String, String, String, String)>
  _suggestions = [
    (0, 'Can we have a quiet room for calls? The open area is very noisy after lunch.', false, 'Sneha Rao', 'HST1012', FeedbackStatus.newItem, ''),
    (1, 'Please add more vegetarian options in the canteen on Fridays.', true, '', '', FeedbackStatus.newItem, ''),
    (3, 'A short weekly demo where each team shows what they built would help everyone.', false, 'Karthik M', 'HST1027', FeedbackStatus.underReview, ''),
    (6, 'The second-floor printer jams every day. Maybe time for a new one?', false, 'Anitha P', 'HST1009', FeedbackStatus.planned, ''),
    (9, 'Flexible start time (9 to 10:30) would really help people who travel far.', true, '', '', FeedbackStatus.inProgress, ''),
    (14, 'Water dispenser on the 3rd floor is not cold any more.', false, 'Ravi Kumar', 'HST1001', FeedbackStatus.implemented, 'Fixed on Monday. Thanks for telling us!'),
    (21, 'Can we get a second monitor for developers who ask for it?', false, 'Priya S', 'HST1018', FeedbackStatus.implemented, 'Approved. Ask IT and they will set it up this week.'),
    (33, 'Monthly team lunch would be great for people in different projects to meet.', true, '', '', FeedbackStatus.underReview, ''),
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