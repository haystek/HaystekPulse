import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../demo_data.dart';
import '../models/pulse_rating.dart';
import '../models/feedback_item.dart';
import '../models/pulse_totals.dart';
import '../services/feedback_service.dart';
import 'feedback_detail_screen.dart';
import '../services/pulse_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Inter font for everything on these screens, sheets and dialogs
/// (same as the employee screens).
Widget _withInter(BuildContext context, Widget child) {
  final t = Theme.of(context);
  return Theme(
    data: t.copyWith(
      textTheme: GoogleFonts.interTextTheme(t.textTheme),
    ),
    child: child,
  );
}

const Color _pageBg = Color(0xFFF5F7FB);
// weeksdark: darker grey, same as the other screens.
const Color _muted = Color(0xCC0E1A3A);
const Color _dark = Color(0xFF111827);
const Color _softBlue = Color(0xFFEEF3FF);
const Color _lightLine = Color(0xFFEEF1F6);
const Color _lowText = Color(0xFFB4430C);
const Color _betterText = Color(0xFF1F4FCC);

/// Management: this week on top, then a mood chart of the last 7 weeks,
/// then every past week grouped by month, newest first.
/// Tap a week in the list to see it on the dashboard.
class AllWeeksScreen extends StatefulWidget {
  const AllWeeksScreen({
    super.key,
    required this.totalEmployees,
    this.selectedWeekId,
    this.onRemind,
  });

  /// How many employees can answer. Used for the "answered" numbers.
  final Future<int> totalEmployees;

  /// The week the dashboard shows now.
  final String? selectedWeekId;

  /// Sends the reminder to people who have not answered yet.
  /// The Remind button is hidden when this is null.
  /// Returns true only when it was really sent.
  final Future<bool> Function()? onRemind;

  @override
  State<AllWeeksScreen> createState() => _AllWeeksScreenState();
}

class _AllWeeksScreenState extends State<AllWeeksScreen> {
  late final Stream<Map<String, PulseTotals>> _weeks;
  Timer? _timer;

  /// The week tapped on the chart.
  String? _chartWeekId;
  bool _sending = false;
  bool _reminded = false;

  /// Past weeks list: [_fAll], [_fReply] or [_fHard].
  String _listFilter = _fAll;

  /// Weekly Pulse comments (for "Reply to N comments" and "to reply").
  late final Stream<List<FeedbackItem>> _comments = FeedbackService.instance
      .watchAll()
      .map((all) => [for (final f in all) if (!f.isFromBox) f]);

  @override
  void initState() {
    super.initState();
    // One document per week in pulse_weeks. Weeks are few, so all of
    // them are read and sorted here.
    _weeks = FirebaseFirestore.instance
        .collection('pulse_weeks')
        .snapshots()
        .map(
          (snap) => {
            for (final doc in snap.docs)
              doc.id: PulseTotals.fromMap(doc.data()),
          },
        );
    // The card changes by itself when the Weekly Pulse opens or closes.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _remind() async {
    final send = widget.onRemind;
    if (send == null || _sending) return;
    setState(() => _sending = true);
    try {
      final sent = await send();
      if (mounted && sent) setState(() => _reminded = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not send the reminder. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Asks first. Only after "Send" is the reminder sent.
  Future<void> _confirmRemind() async {
    final outside = widget.onRemind;
    if (outside != null) {
      // The home screen asks first and shows the result itself.
      setState(() => _sending = true);
      var sent = false;
      try {
        sent = await outside();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _sending = false;
        if (sent) _reminded = true;
      });
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _withInter(
        dialogContext,
        AlertDialog(
          title: const Text('Send a reminder?'),
          content: const Text(
            'Only employees who have not answered this week will receive it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _sending = true);
    var ok = false;
    try {
      ok = await (widget.onRemind ?? PulseService.instance.remindPending)();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (ok) _reminded = true;
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Reminder sent.'
              : 'Could not send the reminder. Please try again.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _withInter(
      context,
      Scaffold(
        backgroundColor: _pageBg,
        appBar: AppBar(
          backgroundColor: _pageBg,
          surfaceTintColor: _pageBg,
          leadingWidth: 68,
          leading: const AppBackButton(),
          titleSpacing: 0,
          title: const Text(
            'All weeks',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
              color: _dark,
            ),
          ),
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: FutureBuilder<int>(
                future: widget.totalEmployees,
                builder: (context, totalSnap) {
                  return StreamBuilder<Map<String, PulseTotals>>(
                    stream: _weeks,
                    builder: (context, snap) {
                      if (snap.hasError || totalSnap.hasError) {
                        return const _Message(
                          'Could not load the weeks. Please go back and try '
                          'again.',
                        );
                      }
                      if (!snap.hasData || !totalSnap.hasData) {
                        return const Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppColors.blue,
                            ),
                          ),
                        );
                      }
                      return StreamBuilder<List<FeedbackItem>>(
                        stream: _comments,
                        builder: (context, cSnap) => _buildList(
                          snap.data!,
                          totalSnap.data!,
                          cSnap.data ?? const <FeedbackItem>[],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList(
    Map<String, PulseTotals> saved,
    int realTotal,
    List<FeedbackItem> comments,
  ) {
    final thisWeek = PulseService.thisWeekId();
    final weeks = <String, PulseTotals>{
      if (DemoData.on) ...DemoData.weeks(thisWeek),
      ...saved,
    };
    final total = DemoData.on ? DemoData.people : realTotal;
    final selected = widget.selectedWeekId ?? thisWeek;
    final now = DateTime.now();

    // The first week the app was used: the oldest week with answers,
    // or this week when nobody has answered yet.
    var firstWeek = thisWeek;
    for (final id in weeks.keys) {
      if (id.compareTo(firstWeek) < 0) firstWeek = id;
    }

    // Every past week, newest first.
    final pastIds = <String>[];
    for (
      var id = PulseService.shiftWeek(thisWeek, -1);
      id.compareTo(firstWeek) >= 0;
      id = PulseService.shiftWeek(id, -1)
    ) {
      pastIds.add(id);
    }

    PulseTotals totalsOf(String id) => weeks[id] ?? const PulseTotals();
    int? levelOf(String id) => _moodLevel(_result(totalsOf(id), total));

    // Weekly Pulse comments by week.
    final byWeek = <String, List<FeedbackItem>>{};
    for (final c in comments) {
      final w = c.weekId;
      if (w != null) byWeek.putIfAbsent(w, () => []).add(c);
    }
    int needReplyOf(String id) =>
        (byWeek[id] ?? const <FeedbackItem>[]).where((c) => !c.hasReply).length;

    final thisTotals = totalsOf(thisWeek);
    final left = (total - thisTotals.submitted).clamp(0, total);
    final lastWeek = PulseService.shiftWeek(thisWeek, -1);

    // To do: only what needs the admin now.
    final todos = <_Todo>[];
    if (PulseService.isOpen(now) && total > 0 && left > 0) {
      final closes = PulseService.closesAt(
        now,
      ).subtract(const Duration(minutes: 1));
      todos.add(
        _Todo(
          icon: Icons.notifications_none,
          tint: _softBlue,
          iconColor: AppColors.blue,
          title: 'Remind $left ${left == 1 ? 'person' : 'people'}',
          sub: 'Weekly Pulse closes ${PulseService.dateTimeLabel(closes)}',
          action: _reminded ? 'Sent ✓' : 'Remind',
          onTap: _reminded || _sending ? null : _confirmRemind,
        ),
      );
    }
    final waiting = [
      for (final c in comments)
        if (!c.hasReply) c,
    ]..sort((a, b) => (a.createdAt ?? now).compareTo(b.createdAt ?? now));
    if (waiting.isNotEmpty) {
      final oldest = waiting.first;
      final days = now.difference(oldest.createdAt ?? now).inDays;
      todos.add(
        _Todo(
          icon: Icons.chat_bubble_outline,
          tint: const Color(0xFFFFF2E6),
          iconColor: const Color(0xFFB45309),
          title: waiting.length == 1
              ? 'Reply to 1 comment'
              : 'Reply to ${waiting.length} comments',
          sub: days <= 0
              ? 'Oldest is from today'
              : (days == 1
                    ? 'Oldest is 1 day old'
                    : 'Oldest is $days days old'),
          action: 'See ›',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const _NeedsReplyScreen()),
          ),
        ),
      );
    }
    String? hardId;
    for (final id in pastIds.take(8)) {
      final l = levelOf(id);
      if (l != null && l <= _mixedLevel) {
        hardId = id;
        break;
      }
    }
    if (hardId != null) {
      final id = hardId;
      final d = totalsOf(id).countFor(PulseRating.difficult);
      todos.add(
        _Todo(
          icon: Icons.warning_amber_rounded,
          tint: const Color(0xFFFDE8E3),
          iconColor: const Color(0xFFC2410C),
          title: 'Look at week of ${_dayMonth(id)}',
          sub: d > 0
              ? '$d ${d == 1 ? 'person' : 'people'} said Difficult'
              : _result(totalsOf(id), total),
          action: 'Open ›',
          onTap: () => Navigator.of(context).pop(id),
        ),
      );
    }

    final children = <Widget>[
      _ThisWeekCard(
        weekId: thisWeek,
        totals: thisTotals,
        total: total,
        // The Remind button is in "To do" now.
        canRemind: false,
        sending: _sending,
        reminded: _reminded,
        onRemind: _remind,
        onTap: () => Navigator.of(context).pop(thisWeek),
      ),
      const SizedBox(height: 14),
      _TodoCard(items: todos),
    ];

    // This week vs last week (only once enough people answered, for
    // privacy – same rule as the result).
    if (levelOf(thisWeek) != null && levelOf(lastWeek) != null) {
      children.add(const SizedBox(height: 14));
      children.add(
        _CompareCard(
          thisWeek: _countsOf(thisTotals),
          lastWeek: _countsOf(totalsOf(lastWeek)),
          soFar: PulseService.isOpen(now),
        ),
      );
    }

    // Last 8 weeks: one bar per week.
    if (pastIds.isNotEmpty) {
      final barIds = [...pastIds.take(7).toList().reversed, thisWeek];
      final picked = _chartWeekId != null && barIds.contains(_chartWeekId)
          ? _chartWeekId!
          : (barIds.contains(selected) ? selected : thisWeek);
      children.add(const SizedBox(height: 14));
      children.add(
        _WeeksCard(
          weekIds: barIds,
          thisWeek: thisWeek,
          selectedId: picked,
          totalsOf: totalsOf,
          levelOf: levelOf,
          total: total,
          onPick: (id) => setState(() => _chartWeekId = id),
          onOpen: (id) => Navigator.of(context).pop(id),
        ),
      );
    }

    // Past weeks.
    final replyIds = [
      for (final id in pastIds)
        if (needReplyOf(id) > 0) id,
    ];
    final hardIds = [
      for (final id in pastIds)
        if ((levelOf(id) ?? 99) <= _mixedLevel) id,
    ];
    final shownIds = _listFilter == _fReply
        ? replyIds
        : _listFilter == _fHard
        ? hardIds
        : pastIds;
    if (pastIds.isNotEmpty) {
      children.add(
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 24, 4, 10),
          child: Text(
            'Past weeks',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _dark,
            ),
          ),
        ),
      );
      children.add(
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _ListChip(
              label: 'All',
              selected: _listFilter == _fAll,
              onTap: () => setState(() => _listFilter = _fAll),
            ),
            _ListChip(
              label: 'Needs reply',
              count: replyIds.length,
              selected: _listFilter == _fReply,
              onTap: () => setState(() => _listFilter = _fReply),
            ),
            _ListChip(
              label: 'Hard weeks',
              count: hardIds.length,
              selected: _listFilter == _fHard,
              onTap: () => setState(() => _listFilter = _fHard),
            ),
          ],
        ),
      );
    }

    final months = <String, List<String>>{};
    for (final id in shownIds) {
      months.putIfAbsent(_monthTitle(id), () => []).add(id);
    }
    months.forEach((month, ids) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Text(
            month.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: _muted,
            ),
          ),
        ),
      );
      children.add(
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              for (var i = 0; i < ids.length; i++) ...[
                if (i > 0)
                  const Divider(height: 1, thickness: 1, color: _lightLine),
                _WeekRow(
                  weekId: ids[i],
                  totals: totalsOf(ids[i]),
                  total: total,
                  highlighted: ids[i] == selected,
                  needReply: needReplyOf(ids[i]),
                  onTap: () => Navigator.of(context).pop(ids[i]),
                ),
              ],
            ],
          ),
        ),
      );
    });

    if (pastIds.isNotEmpty && shownIds.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 8),
          child: Text(
            _listFilter == _fReply
                ? 'Every comment has a reply.'
                : 'No hard weeks.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14.5, color: _muted),
          ),
        ),
      );
    }

    if (pastIds.isEmpty) children.add(const _NoWeeksYet());

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: children,
    );
  }

  /// The tapped week, else the dashboard's week, else the newest week
  /// with a result.
  String? _pickChartWeek(
    List<String> chartIds,
    String selected,
    int? Function(String) levelOf,
  ) {
    if (chartIds.isEmpty) return null;
    if (_chartWeekId != null && chartIds.contains(_chartWeekId)) {
      return _chartWeekId;
    }
    if (chartIds.contains(selected)) return selected;
    for (final id in chartIds.reversed) {
      if (levelOf(id) != null) return id;
    }
    return chartIds.last;
  }
}

// ---------------------------------------------------------------------
// This week
// ---------------------------------------------------------------------

/// The blue card on top. The open and close times come from PulseService,
/// so they follow settings/pulse.
class _ThisWeekCard extends StatelessWidget {
  const _ThisWeekCard({
    required this.weekId,
    required this.totals,
    required this.total,
    required this.canRemind,
    required this.sending,
    required this.reminded,
    required this.onRemind,
    required this.onTap,
  });

  final String weekId;
  final PulseTotals totals;
  final int total;
  final bool canRemind;
  final bool sending;
  final bool reminded;
  final VoidCallback onRemind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const onBlue = Color(0xFFE3EAFF);
    final now = DateTime.now();
    final open = PulseService.isOpen(now);
    final notOpenYet = PulseService.notOpenYet(now);
    final submitted = totals.submitted;
    final left = (total - submitted).clamp(0, total);

    final String title;
    final String timing;
    if (notOpenYet) {
      title = 'Not open yet';
      timing = 'Opens ${PulseService.dateTimeLabel(PulseService.opensAt(now))}';
    } else if (open) {
      title = total == 0 ? 'No employees yet' : _result(totals, total);
      // The window ends at midnight; show it as 11:59 PM of the last day.
      final last = PulseService.closesAt(
        now,
      ).subtract(const Duration(minutes: 1));
      timing = 'Open until ${PulseService.dateTimeLabel(last)}';
    } else {
      title = total == 0 ? 'No employees yet' : _result(totals, total);
      timing = 'Closed';
    }

    return Material(
      color: AppColors.blue,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'This week, ${_shortWeek(weekId)}',
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: onBlue),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(timing, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: onBlue)),
              if (!notOpenYet && total == 0) ...[
                const SizedBox(height: 10),
                const Text(
                  'Answers show here once employees join.',
                  style: TextStyle(fontSize: 13, color: onBlue),
                ),
              ],
              if (!notOpenYet && total > 0) ...[
                const SizedBox(height: 14),
                _AnswerBlocks(answered: submitted, total: total),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$submitted of $total answered',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ),
                    Text(
                      left == 0 ? 'Everyone answered' : '$left still to answer',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ],
                ),
              ],
              if (open && canRemind && left > 0) ...[
                const SizedBox(height: 14),
                _RemindButton(
                  left: left,
                  sending: sending,
                  reminded: reminded,
                  onPressed: onRemind,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One small block per person, filled for each answer.
/// Above 60 people the blocks get too thin, so it becomes one plain bar.
class _AnswerBlocks extends StatelessWidget {
  const _AnswerBlocks({required this.answered, required this.total});

  final int answered;
  final int total;

  @override
  Widget build(BuildContext context) {
    const empty = Color(0xFF4F76E2);
    if (total <= 0 || total > 60) {
      final share = total <= 0 ? 0.0 : (answered / total).clamp(0.0, 1.0);
      return ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: LinearProgressIndicator(
          value: share,
          minHeight: 10,
          backgroundColor: empty,
          color: Colors.white,
        ),
      );
    }
    return Row(
      children: [
        for (var i = 0; i < total; i++)
          Expanded(
            child: Container(
              height: 10,
              margin: EdgeInsets.only(right: i == total - 1 ? 0 : 2),
              decoration: BoxDecoration(
                color: i < answered ? Colors.white : empty,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    );
  }
}

class _RemindButton extends StatelessWidget {
  const _RemindButton({
    required this.left,
    required this.sending,
    required this.reminded,
    required this.onPressed,
  });

  final int left;
  final bool sending;
  final bool reminded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (reminded) {
      return Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF173FB0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check, size: 18, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'Reminder sent',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ],
        ),
      );
    }
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: sending ? null : onPressed,
        child: SizedBox(
          height: 44,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.notifications_none,
                size: 18,
                color: AppColors.blue,
              ),
              const SizedBox(width: 8),
              Text(
                sending
                    ? 'Sending…'
                    : 'Remind $left ${left == 1 ? 'person' : 'people'}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.blue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Mood chart
// ---------------------------------------------------------------------

/// The chart and three quick numbers.
class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.chartIds,
    required this.chartId,
    required this.totalsOf,
    required this.levelOf,
    required this.total,
    required this.onPick,
  });

  final List<String> chartIds;
  final String chartId;
  final PulseTotals Function(String) totalsOf;
  final int? Function(String) levelOf;
  final int total;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MoodChart(
            weekIds: chartIds,
            selectedId: chartId,
            levelOf: levelOf,
            onPick: onPick,
          ),
          ..._quickNumbers(),
        ],
      ),
    );
  }

  /// Answered %, great weeks and the lowest week, for the weeks on the chart.
  List<Widget> _quickNumbers() {
    final rated = [
      for (final id in chartIds)
        if (levelOf(id) != null) id,
    ];
    if (rated.isEmpty || total <= 0) return const [];

    var answers = 0;
    for (final id in chartIds) {
      answers += totalsOf(id).submitted;
    }
    final percent = (answers / (total * chartIds.length) * 100).round();
    final great = rated.where((id) => levelOf(id) == _greatLevel).length;

    // Newest first, so the latest one wins a tie.
    var lowest = rated.last;
    for (final id in rated.reversed) {
      if (levelOf(id)! < levelOf(lowest)!) lowest = id;
    }
    final monday = _mondayOf(lowest);
    final lowIsBad = levelOf(lowest)! <= _mixedLevel;

    return [
      const SizedBox(height: 14),
      const Divider(height: 1, thickness: 1, color: _lightLine),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(child: _QuickNumber('$percent%', 'Answered')),
          Expanded(
            child: _QuickNumber('$great of ${rated.length}', 'Great weeks'),
          ),
          Expanded(
            child: _QuickNumber(
              '${monday.day} ${_monthNames[monday.month - 1]}',
              'Lowest week',
              color: lowIsBad ? _lowText : AppColors.ink,
            ),
          ),
        ],
      ),
    ];
  }
}

class _QuickNumber extends StatelessWidget {
  const _QuickNumber(this.value, this.label, {this.color = AppColors.ink});

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _muted)),
      ],
    );
  }
}

const double _labelWidth = 50;
const double _rowGap = 24;
const double _plotTop = 12;
const double _plotHeight = 144;
const double _chartHeight = 168;

double _yOfLevel(int level) => _plotTop + (_greatLevel - level) * _rowGap;

class _MoodChart extends StatelessWidget {
  const _MoodChart({
    required this.weekIds,
    required this.selectedId,
    required this.levelOf,
    required this.onPick,
  });

  final List<String> weekIds;
  final String selectedId;
  final int? Function(String) levelOf;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final columnWidth = (width - _labelWidth) / weekIds.length;
        final points = <Offset?>[
          for (var i = 0; i < weekIds.length; i++)
            levelOf(weekIds[i]) == null
                ? null
                : Offset(
                    _labelWidth + columnWidth * (i + 0.5),
                    _yOfLevel(levelOf(weekIds[i])!),
                  ),
        ];

        return SizedBox(
          height: _chartHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _ChartPainter(points: points)),
              ),
              for (var level = _greatLevel; level >= 1; level--)
                Positioned(
                  left: 0,
                  width: _labelWidth - 4,
                  top: _yOfLevel(level) - 8,
                  child: Text(
                    _levelNames[level]!,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 16 / 12,
                      fontWeight: FontWeight.w500,
                      color: _muted,
                    ),
                  ),
                ),
              for (var i = 0; i < weekIds.length; i++)
                Positioned(
                  left: _labelWidth + columnWidth * i,
                  width: columnWidth,
                  top: 0,
                  bottom: 0,
                  child: _ChartColumn(
                    weekId: weekIds[i],
                    level: levelOf(weekIds[i]),
                    selected: weekIds[i] == selectedId,
                    onTap: () => onPick(weekIds[i]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One tappable week on the chart: guide line, dot and date.
class _ChartColumn extends StatelessWidget {
  const _ChartColumn({
    required this.weekId,
    required this.level,
    required this.selected,
    required this.onTap,
  });

  final String weekId;
  final int? level;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final day = _mondayOf(weekId).day;
    final mood = level;
    final size = selected ? 18.0 : 12.0;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Week of ${_shortWeek(weekId)}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, box) {
            return Stack(
              children: [
                if (selected)
                  Positioned(
                    left: box.maxWidth / 2 - 1,
                    width: 2,
                    top: 0,
                    height: _plotHeight,
                    child: const ColoredBox(color: Color(0xFFD5E0FB)),
                  ),
                if (mood != null)
                  Positioned(
                    left: box.maxWidth / 2 - size / 2,
                    top: _yOfLevel(mood) - size / 2,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _dotColor(mood),
                        border: Border.all(
                          width: 2,
                          color: selected
                              ? Colors.white
                              : mood == _mostlyLevel
                              ? const Color(0xFF7FA2F3)
                              : _dotColor(mood),
                        ),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: _dotColor(mood),
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 20,
                  child: Center(
                    child: Text(
                      '$day',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected ? _betterText : _muted,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Grid lines, soft area and line. A week with no result breaks the line.
class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.points});

  final List<Offset?> points;

  @override
  void paint(Canvas canvas, Size size) {
    final runs = <List<Offset>>[];
    var run = <Offset>[];
    for (final p in points) {
      if (p == null) {
        if (run.isNotEmpty) runs.add(run);
        run = <Offset>[];
      } else {
        run.add(p);
      }
    }
    if (run.isNotEmpty) runs.add(run);

    final area = Paint()..color = _softBlue;
    for (final r in runs) {
      if (r.length < 2) continue;
      final path = _curve(r)
        ..lineTo(r.last.dx, _plotHeight)
        ..lineTo(r.first.dx, _plotHeight)
        ..close();
      canvas.drawPath(path, area);
    }

    final grid = Paint()
      ..color = _lightLine
      ..strokeWidth = 1;
    for (var level = _greatLevel; level >= 1; level--) {
      final y = _yOfLevel(level);
      canvas.drawLine(Offset(_labelWidth, y), Offset(size.width, y), grid);
    }

    final line = Paint()
      ..color = AppColors.blue
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final r in runs) {
      if (r.length < 2) continue;
      canvas.drawPath(_curve(r), line);
    }
  }

  /// A smooth line that stays flat at each dot, so it never overshoots.
  Path _curve(List<Offset> r) {
    final path = Path()..moveTo(r.first.dx, r.first.dy);
    for (var i = 1; i < r.length; i++) {
      final a = r[i - 1];
      final b = r[i];
      final midX = (a.dx + b.dx) / 2;
      path.cubicTo(midX, a.dy, midX, b.dy, b.dx, b.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(_ChartPainter oldDelegate) => true;
}

// ---------------------------------------------------------------------
// One week in the list
// ---------------------------------------------------------------------

///   [ 16 ]  A great week                28/30
///   [ NOV]  16 – 20 Nov              answered
///           ▬▬▬▬▬▬ (mood)          ● 2 to reply   >
class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.weekId,
    required this.totals,
    required this.total,
    required this.highlighted,
    required this.onTap,
    this.needReply = 0,
  });

  final String weekId;
  final PulseTotals totals;
  final int total;
  final bool highlighted;
  final VoidCallback onTap;
  final int needReply;

  @override
  Widget build(BuildContext context) {
    final monday = _mondayOf(weekId);
    final submitted = totals.submitted;
    final title = _result(totals, total);
    final level = _moodLevel(title);

    return Material(
      color: highlighted ? _softBlue : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 50,
                decoration: BoxDecoration(
                  color: _tileColor(level),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${monday.day}',
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: _tileTextColor(level),
                      ),
                    ),
                    Text(
                      _monthNames[monday.month - 1].toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _tileTextColor(level),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: _dark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _shortWeek(weekId),
                      style: const TextStyle(fontSize: 12.5, color: _muted),
                    ),
                    // Mood bar only once enough people answered (privacy).
                    if (level != null) ...[
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: _Segments(
                          counts: _countsOf(totals),
                          height: 5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$submitted/$total',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _dark,
                    ),
                  ),
                  const Text(
                    'answered',
                    style: TextStyle(fontSize: 11.5, color: _muted),
                  ),
                  if (needReply > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Color(0xFFB45309),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$needReply to reply',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: Color(0xCC0E1A3A),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How the week went, in a few words. Same rules as the dashboard:
/// the result shows after 25% of people answered (at least 3).
String _result(PulseTotals t, int total) {
  final submitted = t.submitted;
  if (submitted == 0) return 'No answers';
  var needed = (total * 0.25).ceil();
  if (needed < 3) needed = 3;
  if (needed > total) needed = total;
  if (submitted < needed) return 'Not enough answers';
  final good = t.countFor(PulseRating.great) + t.countFor(PulseRating.good);
  final share = good / submitted;
  if (share >= 0.75) {
    return t.countFor(PulseRating.great) > t.countFor(PulseRating.good)
        ? 'A great week'
        : 'A good week';
  }
  if (share > 0.5) return 'Mostly good';
  if (share >= 0.25) return 'A mixed week';
  return t.countFor(PulseRating.okay) > t.countFor(PulseRating.difficult)
      ? 'An okay week'
      : 'A hard week';
}

// ---------------------------------------------------------------------
// Mood levels: 6 is the best. Weeks with no result have no level.
// ---------------------------------------------------------------------

const int _greatLevel = 6;
const int _mostlyLevel = 4;
const int _mixedLevel = 3;

const Map<int, String> _levelNames = {
  6: 'Great',
  5: 'Good',
  4: 'Mostly',
  3: 'Mixed',
  2: 'Okay',
  1: 'Hard',
};

int? _moodLevel(String result) {
  switch (result) {
    case 'A great week':
      return 6;
    case 'A good week':
      return 5;
    case 'Mostly good':
      return 4;
    case 'A mixed week':
      return 3;
    case 'An okay week':
      return 2;
    case 'A hard week':
      return 1;
    default:
      return null;
  }
}

Color _dotColor(int level) {
  switch (level) {
    case 6:
      return AppColors.blue;
    case 5:
      return const Color(0xFF7FA2F3);
    case 4:
      return const Color(0xFFB9CCF9);
    case 3:
      return const Color(0xFFD9580F);
    case 2:
      return const Color(0xFFC2410C);
    default:
      return const Color(0xFF9A2F06);
  }
}

Color _tileColor(int? level) {
  switch (level) {
    case 6:
      return AppColors.blue;
    case 5:
      return const Color(0xFFBFD2FB);
    case 4:
      return const Color(0xFFE7EEFE);
    case 3:
      return const Color(0xFFFBD9B5);
    case 2:
      return const Color(0xFFF7BE8A);
    case 1:
      return const Color(0xFFC2410C);
    default:
      return const Color(0xFFF2F5FA);
  }
}

Color _tileTextColor(int? level) {
  switch (level) {
    case 6:
    case 1:
      return Colors.white;
    case 3:
    case 2:
      return const Color(0xFF5A2A05);
    case 5:
    case 4:
      return const Color(0xFF14213D);
    default:
      return AppColors.ink;
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------

const List<String> _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const List<String> _longMonthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

DateTime _mondayOf(String weekId) {
  final p = weekId.split('-').map(int.parse).toList();
  final d = DateTime(p[0], p[1], p[2]);
  return DateTime(d.year, d.month, d.day - (d.weekday - 1));
}

/// "5 – 9 Oct" or "28 Sep – 2 Oct".
String _shortWeek(String weekId) {
  final monday = _mondayOf(weekId);
  final friday = DateTime(monday.year, monday.month, monday.day + 4);
  if (monday.month == friday.month) {
    return '${monday.day} – ${friday.day} ${_monthNames[friday.month - 1]}';
  }
  return '${monday.day} ${_monthNames[monday.month - 1]} – '
      '${friday.day} ${_monthNames[friday.month - 1]}';
}

/// "October 2026": the month the week's Friday falls in.
String _monthTitle(String weekId) {
  final monday = _mondayOf(weekId);
  final friday = DateTime(monday.year, monday.month, monday.day + 4);
  final name = _longMonthNames[friday.month - 1];
  return friday.year == DateTime.now().year ? name : '$name ${friday.year}';
}

/// Shown under the blue card when there are no past weeks yet.
class _NoWeeksYet extends StatelessWidget {
  const _NoWeeksYet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: Color(0xFFEAF0FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.insights_outlined,
              size: 32,
              color: AppColors.blue,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'No past weeks yet',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'After the first Weekly Pulse closes, each week and the mood chart show here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.45, color: _muted),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Helpful for admin: To do, This week vs last week, Last 8 weeks
// ---------------------------------------------------------------------

const String _fAll = 'all';
const String _fReply = 'reply';
const String _fHard = 'hard';

const List<String> _moodOrder = [
  PulseRating.great,
  PulseRating.good,
  PulseRating.okay,
  PulseRating.difficult,
];

const List<String> _moodNames = ['Great', 'Good', 'Okay', 'Difficult'];

const List<Color> _mixColors = [
  AppColors.blue,
  Color(0xFF7FA2F3),
  Color(0xFFE2A93B),
  Color(0xFFD9472C),
];

/// Great, Good, Okay, Difficult counts of one week.
List<int> _countsOf(PulseTotals t) => [
  for (final r in _moodOrder) t.countFor(r),
];

/// "16 Nov".
String _dayMonth(String weekId) {
  final m = _mondayOf(weekId);
  return '${m.day} ${_monthNames[m.month - 1]}';
}

/// The four moods as coloured parts of one bar.
/// [vertical]: Great on top (for the week bars).
class _Segments extends StatelessWidget {
  const _Segments({
    required this.counts,
    this.height = 9,
    this.vertical = false,
  });

  final List<int> counts;
  final double height;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final parts = [
      for (var i = 0; i < 4; i++)
        if (counts[i] > 0)
          Expanded(
            flex: counts[i],
            child: ColoredBox(color: _mixColors[i]),
          ),
    ];
    if (vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: parts,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: parts,
        ),
      ),
    );
  }
}

class _Todo {
  const _Todo({
    required this.icon,
    required this.tint,
    required this.iconColor,
    required this.title,
    required this.sub,
    required this.action,
    required this.onTap,
  });

  final IconData icon;
  final Color tint;
  final Color iconColor;
  final String title;
  final String sub;
  final String action;
  final VoidCallback? onTap;
}

/// "To do": up to three things that need the admin now.
class _TodoCard extends StatelessWidget {
  const _TodoCard({required this.items});

  final List<_Todo> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'To do',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _dark,
                ),
              ),
              const Spacer(),
              if (items.isNotEmpty)
                Text(
                  items.length == 1 ? '1 thing' : '${items.length} things',
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                '👍  All done. Nothing needs you right now.',
                style: TextStyle(fontSize: 14, color: _muted),
              ),
            )
          else
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                const Divider(height: 1, thickness: 1, color: _lightLine),
              _row(items[i]),
            ],
        ],
      ),
    );
  }

  Widget _row(_Todo t) {
    return InkWell(
      onTap: t.onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: t.tint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(t.icon, size: 19, color: t.iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: _dark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    t.sub,
                    style: const TextStyle(fontSize: 12.5, color: _muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              t.action,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: t.onTap == null ? _muted : AppColors.blue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Great / Good / Okay / Difficult: this week and last week side by side.
/// Bars are shares of each week's answers, so a week still open compares
/// fairly with a full one.
class _CompareCard extends StatelessWidget {
  const _CompareCard({
    required this.thisWeek,
    required this.lastWeek,
    required this.soFar,
  });

  final List<int> thisWeek;
  final List<int> lastWeek;
  final bool soFar;

  @override
  Widget build(BuildContext context) {
    final a = thisWeek.fold<int>(0, (x, y) => x + y);
    final b = lastWeek.fold<int>(0, (x, y) => x + y);
    double share(int n, int sum) => sum == 0 ? 0 : n / sum;
    final goodNow = a == 0 ? 0 : ((thisWeek[0] + thisWeek[1]) * 100 / a).round();
    final goodLast = b == 0 ? 0 : ((lastWeek[0] + lastWeek[1]) * 100 / b).round();
    final goodA = thisWeek[0] + thisWeek[1];
    final goodB = lastWeek[0] + lastWeek[1];
    const lastColor = Color(0xFFC9D6FB);

    Widget bar(double v, Color c) => v <= 0
        ? const SizedBox(height: 9)
        : FractionallySizedBox(
            widthFactor: v.clamp(0.03, 1.0),
            alignment: Alignment.centerLeft,
            child: Container(
              height: 9,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          );

    Widget key(Color c, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontSize: 12, color: _muted)),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'This week vs last week',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _dark,
                  ),
                ),
              ),
              if (soFar)
                const Text(
                  'so far',
                  style: TextStyle(fontSize: 12, color: _muted),
                ),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            'How people feel compared with last week.',
            style: TextStyle(fontSize: 12.5, color: _muted),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      _moodNames[i],
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _dark,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        bar(share(thisWeek[i], a), AppColors.blue),
                        const SizedBox(height: 3),
                        bar(share(lastWeek[i], b), lastColor),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${thisWeek[i]}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _dark,
                          ),
                        ),
                        Text(
                          '${lastWeek[i]}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFFA0A7B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              key(AppColors.blue, 'This week ($a)'),
              key(lastColor, 'Last week ($b)'),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F8FB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${goodNow >= goodLast ? '👍' : '👀'}  This week $goodA of $a '
              'people said Great or Good. Last week it was $goodB of $b.',
              style: const TextStyle(fontSize: 13, color: _dark),
            ),
          ),
        ],
      ),
    );
  }
}

/// Last 8 weeks: one bar per week, split by how people felt. Tap a bar
/// to see its numbers; tap the box to open the week.
class _WeeksCard extends StatelessWidget {
  const _WeeksCard({
    required this.weekIds,
    required this.thisWeek,
    required this.selectedId,
    required this.totalsOf,
    required this.levelOf,
    required this.total,
    required this.onPick,
    required this.onOpen,
  });

  final List<String> weekIds;
  final String thisWeek;
  final String selectedId;
  final PulseTotals Function(String) totalsOf;
  final int? Function(String) levelOf;
  final int total;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final picked = totalsOf(selectedId);
    final pickedLevel = levelOf(selectedId);
    final c = _countsOf(picked);
    final pickedName = selectedId == thisWeek
        ? 'This week'
        : 'Week of ${_dayMonth(selectedId)}';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Last ${weekIds.length} weeks',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _dark,
                  ),
                ),
              ),
              const Text(
                'tap a week',
                style: TextStyle(fontSize: 12, color: _muted),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            'Each bar is one week: how people felt.',
            style: TextStyle(fontSize: 12.5, color: _muted),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < weekIds.length; i++)
                  Expanded(child: _barColumn(weekIds[i], i == 0)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (var i = 0; i < 4; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _mixColors[i],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _moodNames[i],
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          Material(
            color: const Color(0xFFF6F8FB),
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onOpen(selectedId),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$pickedName · ${_result(picked, total)}',
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: _dark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            pickedLevel == null
                                ? '${picked.submitted} of $total answered'
                                : '${c[0]} Great · ${c[1]} Good · ${c[2]} Okay · '
                                      '${c[3]} Difficult\n${picked.submitted} of '
                                      '$total answered',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: _muted,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Open',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.blue,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppColors.blue,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _barColumn(String id, bool first) {
    final level = levelOf(id);
    final selected = id == selectedId;
    final hard = level != null && level <= _mixedLevel;
    final m = _mondayOf(id);
    final label = id == thisWeek
        ? 'Now'
        : (first ? '${m.day} ${_monthNames[m.month - 1]}' : '${m.day}');
    return Semantics(
      button: true,
      selected: selected,
      label: 'Week of ${_shortWeek(id)}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onPick(id),
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? _dark : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    // Not enough answers yet: an empty grey bar (privacy).
                    child: level == null
                        ? const ColoredBox(
                            color: Color(0xFFF0F2F7),
                            child: SizedBox.expand(),
                          )
                        : _Segments(
                            counts: _countsOf(totalsOf(id)),
                            vertical: true,
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.visible,
              softWrap: false,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected || hard || id == thisWeek
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: selected
                    ? AppColors.blue
                    : (hard ? _lowText : _muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// All / Needs reply / Hard weeks.
class _ListChip extends StatelessWidget {
  const _ListChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _dark : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? _dark : const Color(0xFFE3E8F1),
          width: 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: Text(
            count == null ? label : '$label  $count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? Colors.white : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// Weekly Pulse comments with no reply yet, oldest first. Tap one to
/// read it and reply.
class _NeedsReplyScreen extends StatelessWidget {
  const _NeedsReplyScreen();

  @override
  Widget build(BuildContext context) {
    return _withInter(
      context,
      Scaffold(
        backgroundColor: _pageBg,
        appBar: AppBar(
          backgroundColor: _pageBg,
          surfaceTintColor: _pageBg,
          leadingWidth: 68,
          leading: const AppBackButton(),
          titleSpacing: 0,
          title: const Text(
            'Needs a reply',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _dark,
            ),
          ),
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: StreamBuilder<List<FeedbackItem>>(
                stream: FeedbackService.instance.watchAll(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return const _Message(
                      'Could not load the comments. Please go back and try '
                      'again.',
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.blue,
                        ),
                      ),
                    );
                  }
                  final now = DateTime.now();
                  final items = [
                    for (final f in snap.data!)
                      if (!f.isFromBox && !f.hasReply) f,
                  ]..sort(
                      (a, b) => (a.createdAt ?? now).compareTo(b.createdAt ?? now),
                    );
                  if (items.isEmpty) {
                    return const _Message('Every comment has a reply. 👍');
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                        child: Text(
                          '${items.length} Weekly Pulse '
                          '${items.length == 1 ? 'comment' : 'comments'}, '
                          'oldest first.',
                          style: const TextStyle(fontSize: 13.5, color: _muted),
                        ),
                      ),
                      for (final f in items) _CommentCard(item: f),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One comment: who (or Anonymous), date, the text, its week, how long
/// it has waited, and the mood.
class _CommentCard extends StatelessWidget {
  const _CommentCard({required this.item});

  final FeedbackItem item;

  @override
  Widget build(BuildContext context) {
    final d = item.createdAt;
    final date = d == null ? '' : '${d.day} ${_monthNames[d.month - 1]}';
    final days = d == null ? 0 : DateTime.now().difference(d).inDays;
    final waited = days <= 0
        ? 'From today'
        : (days == 1 ? 'Waiting 1 day' : 'Waiting $days days');
    final rating = item.rating;
    final difficult = rating == PulseRating.difficult;
    final moodFg = difficult ? const Color(0xFFC2410C) : const Color(0xFFB7791F);
    final moodBg = difficult ? const Color(0xFFFDE8E3) : const Color(0xFFFFF6E5);
    final name = (item.authorName ?? '').trim();
    final week = item.weekId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE3E8F1)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => FeedbackDetailScreen(item: item),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: const Color(0xFFF5F7FB),
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                child: Row(
                  children: [
                    Icon(
                      item.anonymous
                          ? Icons.lock_outline_rounded
                          : Icons.person_rounded,
                      size: 16,
                      color: _muted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.anonymous
                            ? 'Anonymous'
                            : (name.isEmpty ? 'With name' : name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: _dark,
                        ),
                      ),
                    ),
                    Text(
                      date,
                      style: const TextStyle(fontSize: 13, color: _muted),
                    ),
                    const Icon(Icons.chevron_right, size: 18, color: _muted),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.text.trim(),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: _dark,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            [
                              if (week != null) 'Week of ${_dayMonth(week)}',
                              waited,
                            ].join(' · '),
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ),
                        if (rating != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: moodBg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              PulseRating.label(rating).toUpperCase(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.6,
                                color: moodFg,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

