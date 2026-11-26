import 'dart:async';

import 'models/feedback_item.dart';
import 'models/pulse_rating.dart';
import 'models/pulse_totals.dart';
import 'services/feedback_service.dart';
import 'services/broadcast_service.dart';
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
///
///
/// Sample items can be opened, and their status and reply can be changed,
/// but only in memory: nothing is saved and no notification is sent.
class DemoData {
  static const bool on = false;
  static const int people = 30;
  /// Great, Good, Okay, Difficult. Oldest week first, this week last
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
  /// Samples plus real answers. For the same week the real answers are
  /// added on top of the sample, so testing still shows the summary.
  static Map<String, PulseTotals> withReal(
    String thisWeek,
    Map<String, PulseTotals> real,
  ) {
    final out = weeks(thisWeek);
    real.forEach((id, r) {
      final s = out[id];
      out[id] = s == null
          ? r
          : PulseTotals(
              great: s.great + r.great,
              good: s.good + r.good,
              okay: s.okay + r.okay,
              difficult: s.difficult + r.difficult,
              submitted: s.submitted + r.submitted,
            );
    });
    return out;
  }

  /// Sample items start with this id, so the app never saves them.
  static const String idPrefix = 'demo_';
  static bool isDemo(FeedbackItem item) => item.id.startsWith(idPrefix);
  // -------------------------------------------------------------------
  // Weekly Pulse comment samples (management)
  // -------------------------------------------------------------------
  /// Comment texts for Okay answers (office life, short).
  static const List<String> _okayTexts = [
    'Work was fine, but too many meetings. I had little time to actually code.',
    'The requirements changed twice this week, so I had to redo some work.',
    'Not sure what my priorities are after the team change.',
    'My laptop is very slow. Builds take 20 minutes.',
    'Okay week. The AC in our bay is too cold.',
    'Helping the new joiners took most of my week.',
    'Code reviews are taking two or three days. It slows everything down.',
    'The test server was down twice, so I lost half a day.',
    'Too many small tasks. Hard to focus on one big piece of work.',
    'Okay week, but the canteen queue at 1 PM is very long.',
    'I waited a long time for access to the new project folder.',
    'The daily stand-up runs for 40 minutes. Can we keep it short?',
    'Fine week. The parking was full every morning after 9:30.',
    'I am not clear who approves leave in the new team.',
    'Some tickets have no details, so I spend time asking questions.',
    'Network was slow in the afternoons. Video calls kept dropping.',
  ];

  /// Comment texts for Difficult answers.
  static const List<String> _hardTexts = [
    'Too many late-night calls with the client this week. Hard to switch off.',
    'Very stressful week. The deadline was too tight and I worked late three days.',
    'I’m stuck on a task and don’t know who to ask for help.',
    'The production issue on Tuesday was hard. Nobody knew who was on call.',
    'Travelling to the client site every day this week was tiring.',
    'Not feeling well this week, and it was hard to focus.',
    'I had to work on the weekend to finish the release.',
    'Two people left the team, and their work came to me with no handover.',
    'The client was unhappy and I felt blamed in the call.',
    'I could not take my planned leave because of the deadline.',
    'Too much pressure this week. I felt very tired by Friday.',
    'The new process is confusing and nobody has explained it.',
  ];

  /// Names for comments sent with a name.
  static const List<String> _names = [
    'Ravi Kumar', 'Priya S', 'Karthik M', 'Rahul T', 'Arjun Reddy',
    'Sneha Rao', 'Divya K', 'Meera J', 'Vikram N', 'Anitha P',
  ];

  /// A short admin reply for each status (New has none).
  static String _replyFor(String status) {
    switch (status) {
      case FeedbackStatus.underReview:
        return 'Thanks for telling us. We’re looking into this.';
      case FeedbackStatus.planned:
        return 'Thanks. We’ve planned a fix and will share the date soon.';
      case FeedbackStatus.inProgress:
        return 'We’re working on this now. Thanks for your patience.';
      case FeedbackStatus.implemented:
        return 'This is done now. Thank you for raising it.';
      case FeedbackStatus.noted:
        return 'Thank you for sharing. Please talk to HR anytime if you need support.';
      default:
        return '';
    }
  }

  /// Sample status: this week everything is New; last week some are
  /// New; older weeks are mostly answered.
  static String _statusFor(int weeksAgo, int j) {
    if (weeksAgo == 0) return FeedbackStatus.newItem;
    if (weeksAgo == 1 && j % 3 == 0) return FeedbackStatus.newItem;
    if (weeksAgo >= 2 && j % 9 == 4) return FeedbackStatus.newItem;
    const cycle = [
      FeedbackStatus.implemented,
      FeedbackStatus.inProgress,
      FeedbackStatus.planned,
      FeedbackStatus.underReview,
      FeedbackStatus.noted,
    ];
    return cycle[(j + weeksAgo) % cycle.length];
  }

  /// Sample comments for one week: exactly one for every Okay and every
  /// Difficult answer of that week, so every count matches.
  static List<FeedbackItem> comments(String weekId, String thisWeek) {
    final back = _sample.length - 1;
    var index = -1;
    for (var i = 0; i < _sample.length; i++) {
      if (PulseService.shiftWeek(thisWeek, i - back) == weekId) index = i;
    }
    if (index < 0) return const [];
    final weeksAgo = back - index;
    final okay = _sample[index][2];
    final hard = _sample[index][3];
    final opened = DateTime.parse(weekId);
    final now = DateTime.now();
    return [
      for (var j = 0; j < okay + hard; j++)
        () {
          final isHard = j >= okay;
          final k = isHard ? j - okay : j;
          final text = isHard
              ? _hardTexts[(index * 3 + k) % _hardTexts.length]
              : _okayTexts[(index * 5 + k) % _okayTexts.length];
          final anonymous = (index + j) % 3 == 0;
          final status = _statusFor(weeksAgo, j);
          // Spread over the open days; never in the future.
          var at = opened.add(Duration(hours: 17, minutes: j * 47 % 600));
          if (at.isAfter(now)) at = now.subtract(Duration(minutes: 7 * (j + 1)));
          return _withChanges(
            FeedbackItem(
              id: '$idPrefix${weekId}_$j',
              source: 'pulse',
              text: text,
              anonymous: anonymous,
              authorName: anonymous
                  ? null
                  : _names[(index * 2 + j) % _names.length],
              rating: isHard ? PulseRating.difficult : PulseRating.okay,
              weekId: weekId,
              status: status,
              managementMessage: _replyFor(status),
              createdAt: at,
            ),
          );
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
    (1, 'The parking lights near Gate 2 are not working. It is dark after 7 PM.', false, 'Vikram N', 'HST1034', FeedbackStatus.underReview, 'Thanks for flagging this. Facilities is checking the wiring and will update us by Thursday.'),
    (2, 'Can we have a water dispenser on the 3rd floor? Everyone walks down to the 2nd floor to fill bottles.', false, 'Ravi Kumar', 'HST1001', FeedbackStatus.planned, 'Good point. We’ve ordered one, and it should be installed next week.'),
    (3, 'Laptop chargers keep going missing from the meeting rooms. Can IT keep a few spares?', true, '', '', FeedbackStatus.planned, 'IT will keep 10 spare chargers at the help desk from Monday. Please return them after use.'),
    (4, 'The meeting room booking often clashes. Two teams show up for the same slot.', false, 'Karthik M', 'HST1027', FeedbackStatus.inProgress, 'Thanks for raising this. We’re moving all bookings to the shared calendar from Monday.'),
    (5, 'New joiners wait 3 or 4 days for system access. Can we make this faster?', false, 'Meera J', 'HST1041', FeedbackStatus.inProgress, 'IT and HR are making one checklist so access is ready on day one. It starts with the next batch.'),
    (7, 'Please allow work from home on Fridays.', true, '', '', FeedbackStatus.underReview, 'We’re discussing this with team leads and will share a decision by the end of the month.'),
    (9, 'The washroom on the 2nd floor needs cleaning more often.', true, '', '', FeedbackStatus.implemented, 'Cleaning is now twice a day, at 11 AM and 4 PM. Thanks for telling us.'),
    (12, 'The Wi-Fi is very slow after 4 PM.', false, 'Anitha P', 'HST1009', FeedbackStatus.implemented, 'We upgraded the internet plan last week. Please let us know if it’s still slow.'),
    (15, 'Can we get standing desks for people with back pain?', false, 'Suresh B', 'HST1007', FeedbackStatus.implemented, 'Six standing desks are now in the 3rd floor bay. You can book them at the front desk.'),
    (20, 'Can we have a short team lunch once a month?', false, 'Priya S', 'HST1018', FeedbackStatus.noted, 'Thanks for the idea. We’ve noted it for next quarter’s budget.'),
    (28, 'Can we play music in the pantry?', true, '', '', FeedbackStatus.noted, 'We tried it, but some teams found it distracting. We’ll keep the pantry quiet for now.'),
  ];

  /// Sample Suggestion Box entries, newest first.
  static List<FeedbackItem> suggestions() {
    final now = DateTime.now();
    return [
      for (var i = 0; i < _suggestions.length; i++)
        () {
          final s = _suggestions[i];
          final at = DateTime(
            now.year,
            now.month,
            now.day - s.$1,
            10 + i % 6,
            15 * (i % 4),
          );
          return _withChanges(
            FeedbackItem(
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
            ),
          );
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
    (7, PulseRating.okay),
    (8, PulseRating.difficult),
  ];

  /// When a sample answer was sent: the open day of that week, 7:30 PM.
  static DateTime _answeredAt(int weeksAgo) {
    final weekId = PulseService.shiftWeek(
      PulseService.currentWeekId(),
      -weeksAgo,
    );
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
    (2, 'Very stressful week. The deadline was too tight and I worked late three days.', true, FeedbackStatus.underReview, 'Thank you for telling us. If you’re comfortable, please share your name here so we can help you with the workload. Sharing it is your choice.'),
    (4, 'Okay week. The AC in our bay is too cold.', false, FeedbackStatus.implemented, 'We’ve asked facilities to adjust the temperature.'),
    (5, 'Not feeling well this week, and it was hard to focus.', true, FeedbackStatus.noted, 'Please take care of yourself. You can take leave if you need it, and talk to HR anytime.'),
    (7, 'My laptop is very slow. Builds take 20 minutes.', false, FeedbackStatus.inProgress, 'IT is adding more memory to your laptop this week. A spare laptop is ready at the help desk until then.'),
    (8, 'Travelling to the client site every day this week was tiring.', true, FeedbackStatus.implemented, 'We’re moving some client visits to online calls for the whole team. Thanks for telling us.'),
  ];

  /// (days ago, text, anonymous, status, reply) for sample suggestions.
  /// The first one is New with no reply, to test rows without a reply.
  static const List<(int, String, bool, String, String)> _mySuggestions = [
    (1, 'Can we have a quiet room for calls? The open area is noisy after lunch.', false, FeedbackStatus.newItem, ''),
    (3, 'Can we have a water dispenser on the 3rd floor? Everyone walks down to the 2nd floor to fill bottles.', false, FeedbackStatus.planned, 'Good point. We’ve ordered one, and it should be installed next week.'),
    (5, 'Laptop chargers keep going missing from the meeting rooms. Can IT keep a few spares?', true, FeedbackStatus.planned, 'IT will keep 10 spare chargers at the help desk from Monday. Please return them after use.'),
    (6, 'The meeting room booking often clashes. Two teams show up for the same slot.', false, FeedbackStatus.inProgress, 'Thanks for raising this. We’re moving all bookings to the shared calendar from Monday.'),
    (10, 'Please allow work from home on Fridays.', true, FeedbackStatus.underReview, 'We’re discussing this with team leads and will share a decision by the end of the month.'),
    (13, 'The washroom on the 2nd floor needs cleaning more often.', true, FeedbackStatus.implemented, 'Cleaning is now twice a day, at 11 AM and 4 PM. Thanks for telling us.'),
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
          return _withChanges(
            FeedbackItem(
              id: '${idPrefix}my_box_$i',
              source: 'box',
              text: s.$2,
              anonymous: s.$3,
              status: s.$4,
              managementMessage: s.$5,
              createdAt: at,
              updatedAt: at.add(const Duration(days: 1)),
            ),
          );
        }(),
      for (var i = 0; i < _myComments.length; i++)
        () {
          final c = _myComments[i];
          final weekId = PulseService.shiftWeek(thisWeek, -c.$1);
          final at = _answeredAt(c.$1);
          return _withChanges(
            FeedbackItem(
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
            ),
          );
        }(),
    ];
    final fallback = DateTime.now();
    list.sort(
      (a, b) => (b.createdAt ?? fallback).compareTo(a.createdAt ?? fallback),
    );
    return list;
  }

  // -------------------------------------------------------------------
  // Sample conversations (inside a sample item)
  // -------------------------------------------------------------------

  static FeedbackItem? _find(String id) {
    for (final f in [...all(), ...mine()]) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// The steps an item went through to reach its status.
  static List<String> _path(String status) {
    switch (status) {
      case FeedbackStatus.underReview:
        return const [FeedbackStatus.underReview];
      case FeedbackStatus.planned:
        return const [FeedbackStatus.underReview, FeedbackStatus.planned];
      case FeedbackStatus.inProgress:
        return const [
          FeedbackStatus.underReview,
          FeedbackStatus.planned,
          FeedbackStatus.inProgress,
        ];
      case FeedbackStatus.implemented:
        return const [
          FeedbackStatus.underReview,
          FeedbackStatus.planned,
          FeedbackStatus.inProgress,
          FeedbackStatus.implemented,
        ];
      case FeedbackStatus.noted:
        return const [FeedbackStatus.underReview, FeedbackStatus.noted];
      default:
        return const [];
    }
  }

  /// A sample item's conversation: each status change, admin's reply with
  /// the last one, and for Implemented a short thank-you from the employee.
  static List<ThreadEntry> thread(String id) {
    final item = _find(id);
    if (item == null) return const [];
    final steps = _path(item.status);
    final reply = item.managementMessage.trim();
    if (steps.isEmpty && reply.isEmpty) return const [];

    final now = DateTime.now();
    final start = item.createdAt ?? now.subtract(const Duration(days: 1));
    var end = start.add(const Duration(days: 3));
    if (end.isAfter(now)) end = now;
    final thanks = item.status == FeedbackStatus.implemented;
    final count = (steps.isEmpty ? 1 : steps.length) + (thanks ? 1 : 0);
    final gap = end.difference(start) ~/ (count + 1);
    DateTime at(int i) => start.add(gap * (i + 1));

    final list = <ThreadEntry>[];
    if (steps.isEmpty) {
      list.add(
        ThreadEntry(id: '${id}_t0', fromManagement: true, text: reply, at: at(0)),
      );
    } else {
      for (var i = 0; i < steps.length; i++) {
        final last = i == steps.length - 1;
        list.add(
          ThreadEntry(
            id: '${id}_t$i',
            fromManagement: true,
            text: last ? reply : '',
            status: steps[i],
            at: at(i),
          ),
        );
      }
    }
    if (thanks) {
      list.add(
        ThreadEntry(
          id: '${id}_thanks',
          fromManagement: false,
          text: 'Thank you, this helps a lot.',
          at: at(count - 1),
        ),
      );
    }
    return list;
  }

  /// Live: redraws when the sample's status is changed in the app.
  static Stream<List<ThreadEntry>> watchThread(String id) async* {
    yield thread(id);
    await for (final _ in changes) {
      yield thread(id);
    }
  }

  // -------------------------------------------------------------------
  // Broadcast samples (admin and employee)
  // -------------------------------------------------------------------

  /// (days ago, title, message, [(admin, name or '', text, hours after)]).
  static const List<(int, String, String, List<(bool, String, String, int)>)>
  _broadcasts = [
    (1, 'Quiet room is ready on the 4th floor', 'Book it in the shared calendar, 30 minutes at a time. Thanks for the suggestion!', [
      (false, 'Sneha Rao', 'Thank you! This helps a lot for client calls.', 2),
      (false, '', 'Can we book it for longer meetings too?', 5),
      (true, '', 'For now 30 minutes, so everyone gets a turn. We’ll check again next month.', 7),
    ]),
    (3, 'New water dispenser on the 3rd floor', 'It’s next to the lift. No more walking down to the 2nd floor.', [
      (false, '', 'Finally! Thanks team.', 3),
    ]),
    (5, 'Fire drill on Thursday at 11 AM', 'When the alarm rings, please leave by the nearest stairs and meet at the main gate. It takes about 15 minutes.', [
      (false, '', 'Will the lifts be off during the drill?', 2),
      (true, '', 'Yes, please use the stairs only.', 3),
    ]),
    (8, 'Team lunch on the last Friday of the month', 'Lunch is on us. Please tell your lead about any food preferences by Wednesday.', [
      (false, 'Priya S', 'Please add vegetarian options.', 1),
      (true, '', 'Yes, there will be vegetarian and vegan options.', 4),
    ]),
    (11, 'Standing desks are here', 'Six standing desks are in the 3rd floor bay. You can book them at the front desk.', [
      (false, 'Suresh B', 'Thank you, my back is happy!', 4),
    ]),
    (14, 'Wi-Fi upgrade done', 'We upgraded the internet plan. Please tell us if it is still slow after 4 PM.', []),
    (20, 'New on-call list for production issues', 'The on-call list is now on the team board. Please check your week and swap with a teammate if needed.', [
      (false, 'Sneha Rao', 'This is very helpful. Thank you.', 6),
    ]),
  ];

  static DateTime _bcAt(int daysAgo) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day - daysAgo, 11, 0);
  }

  /// Sample broadcasts, newest first.
  static List<Broadcast> broadcasts() => [
    for (var i = 0; i < _broadcasts.length; i++)
      Broadcast(
        id: '${idPrefix}bc_$i',
        title: _broadcasts[i].$2,
        body: _broadcasts[i].$3,
        createdAt: _bcAt(_broadcasts[i].$1),
        commentCount: _broadcasts[i].$4.length,
      ),
  ];

  /// Comments of one sample broadcast, oldest first.
  static List<BroadcastComment> broadcastComments(String id) {
    for (var i = 0; i < _broadcasts.length; i++) {
      if ('${idPrefix}bc_$i' != id) continue;
      final at = _bcAt(_broadcasts[i].$1);
      return [
        for (var j = 0; j < _broadcasts[i].$4.length; j++)
          BroadcastComment(
            id: '${id}_c$j',
            text: _broadcasts[i].$4[j].$3,
            admin: _broadcasts[i].$4[j].$1,
            name: _broadcasts[i].$4[j].$2.isEmpty ? null : _broadcasts[i].$4[j].$2,
            createdAt: at.add(Duration(hours: _broadcasts[i].$4[j].$4)),
          ),
      ];
    }
    return const [];
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
