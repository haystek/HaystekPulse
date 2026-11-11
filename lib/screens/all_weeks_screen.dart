import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../demo_data.dart';
import '../models/pulse_rating.dart';
import '../models/pulse_totals.dart';
import '../services/pulse_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Inter font for everything on these screens, sheets and dialogs
/// (same as the employee screens).
Widget _withInter(BuildContext context, Widget child) {
  final t = Theme.of(context);
  return Theme(
    data: t.copyWith(
      textTheme: GoogleFonts.plusJakartaSansTextTheme(t.textTheme),
    ),
    child: child,
  );
}

const Color _pageBg = Color(0xFFF5F7FB);
const Color _muted = Color(0xFF5B6578);
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
              fontWeight: FontWeight.w500,
              color: AppColors.ink,
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
                      return _buildList(snap.data!, totalSnap.data!);
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

  Widget _buildList(Map<String, PulseTotals> saved, int realTotal) {
    final thisWeek = PulseService.thisWeekId();
    final weeks = <String, PulseTotals>{
      if (DemoData.on) ...DemoData.weeks(thisWeek),
      ...saved,
    };
    final total = DemoData.on ? DemoData.people : realTotal;
    final selected = widget.selectedWeekId ?? thisWeek;

    // The first week the app was used: the oldest week with answers,
    // or this week when nobody has answered yet.
    var firstWeek = thisWeek;
    for (final id in weeks.keys) {
      if (id.compareTo(firstWeek) < 0) firstWeek = id;
    }

    // Every past week, newest first. Weeks where nobody answered still
    // show, so no week goes missing. This week has its own card on top.
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

    // The chart: up to 7 past weeks, oldest on the left.
    final chartIds = pastIds.take(7).toList().reversed.toList();
    final chartId = _pickChartWeek(chartIds, selected, levelOf);

    final children = <Widget>[
      _ThisWeekCard(
        weekId: thisWeek,
        totals: totalsOf(thisWeek),
        total: total,
        canRemind: widget.onRemind != null,
        sending: _sending,
        reminded: _reminded,
        onRemind: _remind,
        onTap: () => Navigator.of(context).pop(thisWeek),
      ),
    ];

    if (chartId != null) {
      children.add(const SizedBox(height: 16));
      children.add(
        _TrendCard(
          chartIds: chartIds,
          chartId: chartId,
          totalsOf: totalsOf,
          levelOf: levelOf,
          total: total,
          onPick: (id) => setState(() => _chartWeekId = id),
        ),
      );
    }

    // One white card per month. The month name sits above it.
    final months = <String, List<String>>{};
    for (final id in pastIds) {
      months.putIfAbsent(_monthTitle(id), () => []).add(id);
    }
    // A chosen week older than the chart is still highlighted in the list.
    final olderThanChart =
        pastIds.contains(selected) && !chartIds.contains(selected);
    final highlighted = olderThanChart ? selected : chartId;
    months.forEach((month, ids) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
          child: Text(
            month,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
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
              for (final id in ids)
                _WeekRow(
                  weekId: id,
                  totals: totalsOf(id),
                  total: total,
                  highlighted: id == highlighted,
                  onTap: () => Navigator.of(context).pop(id),
                ),
            ],
          ),
        ),
      );
    });

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
      title = _result(totals, total);
      // The window ends at midnight; show it as 11:59 PM of the last day.
      final last = PulseService.closesAt(
        now,
      ).subtract(const Duration(minutes: 1));
      timing = 'Open until ${PulseService.dateTimeLabel(last)}';
    } else {
      title = _result(totals, total);
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
                style: const TextStyle(fontSize: 13, color: onBlue),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(timing, style: const TextStyle(fontSize: 13, color: onBlue)),
              if (!notOpenYet) ...[
                const SizedBox(height: 14),
                _AnswerBlocks(answered: submitted, total: total),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$submitted of $total answered',
                        style: const TextStyle(fontSize: 13, color: onBlue),
                      ),
                    ),
                    Text(
                      left == 0 ? 'Everyone answered' : '$left still to answer',
                      style: const TextStyle(fontSize: 13, color: onBlue),
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
                  fontWeight: FontWeight.w500,
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
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 13, color: _muted)),
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
                            ? FontWeight.w500
                            : FontWeight.w400,
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

///   [ 19 ]  Mostly good                 28/30
///   [ OCT]  19 – 23 Oct                 ▬▬▬▬   >
class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.weekId,
    required this.totals,
    required this.total,
    required this.highlighted,
    required this.onTap,
  });

  final String weekId;
  final PulseTotals totals;
  final int total;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final monday = _mondayOf(weekId);
    final submitted = totals.submitted;
    final title = _result(totals, total);
    final level = _moodLevel(title);
    final share = total <= 0 ? 0.0 : (submitted / total).clamp(0.0, 1.0);

    return Material(
      color: highlighted ? _softBlue : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 72,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                // The date tile: Monday's day and the month, coloured by mood.
                Container(
                  width: 48,
                  height: 52,
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
                          fontWeight: FontWeight.w500,
                          color: _tileTextColor(level),
                        ),
                      ),
                      Text(
                        _monthNames[monday.month - 1].toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          color: _tileTextColor(level),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _shortWeek(weekId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: _muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$submitted/$total',
                        maxLines: 1,
                        style: const TextStyle(fontSize: 13, color: _muted),
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: share,
                          minHeight: 4,
                          backgroundColor: const Color(0xFFE3E8F1),
                          color: AppColors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: Color(0xFF8E97AB),
                ),
              ],
            ),
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
